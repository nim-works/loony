import std/atomics

import loony/spec
import loony/memalloc

type
  Node* = object
    slots* : array[0..N, Atomic[uint]]  # Pointers to object
    next*  : Atomic[NodePtr]            # NodePtr - successor node
    ctrl*  : ControlBlock               # Control block for mem recl

template toNodePtr*(pt: uint | ptr Node): NodePtr =
  # Convert ptr Node into NodePtr uint
  cast[NodePtr](pt)
template toNode*(pt: NodePtr | uint): Node =
  # NodePtr -> ptr Node and deref
  cast[ptr Node](pt)[]
template toUInt*(node: var Node): uint =
  # Get address to node
  cast[uint](node.addr)
template toUInt*(nodeptr: ptr Node): uint =
  # Equivalent to toNodePtr
  cast[uint](nodeptr)

proc prepareElement*[T: ref](el: T): uint =
  ## Prepare an item to be taken into the queue; we bump the RC first to
  ## ensure that no other operations free it, then add the WRITER bit.
  GC_ref el
  result = cast[uint](el) or WRITER

template fetchNext*(node: Node, moorder: MemoryOrder = moAcquireRelease): NodePtr =
  node.next.load(order = moorder)

template fetchNext*(node: NodePtr, moorder: MemoryOrder = moAcquireRelease): NodePtr =
  # get the NodePtr to the next Node, can be converted to a TagPtr of (nptr: NodePtr, idx: 0'u16)
  (toNode node).next.load(order = moorder)

template fetchAddSlot*(t: Node, idx: uint16, w: uint, moorder: MemoryOrder = moAcquireRelease): uint =
  ## Fetches the pointer to the object in the slot while atomically
  ## increasing the value by `w`.
  ##
  ## Remembering that the pointer has 3 tail bits clear; these are
  ## reserved and increased atomically to indicate RESUME, READER, WRITER
  ## statuship.
  t.slots[idx].fetchAdd(w, order = moorder)

template compareAndSwapNext*(t: Node, expect: var uint, swap: var uint): bool =
  t.next.compareExchange(expect, swap, moRelaxed) # MO as per cpp impl

template compareAndSwapNext*(t: NodePtr, expect: var uint, swap: var uint): bool =
  (toNode t).next.compareExchange(expect, swap, moRelaxed) # MO as per cpp impl

proc `=destroy`*(n: var Node) =
  deallocAligned(n.addr, NODEALIGN.int)

proc allocNode*(): ptr Node =
  cast[ptr Node](allocAligned0(sizeof(Node), NODEALIGN.int))

proc allocNode*[T](el: T): ptr Node =
  result = allocNode()
  result.slots[0].store(el)
  # result.slots[0].store(prepareElement el) <- preparation of the element
  #                                           to be handled at head of push op

proc tryReclaim*(node: var Node; start: uint16) =
  block done:
    for i in start .. N:
      template s: Atomic[uint] = node.slots[i]
      if (s.load(order = moAcquire) and CONSUMED) != CONSUMED:
        var prev = s.fetchAdd(RESUME, order = moRelaxed) and CONSUMED
        if prev != CONSUMED:
          break done
    var flags = node.ctrl.fetchAddReclaim(SLOT)
    if flags == (ENQ or DEQ):
      `=destroy` node

proc incrEnqCount*(node: var Node; final: uint16 = 0) =
  var mask =
    node.ctrl.fetchAddTail:
      (final.uint32 shl 16) + 1
  template finalCount: uint16 =
    if final == 0:
      getHigh mask
    else:
      final
  if finalCount == (mask.uint16 and MASK) + 1:
    if node.ctrl.fetchAddReclaim(ENQ) == (DEQ or SLOT):
      `=destroy` node

proc incrDeqCount*(node: var Node; final: uint16 = 0) =
  var mask =
    node.ctrl.fetchAddTail:
      (final.uint32 shl 16) + 1
  template finalCount: uint16 =
    if final == 0:
      getHigh mask
    else:
      final
  if finalCount == (mask.uint16 and MASK) + 1:
    if node.ctrl.fetchAddReclaim(DEQ) == (ENQ or SLOT):
      `=destroy` node
