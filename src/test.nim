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

# proc runThings(targ: ThreadArg) {.thread.} =
#   var q = targ.q
#   while true:

#     var job = q[].pop()
#     if job == nil:
#       continue
#     while job.running():
#       job = trampoline job


proc pass(cFrom,cTo: C): C =
  cTo.q = cFrom.q
  return cTo

proc register(c: C): C {.cpsMagic.} =
  # c.q[].push(c)
  return c

proc doContinualThings() {.cps:C.} =
  var orig = getThreadId()
  # echo "WOAH ", orig
  register()
  # echo "COOL ", getThreadId(), " ", orig
  var x = 5


var thr: Thread[ThreadArg]
var work: seq[C]
for i in 0..5:
  var d = whelp doContinualThings()
  d.q = queue
  queue[].push(d)
  echo repr queue[]
  work.add(d)
# createThread(thr, runThings, targ)
# joinThread(thr)
while true:
  var job = queue[].pop()
  while job.running():
    job = trampoline job
    var y = whelp doContinualThings()
    y.q = queue
    work.add(y)
    queue[].push(y)
  echo queue[].repr
echo repr work