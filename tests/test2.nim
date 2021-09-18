import std/os
import std/atomics

import cps
import loony {.all.}

# Moment of truth
var queue = createShared LoonyQueue[Continuation]
initLoonyQueue queue[]

type
  C = ref object of Continuation
    q: ptr LoonyQueue[Continuation]
  ThreadArg = object
    q: ptr LoonyQueue[Continuation]

var targ = ThreadArg(q: queue)

proc runThings(targ: ThreadArg) {.thread.} =
  var q = targ.q
  var i: int
  while i < 50:
    var job = q[].pop()
    if job == nil:
      inc(i)
      continue
    while job.running():
      job = trampoline job
      i = 0
  echo "Finished"


proc pass(cFrom,cTo: C): C =
  cTo.q = cFrom.q
  return cTo

proc register(c: C): C {.cpsMagic.} =
  c.q[].push(c)
  return nil

var counter {.global.}: Atomic[int]
counter.store(0)

proc doContinualThings() {.cps:C.} =
  var orig = getThreadId()
  # echo "WOAH ", orig
  register()
  discard counter.fetchAdd(1)


dumpAllocstats:
  # for i in 0..<5000:
  #   var c = whelp doContinualThings()
  #   c.q = queue
  #   queue[].push(c)
  for i in 0..11000:
    var c = queue[].pop()
    while c.running():
      c = trampoline c
  echo counter.load()
  echo "completed"
