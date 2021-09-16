import std/atomics
import "."/[alias, constants, controlblock, node]
# Import the holy one
import pkg/cps

# sprinkle some raise defect
# raise Defect(nil)
# raise Defect(nil)
# raise Defect(nil)
# raise Defect(nil)
# raise Defect(nil)

type
  LoonyQueue* = object
    head     : Atomic[TagPtr]     # (NodePtr, idx)    ## Whereby node contains the slots and idx
    tail     : Atomic[TagPtr]     # (NodePtr, idx)    ## is the uint16 index of the slot array
    currTail : Atomic[NodePtr]    # 8 bytes Current NodePtr

  ## Result types for the private
  ## advHead and advTail functions
  AdvTail = enum
    AdvAndInserted, # 0000_0000
    AdvOnly         # 0000_0001
  AdvHead = enum
    QueueEmpty,     # 0000_0000
    Advanced        # 0000_0001

template fetchTail(queue: var LoonyQueue): TagPtr =
  ## get the TagPtr of the tail (nptr: NodePtr, idx: uint16)
  TagPtr(queue.tail.load())

template fetchHead(queue: var LoonyQueue): TagPtr =
  ## get the TagPtr of the head (nptr: NodePtr, idx: uint16)
  TagPtr(queue.head.load())

template fetchCurrTail(queue: var LoonyQueue): NodePtr =
  ## get the NodePtr of the current tail REVIEW why isn't this a TagPtr?
  cast[NodePtr](queue.currTail.load())

template fetchIncTail(queue: var LoonyQueue): TagPtr =
  ## Atomic fetchAdd of Tail TagPtr - atomic inc of idx in (nptr: NodePtr, idx: uint16)
  TagPtr(queue.tail.fetchAdd(1))

template fetchIncHead(queue: var LoonyQueue): TagPtr =
  ## Atomic fetchAdd of Head TagPtr - atomic inc of idx in (nptr: NodePtr, idx: uint16)
  TagPtr(queue.head.fetchAdd(1))

template compareAndSwapTail(queue: var LoonyQueue, expect: var uint, swap: uint | TagPtr): bool =
  queue.tail.compareExchange(expect, swap)
  
template compareAndSwapHead(queue: var LoonyQueue, expect: var uint, swap: uint | TagPtr): bool =
  queue.head.compareExchange(expect, swap)

proc nptr(tag: TagPtr): NodePtr =
  result = toNodePtr(tag and PTRMASK)
proc idx(tag: TagPtr): uint16 =
  result = uint16(tag and TAGMASK)
proc tag(tag: TagPtr): uint16 = tag.idx
proc `$`(tag: TagPtr): string =
  var res = (nptr:tag.nptr, idx:tag.idx)
  return $res

proc advTail(queue: var LoonyQueue, el: Continuation, t: NodePtr): AdvTail =  
  var null = 0'u
  while true:
    var curr: TagPtr = queue.fetchTail()
    if t != curr.nptr:
      t.incrEnqCount()
      return AdvOnly
    var next = t.fetchNext()
    if cast[ptr Node](next).isNil():
      var node = cast[NodePtr](el) # allocNode(el) TODO; allocate mem
      null = 0'u
      if t.compareAndSwapNext(null, node):
        null = 0'u
        var tag: TagPtr = node + 1  # Translates to (nptr: node, idx: 1)
        while not queue.compareAndSwapTail(null, tag): # T11
          if t != curr.nptr:
            t.incrEnqCount()
            return AdvAndInserted
        t.incrEnqCount(curr.idx-N)
        return AdvAndInserted
      else:
        # deallocNode(node) TODO; dealloc mem
        continue
    else: # T20
      null = 0'u
      while not queue.compareAndSwapTail(null,next+1):    # next+1 translates to (nptr: next, idx: 1)
        if t != curr.nptr:
          t.incrEnqCount()
          return AdvOnly
      t.incrEnqCount(curr.idx-N)
      return AdvOnly

proc advHead(queue: var LoonyQueue, curr: var TagPtr, h,t: NodePtr): AdvHead =
  ## Reviewd, seems to follow the algorithm correctly and makes logical sense
  ## TODO DOC
  var next = h.fetchNext()
  if cast[ptr Node](next).isNil() or (t == h):
    h.incrDeqCount()
    return QueueEmpty
  curr += 1 # Equivalent to (nptr: NodePtr, idx: idx+=1)
  while not queue.compareAndSwapHead(curr, next.nptr): # equivalent to (nptr: next, idx: 0)
    if curr.nptr != h:
      h.incrDeqCount()
      return Advanced
  h.incrDeqCount(curr.idx-N)
  return Advanced



proc enqueue(queue: var LoonyQueue, el: Continuation) =
  while true:
    var tag = fetchIncTail(queue)
    var t: NodePtr = tag.nptr
    var i: uint16 = tag.idx
    if i < N:
      var w   : uint = prepareElement(el)
      let prev: uint = fetchAddSlot(t, i, w)
      if prev <= RESUME:
        return
      if prev == (READER or RESUME):
        (t.toNode) = tryReclaim(i + 1)
      continue
    else:     # Slow path; modified version of Michael-Scott algorithm
      case queue.advTail(el, t)
      of AdvAndInserted: return
      of AdvOnly: continue

proc deque(queue: var LoonyQueue): Continuation =
  while true:
    var curr = queue.fetchHead()
    var tail = queue.fetchTail()
    var h,t: NodePtr
    var i,ti: uint16
    (h, i) = (curr.nptr, curr.idx)
    (t, ti) = (tail.nptr, tail.idx)
    if (i >= N or i >= ti) and (h == t):
      return nil # Um ok
    var ntail = queue.fetchIncTail()
    (h, i) = (ntail.nptr, ntail.idx)
    if i < N:
      var prev = h.fetchAddSlot(i, READER)
      if i == N-1:
        (h.toNode) = tryReclaim(0)
      if (prev and WRITER) != 0:
        if (prev and RESUME) != 0:
          (h.toNode) = tryReclaim(i + 1)
        return cast[Continuation](prev and PTR_MASK) # TODO: define PTR_MASK
      continue
    else:
      case queue.advHead(curr, h, t)
      of Advanced: continue
      of QueueEmpty: return nil # big oof

proc isEmpty(queue: var LoonyQueue): bool =
  discard # TODO

## Consumed slots have been written to and then read
## If a concurrent deque operation outpaces the
## corresponding enqueue operation then both operations
## have to abandon and try again. Once all slots in the
## node have been consumed or abandoned, the node is
## considered drained and unlinked from the list.
## Node can be reclaimed and de-allocated.

## Queue manages an enqueue index and a dequeue index.
## Each are modified by fetchAndAdd; gives thread reserves
## previous index for itself which may be used to address
## a slot in the respective nodes array.
## ANCHOR both node pointers are tagged with their assoc
## index value -> they store both address to respective
## node as well as the current index value in the same
## memory word.
## Requires a sufficient number of available bits that
## are not used to present the nodes addresses themselves.