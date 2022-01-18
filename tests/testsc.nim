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
  continuationCount = when defined(windows): 100_000 else: 100_000
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

var q: LoonyQueue[Continuation]
# var q: SCLoonyQueue[Continuation]


proc enqueue(c: C): C {.cpsMagic.} =
  check not q.isNil
  q.push(c)

var counter {.global.}: Atomic[int]

# try to delay a reasonable amount of time despite platform
when defined(windows):
  proc noop(c: C): C {.cpsMagic.} =
    sleep:
      when defined(danger) and false: # Reduce cont count on windows before adding sleep
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

proc runThings() {.thread.} =
  for i in 0..<(continuationCount div threadCount):
    var c = whelp doContinualThings()
    while c.running:
      c = trampoline c

template expectCounter(n: int): untyped =
  ## convenience
  let tn = (n div threadCount) * threadCount
  try:
    check counter.load == tn
  except Exception:
    checkpoint " counter: ", load counter
    checkpoint "expected: ", tn
    raise
import benchy
timeIt("do the things", 100):
# suite "loony":
# block:
  block:
    ## creation and initialization of the queue

    # Moment of truth
    # q = newSCLoonyQueue[Continuation]()
    q = newLoonyQueue[Continuation]()

  
  block:
    ## run some continuations through the queue in many threads
    # when not defined(danger): skip "slow"
    var threads: seq[Thread[void]]
    newSeq(threads, threadCount)

    counter.store 0
    # dumpAllocStats:
    block:
      for thread in threads.mitems:
        createThread(thread, runThings)
      # checkpoint "created $# threads" % [ $threadCount ]
      while true:
        var job = pop q
        if job.dismissed:
          break
        else:
          while job.running:
            job = trampoline job

      for thread in threads.mitems:
        joinThread thread
      # checkpoint "joined $# threads" % [ $threadCount ]

      expectCounter continuationCount