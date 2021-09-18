import std/osproc
import std/strutils
import std/logging
import std/atomics
import std/os
import std/macros

import balls
import cps

import loony

const
  continuationCount = when defined(windows): 1_000 else: 10_000
let
  threadCount = when defined(danger): countProcessors() else: 1

type
  C = ref object of Continuation
    q: LoonyQueue[Continuation]
  ThreadArg = object
    q: LoonyQueue[Continuation]

addHandler newConsoleLogger()
setLogFilter:
  when defined(danger):
    lvlNotice
  elif defined(release):
    lvlInfo
  else:
    lvlDebug

proc dealloc(c: C; E: typedesc[C]): E =
  checkpoint "reached dealloc"

proc runThings(targ: ThreadArg) {.thread.} =
  while true:
    var job = pop targ.q
    if job.dismissed:
      break
    else:
      while job.running:
        job = trampoline job

proc pass(cFrom, cTo: C): C =
  cTo.q = cFrom.q
  return cTo

proc enqueue(c: C): C {.cpsMagic.} =
  c.q.push(c)

var counter {.global.}: Atomic[int]

# try to delay a reasonable amount of time despite platform
when defined(windows):
  proc noop(c: C): C {.cpsMagic.} =
    sleep:
      when defined(danger):
        1
      else:
        0 # 🤔
    c
else:
  import posix
  proc noop(c: C): C {.cpsMagic.} =
    const
      ns = when defined(danger): 1_000 else: 10_000
    var x = Timespec(tv_sec: 0.Time, tv_nsec: ns)
    var y: Timespec
    if 0 != nanosleep(x, y):
      raise
    c

proc doContinualThings() {.cps: C.} =
  enqueue()
  noop()
  enqueue()
  discard counter.fetchAdd(1)

template expectCounter(n: int): untyped =
  ## convenience
  try:
    check counter.load == n
  except Exception:
    checkpoint " counter: ", load counter
    checkpoint "expected: ", n
    raise

suite "loony":
  var queue: LoonyQueue[Continuation]

  block:
    ## creation and initialization of the queue

    # Moment of truth
    queue = initLoonyQueue[Continuation]()

  block:
    ## run some continuations through the queue in another thread
    when defined(danger): skip "boring"
    var targ = ThreadArg(q: queue)
    var thr: Thread[ThreadArg]

    counter.store 0
    dumpAllocStats:
      for i in 0 ..< continuationCount:
        var c = whelp doContinualThings()
        c.q = queue
        discard enqueue c
      createThread(thr, runThings, targ)
      joinThread thr
      expectCounter continuationCount

  block:
    ## run some continuations through the queue in many threads
    when not defined(danger): skip "slow"
    var targ = ThreadArg(q: queue)
    var threads: seq[Thread[ThreadArg]]
    threads.newSeq threadCount

    counter.store 0
    dumpAllocStats:
      for i in 0 ..< continuationCount:
        var c = whelp doContinualThings()
        c.q = queue
        discard enqueue c
      checkpoint "queued $# continuations" % [ $continuationCount ]

      for thread in threads.mitems:
        createThread(thread, runThings, targ)
      checkpoint "created $# threads" % [ $threadCount ]

      for thread in threads.mitems:
        joinThread thread
      checkpoint "joined $# threads" % [ $threadCount ]

      expectCounter continuationCount
