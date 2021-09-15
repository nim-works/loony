# O. Giersch and J. Nolte, "Fast and Portable Concurrent FIFO Queues With Deterministic Memory Reclamation," in IEEE Transactions on Parallel and Distributed Systems, vol. 33, no. 3, pp. 604-616, 1 March 2022, doi: 10.1109/TPDS.2021.3097901.

import pkg/cps
import std/atomics

const
  RESUME = uint8(1)         # 0001
  WRITER = uint8(1 shl 1)   # 0010
  READER = uint8(1 shl 2)    # 0100
  SLOT   = uint8(1)
  DEQ    = uint8(1 shl 1)
  ENQ    = uint8(1 shl 2)
  N      = 1024             # Number of slots per node in the queue

type

  Node = ptr object
    slots : array[0..N, Atomic[uint]]    # 
    next  : Atomic[uint]                 # Pointer to Node
    ctrl  : ControlBlock                 # 

  Tag = tuple
    nptr: Node
    idx: uint16
  # Tag = (Node, uint16)

  LoonyQueue = object
    head     : Atomic[uint]     # Pointer to a Tag = (Node, idx)    ## Whereby node contains the slots and idx
    tail     : Atomic[uint]     # Pointer to a Tag = (Node, idx)    ## is the uint16 index of the slot array
    currTail : Atomic[uint]     # Current Node
  
  ControlBlock = object
    headMask : Atomic[(uint16, uint16)]     # 
    tailMask : Atomic[(uint16, uint16)]     # 
    reclaim  : Atomic[     uint8      ]     # 

  AdvTail = enum
    AdvAndInserted, # 0000
    AdvOnly         # 0001

template fetchIncTailTag(queue: var LoonyQueue): Tag =
  cast[ptr Tag](queue.tail.fetchAdd(1))[]
template fetchAddSlot(t: Node, idx: uint16, w: uint): uint =
  t[].slots[idx].fetchAdd(w)
template prepareElement(el: Continuation): uint =
  (cast[uint](el) or WRITER)  # BIT or
template tryReclaimSlot(t: Node, idx: uint16, w, p: uint): bool =
  t[].slots[idx - 1].compareExchange(w, p)
template fetchTail(queue: var LoonyQueue): Tag =
  cast[ptr Tag](queue.tail.load())[]
template fetchNext(node: Node): Node =
  cast[Node](node[].next.load())



proc advTail(queue: var LoonyQueue, el: Continuation, t: Node): AdvTail =
  var res: AdvTail
  var final: uint16
  var loopres = (res, final)  # Lazy
  while true:
    var curr = queue.fetchTail()
    if t != curr.nptr:
      loopres = (AdvOnly, 0'u16)
      break
    var next = t.fetchNext()
    if next.isNil():



proc enqueue(queue: var LoonyQueue, el: Continuation) =
  while true:
    var t: Node
    var i: uint16
    (t, i) = fetchIncTailTag(queue)
    if i < N:  # Fast path - guaranteed exclusive rights to write/consume
      var w   : uint = prepareElement(el)
      let prev: uint = fetchAddSlot(t, i, w)

      if prev <= RESUME:
        return
      if prev == (READER or RESUME):
        discard tryReclaimSlot(t, i, w, prev) #what do i do if this fucking fails lol
      continue
    else:     # Slow path; modified version of Michael-Scott algorithm
      case queue.advTail(el, t)
      of AdvAndInserted: return
      of AdvOnly: continue