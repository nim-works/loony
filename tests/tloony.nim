import std/osproc
import std/strutils
import std/logging
import std/atomics
import std/os
import std/macros
import std/hashes

import balls

import loony
import loony/ward

const
  continuationCount = 10_000
let
  threadCount = 11

type
  Cop = ref object
    r: bool
    e: int

addHandler newConsoleLogger()
setLogFilter:
  when defined(danger):
    lvlNotice
  elif defined(release):
    lvlInfo
  else:
    lvlDebug

var w: LoonyQueue[Cop]
w = newLoonyQueue[Cop]()
var q = w.newWard({PoolWaiter})
var counter {.global.}: Atomic[int]

proc enqueue(c: var Cop) =
  check not q.isNil
  c.r = true
  c.e = c.e + 1
  let v = q.push(c)


proc runThings() {.thread.} =
  while true:
    var job = pop q
    var i: bool
    if job.isNil():
      break
    else:
      if job.e < 3:
        enqueue job
      else:
        discard counter.fetchAdd(1)

template expectCounter(n: int): untyped =
  ## convenience
  try:
    check counter.load == n
  except Exception:
    checkpoint " counter: ", load counter
    checkpoint "expected: ", n
    raise

# suite "loony":

block:
  proc main =
    ## run some ref objects through the queue in many threads
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
        echo "Sleep for a bit"
        sleep(500)
        echo "Lets begin"
        for i in 0 ..< continuationCount:
          var c = new Cop
          c = Cop()
          enqueue c
        checkpoint "queued $# continuations" % [ $continuationCount ]
        sleep(5_000)
        q.killWaiters
        for thread in threads.mitems:
          joinThread thread
        checkpoint "joined $# threads" % [ $threadCount ]

        expectCounter continuationCount
  main()