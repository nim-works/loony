import cps
import loony

# Moment of truth
var queue = createShared(LoonyQueue)
queue[] = initLoonyQueue()

type
  C = ref object of Continuation
    q: ptr LoonyQueue
  ThreadArg = object
    q: ptr LoonyQueue

var targ = ThreadArg(q: queue)

proc runThings(targ: ThreadArg) {.thread.} =
  var q = targ.q
  var i: int
  while i < 10:
    var job = q[].pop()
    if job == nil:
      inc(i)
      continue
    while job.running():
      job = trampoline job
      i = 0


proc pass(cFrom,cTo: C): C =
  cTo.q = cFrom.q
  return cTo

proc register(c: C): C {.cpsMagic.} =
  c.q[].push(c)
  return nil

proc doContinualThings() {.cps:C.} =
  var orig = getThreadId()
  echo "WOAH ", orig
  register()
  echo "COOL ", getThreadId(), " ", orig
  var x = 5


var thr: Thread[ThreadArg]
# var work: seq[C]
dumpAllocStats:
  for i in 0..50:
    var d = whelp doContinualThings()
    d.q = queue
    queue[].push(d)
    # work.add(d)
  createThread(thr, runThings, targ)
  # joinThread(thr)
  for i in 0..1000:
    var y = whelp doContinualThings()
    y.q = queue
    # work.add(y)
    queue[].push(y)
    var job = queue[].pop()
    while job.running():
      job = trampoline job
  joinThread(thr)
  # echo repr work