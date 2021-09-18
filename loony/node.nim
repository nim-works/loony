import std/atomics

import loony/spec
import loony/memalloc

type
  Node* = object
    slots* : array[0..N-1, Atomic[uint]]  # Pointers to object
    next*  : Atomic[NodePtr]              # NodePtr - successor node
    ctrl*  : ControlBlock                 # Control block for mem recl

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
  ## Take an item into the queue; we bump the RC first to ensure
  ## that no other operations free it, then add the WRITER bit.
  GC_ref el
  result = cast[uint](el) or WRITER

template fetchNext*(node: Node): NodePtr =
  node.next.load()

template fetchNext*(node: NodePtr): NodePtr =
  # get the NodePtr to the next Node, can be converted to a TagPtr of (nptr: NodePtr, idx: 0'u16)
  (toNode node).next.load()

template fetchAddSlot*(t: Node, idx: uint16, w: uint): uint =
  ## Fetches the pointer to the object in the slot while atomically
  ## increasing the value by `w`.
  ##
  ## Remembering that the pointer has 3 tail bits clear; these are
  ## reserved and increased atomically to indicate RESUME, READER, WRITER
  ## statuship.
  t.slots[idx].fetchAdd(w)

template compareAndSwapNext*(t: Node, expect: var uint, swap: var uint): bool =
  t.next.compareExchange(expect, swap)

template compareAndSwapNext*(t: NodePtr, expect: var uint, swap: var uint): bool =
  # Dumb, this needs to have expect be variable
  (toNode t).next.compareExchange(expect, swap)

proc `=destroy`*(n: var Node) =
  # echo "deallocd"
  deallocAligned(n.addr, NODEALIGN.int)

proc allocNode*(): ptr Node =
  # echo "allocd"
  cast[ptr Node](allocAligned0(sizeof(Node), NODEALIGN.int))

proc allocNode*[T](el: T): ptr Node =
  # echo "allocd"
  result = allocNode()
  result.slots[0].store(prepareElement el)

proc tryReclaim*(node: var Node; start: uint16) =
  # echo "trying to reclaim"
  block done:
    for i in start ..< N:
      template s: Atomic[uint] = node.slots[i]
      # echo "Slot current val ", s.load()
      if (s.load() and CONSUMED) != CONSUMED:
        var prev = s.fetchAdd(RESUME) and CONSUMED
        # echo prev
        if prev != CONSUMED:
          break done
    var flags = node.ctrl.fetchAddReclaim(SLOT)
    # echo "Try reclaim flag ", flags
    if flags == (ENQ or DEQ):
      `=destroy` node

proc incrEnqCount*(node: var Node; final: uint16 = 0) =
  var finalCount: uint16 = final
  var mask: ControlMask
  var currCount: uint16
  if finalCount == 0:
    mask = node.ctrl.fetchAddTail(1)
    finalCount = mask.getHigh()
    currCount = cast[uint16](1 + (mask and MASK))
  else:
    var v: uint32 = 1 + (cast[uint32](finalCount) shl 16)
    mask = node.ctrl.fetchAddTail(v)
    currCount = cast[uint16](1 + (mask and MASK))
  if currCount == finalCount:
    var prev = node.ctrl.fetchAddReclaim(ENQ)
    # echo "IncrEnqCount prev ", prev
    # echo "IncrEnqCount new ", t.toNode().ctrl.reclaim.load()
    if prev == (DEQ or SLOT):
      `=destroy` node

proc incrDeqCount*(node: var Node; final: uint16 = 0) =
  var finalCount: uint16 = final
  var mask: ControlMask
  var currCount: uint16
  # echo "Incrementing deq count"
  if finalCount == 0:
    mask = node.ctrl.fetchAddTail(1)
    finalCount = mask.getHigh()
    currCount = cast[uint16](1 + (mask and MASK))
    # echo "If finalcount == 0, vals ", finalCount, " ", currCount
  else:
    var v: uint32 = 1 + (cast[uint32](finalCount) shl 16)
    mask = node.ctrl.fetchAddTail(v)
    currCount = cast[uint16](1 + (mask and MASK))
  #   echo "finalcount != 0, vals ", finalCount, " ", currCount
  # echo "Finalcount & currCount, vals ", finalCount, " ", currCount
  if currCount == finalCount:
    var prev = node.ctrl.fetchAddReclaim(DEQ)
    # The article omits the deq algorithm but I'm guessing i swap these
    # vals to DEQ and ENQ
    # echo "IncrDEQCount prev ", prev
    # echo "IncrDEQCount new ", t.toNode().ctrl.reclaim.load()
    if prev == (ENQ or SLOT):
      `=destroy` node
