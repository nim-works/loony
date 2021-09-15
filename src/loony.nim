# O. Giersch and J. Nolte, "Fast and Portable Concurrent FIFO Queues With Deterministic Memory Reclamation," in IEEE Transactions on Parallel and Distributed Systems, vol. 33, no. 3, pp. 604-616, 1 March 2022, doi: 10.1109/TPDS.2021.3097901.

## REVIEW
## There is a clear distinction between the order of
## operations they present in their paper compared to
## the algorithms on their git repo. Since they link
## the git-repo in their article it is surely the most
## correct version right? RIGHT?!

## TODO
## Still have to do all the node operations and masking
## demasking etc. Also there must be some operations missing
## since I barely touched currTail; I assume ControlBlock is
## used for the purpose of dereferencing pointers?

import pkg/cps
import std/atomics

const
  RESUME   =   uint8(1      ) # 0001
  WRITER   =   uint8(1 shl 1) # 0010
  READER   =   uint8(1 shl 2) # 0100
  CONSUMED = READER or WRITER # 0110
  SLOT     =   uint8(1      ) # 0001
  DEQ      =   uint8(1 shl 1) # 0010
  ENQ      =   uint8(1 shl 2) # 0100
  N      = 1024             # Number of slots per node in the queue

  PTR_MASK =   uint8(0      ) # TODO define

type

  Node = object
    slots : array[0..N, Atomic[uint]]    # Pointers to object
    next  : Atomic[uint]                 # NodePtr
    ctrl  : ControlBlock                 # 
  NodePtr = ptr Node

  Tag = tuple
    nptr: NodePtr
    idx: uint16
  # Tag = (Node, uint16)

  LoonyQueue = object
    head     : Atomic[uint]     # Pointer to a Tag = (NodePtr, idx)    ## Whereby node contains the slots and idx
    tail     : Atomic[uint]     # Pointer to a Tag = (NodePtr, idx)    ## is the uint16 index of the slot array
    currTail : Atomic[uint]     # Current NodePtr
  
  ControlBlock = object
    headMask : Atomic[(uint16, uint16)]     # 
    tailMask : Atomic[(uint16, uint16)]     # 
    reclaim  : Atomic[     uint8      ]     # 

  AdvTail = enum
    AdvAndInserted, # 0000
    AdvOnly         # 0001
  AdvHead = enum
    QueueEmpty,     # 0000
    Advanced        # 0001

template prepareElement(el: Continuation): uint =
  (cast[uint](el) or WRITER)  # BIT or

template fetchTail(queue: var LoonyQueue): Tag =
  cast[ptr Tag](queue.tail.load())[]
template fetchHead(queue: var LoonyQueue): Tag =
  cast[ptr Tag](queue.head.load())[]
template fetchCurrTail(queue: var LoonyQueue): NodePtr =
  cast[NodePtr](queue.currTail.load())
template fetchIncTail(queue: var LoonyQueue): Tag =
  cast[ptr Tag](queue.tail.fetchAdd(1))[]
template fetchIncHead(queue: var LoonyQueue): Tag =
  cast[ptr Tag](queue.head.fetchAdd(1))[]

template fetchNext(node: NodePtr): NodePtr =
  cast[NodePtr](node[].next.load())
template fetchAddSlot(t: NodePtr, idx: uint16, w: uint): uint =
  t[].slots[idx].fetchAdd(w)

template compareAndSwapNext(t: NodePtr, expect: var uint, swap: var uint): bool =
  t[].next.compareExchange(expect, swap) # Dumb, this needs to have expect be variable
template compareAndSwapTail(queue: var LoonyQueue, expect: var uint, swap: uint): bool =
  queue.tail.compareExchange(expect, swap)
template compareAndSwapTail(queue: var LoonyQueue, expect: var uint, swap: Tag): bool =
  queue.tail.compareExchange(expect, cast[uint](swap))
template compareAndSwapHead(queue: var LoonyQueue, expect: var uint, swap: uint): bool =
  queue.head.compareExchange(expect, swap)
template compareAndSwapHead(queue: var LoonyQueue, expect: var uint, swap: Tag): bool =
  queue.head.compareExchange(expect, cast[uint](swap))

template incrEnqCount(t: NodePtr, v: uint = 0'u) =
  discard # TODO
template incrDeqCount(t: NodePtr, v: uint = 0'u) =
  discard # TODO

proc tryReclaim(idx: uint): Node =
  discard # TODO

template deallocNode(x: untyped): untyped =
  discard # TODO
template allocNode(x: untyped): untyped =
  discard # TODO

proc advTail(queue: var LoonyQueue, el: Continuation, t: NodePtr): AdvTail =  
  ## REVIEW
  var null = 0'u
  while true:
    var curr: Tag = queue.fetchTail()
    if t != curr.nptr:
      t.incrEnqCount()
      return AdvOnly
    var next = t.fetchNext()
    if next.isNil():
      var node = cast[uint](el) # allocNode(el) TODO; allocate mem
      null = 0'u
      if t.compareAndSwapNext(null, node):
        null = 0'u
        var tag: Tag = (nptr: cast[NodePtr](node), idx: 1'u16)
                  # I don't understand why I'm doing this :/
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
      while not queue.compareAndSwapTail(null,(nptr:next, idx:1'u16)):
        if t != curr.nptr:
          t.incrEnqCount()
          return AdvOnly
      t.incrEnqCount(curr.idx-N)
      return AdvOnly

proc advHead(queue: var LoonyQueue, curr: var Tag, h: NodePtr, t: NodePtr): AdvHead =
  var next = h.fetchNext()
  if next.isNil() or (t == h):
    h.incrDeqCount()
    return QueueEmpty
  curr.idx += 1
  var vcurr = cast[uint](curr)
  while not queue.compareAndSwapHead(vcurr, (nptr: next, idx: 0'u16)):
    if curr.nptr != h:
      h.incrDeqCount()
      return Advanced
  h.incrDeqCount(curr.idx-N)
  return Advanced



proc enqueue(queue: var LoonyQueue, el: Continuation) =
  ## REVIEW
  while true:
    var t: NodePtr
    var i: uint16
    (t, i) = fetchIncTail(queue)
    if i < N:  # Fast path - guaranteed exclusive rights to write/consume
      var w   : uint = prepareElement(el)
      let prev: uint = fetchAddSlot(t, i, w)
      if prev <= RESUME:
        return
      if prev == (READER or RESUME):
        t[] = tryReclaim(i + 1)
      continue
    else:     # Slow path; modified version of Michael-Scott algorithm
      case queue.advTail(el, t)
      of AdvAndInserted: return
      of AdvOnly: continue

proc deque(queue: var LoonyQueue): Continuation =
  while true:
    var curr = queue.fetchHead()
    var h,t: NodePtr
    var i,ti: uint16
    (h, i) = curr
    (t, ti) = queue.fetchTail()
    if (i >= N or i >= ti) and (h == t):
      return nil # Um ok
    (h, i) = queue.fetchIncTail()
    if i < N:
      var prev = h.fetchAddSlot(i, READER)
      if i == N-1:
        h[] = tryReclaim(0)
      if (prev and WRITER) != 0:
        if (prev and RESUME) != 0:
          h[] = tryReclaim(i + 1)
        return cast[Continuation](prev and PTR_MASK) # TODO: define PTR_MASK
      continue
    else:
      case queue.advHead(curr, h, t)
      of Advanced: continue
      of QueueEmpty: return nil # big oof

proc isEmpty(queue: var LoonyQueue): bool =
  discard # TODO