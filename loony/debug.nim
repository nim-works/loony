## Copyright (c) 2021 Shayan Habibi
## 
## Contains the debug tools and counters used in loony

import loony/spec

when defined(loonyDebug):
  import std/logging
  export debug, info, notice, warn, error, fatal
else:
  # use the `$` converter just to ensure that debugging statements compile
  template debug*(args: varargs[untyped, `$`]): untyped = discard
  template info*(args: varargs[untyped, `$`]): untyped = discard
  template notice*(args: varargs[untyped, `$`]): untyped = discard
  template warn*(args: varargs[untyped, `$`]): untyped = discard
  template error*(args: varargs[untyped, `$`]): untyped = discard
  template fatal*(args: varargs[untyped, `$`]): untyped = discard

when defined(loonyDebug):
  ## Provided are atomic counters and templates/functions which assist measuring
  ## memory leaks with loony. This is primarily used when debugging the algorithm
  ## and is unlikely to be required by end-users. There is a cost in using these
  ## functions as they use costly atomic writes.
  var nodeCounter* {.global.}: int
  var reclaimCounter* {.global.}: int
  var recPathCounter* {.global.}: int
  var enqCounter* {.global.}: int
  var deqCounter* {.global.}: int
  var enqPathCounter* {.global.}: int
  var deqPathCounter* {.global.}: int
  nodeCounter.store(0); reclaimCounter.store(0)
  enqCounter.store(0);  deqCounter.store(0)
  recPathCounter.store(0); enqPathCounter.store(0)
  deqPathCounter.store(0)

  proc echoDebugNodeCounter*() =
    ## This will output the counter
    notice "Node counter: " & $nodeCounter.load()

  template debugNodeCounter*(body: untyped) =
    mixin load
    let (initC, initRec, initRecP, initEnq, initDeq, initEnqP, initDeqP) =
          ( nodeCounter.load(), reclaimCounter.load(),
            recPathCounter.load(), enqCounter.load(),
            deqCounter.load(), enqPathCounter.load(),
            deqPathCounter.load())
    body
    let newC = nodeCounter.load()
    if (newC - initC) > 0:
      warn "Finished block with node count:   " & $(newC - initC)
      notice "Nodes destroyed via reclaim:    " & $(reclaimCounter.load() - initRec)
      notice "Nodes destroyed via deq:        " & $(deqCounter.load() - initDeq)
      notice "Nodes destroyed via enq:        " & $(enqCounter.load() - initEnq)
      notice "Aborted reclaim ops:            " & $(recPathCounter.load() - initRecP)
      notice "Unreclaimed Enq ops:            " & $(enqPathCounter.load() - initEnqP)
      notice "Unreclaimed Deq ops:            " & $(deqPathCounter.load() - initDeqP)

  template incDebugCounter*(): untyped = discard   nodeCounter.fetchAdd(1, Rlx)
  template decDebugCounter*(): untyped = discard   nodeCounter.fetchSub(1, Rlx)
  template incReclaimCounter*(): untyped = discard reclaimCounter.fetchAdd(1, Rlx)
  template incRecPathCounter*(): untyped = discard recPathCounter.fetchAdd(1, Rlx)
  template incEnqCounter*(): untyped = discard     enqCounter.fetchAdd(1, Rlx)
  template incDeqCounter*(): untyped = discard     deqCounter.fetchAdd(1, Rlx)
  template incEnqPathCounter*(): untyped = discard enqPathCounter.fetchAdd(1, Rlx)
  template incDeqPathCounter*(): untyped = discard deqPathCounter.fetchAdd(1, Rlx)
else:
  proc echoDebugNodeCounter*(expected: int = 0) = discard
  template debugNodeCounter*(body: untyped): untyped = body
  template incDebugCounter*(): untyped = discard
  template decDebugCounter*(): untyped = discard
  template incReclaimCounter*(): untyped = discard
  template incRecPathCounter*(): untyped = discard
  template incEnqCounter*(): untyped = discard
  template incDeqCounter*(): untyped = discard
  template incEnqPathCounter*(): untyped = discard
  template incDeqPathCounter*(): untyped = discard
