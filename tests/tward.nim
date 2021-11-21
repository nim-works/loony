import std/osproc
import std/strutils
import std/logging
import std/atomics
import std/os
import std/macros

import balls
import cps

import loony
import loony/ward

const
  continuationCount = 10_000
let
  threadCount = 12

type
  C = ref object of Continuation

addHandler newConsoleLogger()
setLogFilter:
  when defined(danger):
    lvlNotice
  elif defined(release):
    lvlInfo
  else:
    lvlDebug

var w: LoonyQueue[Continuation]
w = initLoonyQueue[Continuation]()
var q = w.newWard({PoolWaiter})


proc runThings() {.thread.} =
  while true:
    var job = pop q
    if job.dismissed:
      break
    else:
      while job.running:
        job = trampoline job

proc enqueue(c: C): C {.cpsMagic.} =
  check not q.isNil
  discard q.push(c)

var counter {.global.}: Atomic[int]

import std/hashes

# try to delay a reasonable amount of time despite platform
when defined(windows):
  proc noop(c: C): C {.cpsMagic.} =
    var i: int
    # while true:
    #   let v = hash i
    #   if i == 300: break
    #   inc i
    # sleep:
    #   when defined(danger) and false: # Reduce cont count on windows before adding sleep
    #     1
    #   else:
    #     # 0
    #     1 # 🤔
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

  block:
    ## run some continuations through the queue in another thread
    skip "boring"
    var thr: Thread[void]

    counter.store 0
    dumpAllocStats:
      for i in 0 ..< continuationCount:
        var c = whelp doContinualThings()
        discard enqueue c
      createThread(thr, runThings)
      joinThread thr
      expectCounter continuationCount

  block:
    ## run some continuations through the queue in many threads
    var threads: seq[Thread[void]]
    newSeq(threads, threadCount)
    counter.store 0
    dumpAllocStats:
      debugNodeCounter:
        # If `loonyDebug` is defined this will output number of nodes you started
        # with - the number of nodes you end with (= non-deallocated nodes)
        for thread in threads.mitems:
          createThread(thread, runThings)
        checkpoint "created $# threads" % [ $threadCount ]
        echo "gonna sleep"
        sleep(5_000)
        echo "passed"
        for i in 0 ..< continuationCount:
          var c = whelp doContinualThings()
          discard enqueue c
        checkpoint "queued $# continuations" % [ $continuationCount ]
        echo "passed 2"
        sleep(5_000)
        echo counter.load()
        for thread in threads.mitems:
          joinThread thread
        checkpoint "joined $# threads" % [ $threadCount ]

        expectCounter continuationCount
