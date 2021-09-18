import std/atomics
import std/os
import std/macros

import balls
import cps

import loony

const
  continuations = 5_000

type
  C = ref object of Continuation
    q: ptr LoonyQueue[Continuation]
  ThreadArg = object
    q: ptr LoonyQueue[Continuation]

proc dealloc(c: C; E: typedesc[C]): E =
  checkpoint "reached dealloc"

proc runThings(targ: ThreadArg) {.thread.} =
  var q = targ.q
  var i: int
  var prev: C
  var str: string
  while i < 50:
    # checkpoint str
    var job = pop q[]
    if job == nil:
      # checkpoint "nil"
      inc(i)
      sleep(50)
    else:
      while job.running():
        job = trampoline job
        str.add('C')
        # checkpoint str
        # checkpoint job.running()
        # i = 0

proc pass(cFrom, cTo: C): C =
  cTo.q = cFrom.q
  return cTo

proc enqueue(c: C): C {.cpsMagic.} =
  c.q[].push(c)

var counter {.global.}: Atomic[int]

proc doContinualThings() {.cps: C.} =
  var orig = getThreadId()
  # checkpoint "WOAH ", orig
  enqueue()
  discard counter.fetchAdd(1)
  enqueue()
  # checkpoint "end"
  orig = 5

suite "loony":
  var queue: ptr LoonyQueue[Continuation]

  block:
    ## creation and initialization of the queue

    # Moment of truth
    queue = createShared LoonyQueue[Continuation]
    initLoonyQueue queue[]

  block:
    ## run some continuations through the queue in another thread
    var targ = ThreadArg(q: queue)
    var thr: Thread[ThreadArg]

    dumpAllocStats:
      for i in 0 ..< continuations:
        var c = whelp doContinualThings()
        c.q = queue
        discard enqueue c
      createThread(thr, runThings, targ)
      joinThread thr
      check counter.load() == continuations
