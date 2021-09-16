import std/atomics
import "."/[constants, controlblock, alias, memalloc]
# Import the holy one
import pkg/cps

type
  Node* = object
    slots* : array[0..N, Atomic[uint]]    # Pointers to object
    next*  : Atomic[NodePtr]              # NodePtr - successor node
    ctrl*  : ControlBlock                 # Control block for mem recl

when isMainModule:
  echo ""
  var node = alignedAlloc0(sizeof(Node), NODEALIGN)
  echo cast[uint](node)

template toNodePtr*(pt: uint | ptr Node): NodePtr =  # Convert ptr Node into NodePtr uint
  cast[NodePtr](pt)
template toNode*(pt: NodePtr | uint): Node =         # Convert NodePtr to ptr Node and deref
  cast[ptr Node](pt)[]
template toUInt*(node: var Node): uint =             # Get address to node
  cast[uint](node.addr)
template toUInt*(nodeptr: ptr Node): uint =          # Equivalent to toNodePtr
  cast[uint](nodeptr)

proc prepareElement*(el: Continuation): uint =
  GC_ref(el)
  return (cast[uint](el) or WRITER)  # BIT or
  # (cast[uint](el))  # BIT or

template fetchNext*(node: Node): NodePtr = node.next.load()
template fetchNext*(node: NodePtr): NodePtr =
  # get the NodePtr to the next Node, can be converted to a TagPtr of (nptr: NodePtr, idx: 0'u16)
  (node.toNode).next.load()

template fetchAddSlot*(t: Node, idx: uint16, w: uint): uint = t.slots[idx].fetchAdd(w)
template fetchAddSlot*(t: NodePtr, idx: uint16, w: uint): uint =
  (t.toNode).slots[idx].fetchAdd(w)
# Fetches the pointer to the object in the slot while atomically increasing the val
# 
# Remembering that the pointer has 3 tail bits clear; these are reserved
# and increased atomically do indicate RESUME, READER, WRITER statuship.

template compareAndSwapNext*(t: Node, expect: var uint, swap: var uint): bool =
  t.next.compareExchange(expect, swap)
template compareAndSwapNext*(t: NodePtr, expect: var uint, swap: var uint): bool =
  (t.toNode).next.compareExchange(expect, swap) # Dumb, this needs to have expect be variable

template deallocNode*(n: var Node) =
  deallocAligned(n.addr, NODEALIGN.int)
  
template deallocNode*(n: NodePtr) =
  deallocAligned(cast[pointer](n), NODEALIGN.int)


proc allocNode*(): NodePtr =     # Is this for some reason better if template?
  var res = cast[ptr Node](allocAligned0(sizeof(Node), NODEALIGN.int))
  res[] = Node()
  result = res.toNodePtr()

proc allocNode*(el: Continuation): NodePtr =
  var res = cast[ptr Node](allocAligned0(sizeof(Node), NODEALIGN.int))
  res[] = Node()
  res[].slots[0].store(el.prepareElement())
  # return res.toNodePtr
  return res.toNodePtr()

# proc initNode*(): Node =
#   var res {.align(NODEALIGN).} = Node(); return res # Should I still use mem alloc createShared?
# proc init*[T: Node](t: T): T =
#   var res {.align(NODEALIGN).} = Node(); return res

proc tryReclaim*(t: NodePtr, start: uint16) =
  for i in start..N:
    var s = t.toNode().slots[i]
    if (s.load() and CONSUMED) != CONSUMED:
      var prev = s.fetchAdd(RESUME) and CONSUMED
      echo prev
      if prev != CONSUMED:
        echo i
        # FIXME I keep hitting a SIGSEV 
        return
  var flags = t.toNode().ctrl.fetchAddReclaim(SLOT)
  if flags == (ENQ or DEQ):
    deallocNode(t)

proc incrEnqCount*(t: NodePtr, final: uint16 = 0) =
  var finalCount: uint16 = final
  var mask: ControlMask
  if finalCount == 0:
    mask = t.toNode().ctrl.fetchAddTail(1)
    finalCount = mask.getHigh()
  else:
    var v: uint32 = 1 + (cast[uint32](finalCount) shl 16)
    mask = t.toNode().ctrl.fetchAddTail(v)
  var currCount = mask.getLow() + 1
  if currCount == finalCount:
    var prev = t.toNode().ctrl.fetchAddReclaim(ENQ)
    if prev == (DEQ or SLOT):
      deallocNode(t)

proc incrDeqCount*(t: NodePtr, final: uint16 = 0) =
  var finalCount: uint16 = final
  var mask: ControlMask
  if finalCount == 0:
    mask = t.toNode().ctrl.fetchAddHead(1)
    finalCount = mask.getHigh()
  else:
    var v: uint32 = 1 + (cast[uint32](finalCount) shl 16)
    mask = t.toNode().ctrl.fetchAddHead(v)
  var currCount = mask.getLow() + 1
  if currCount == finalCount:
    var prev = t.toNode().ctrl.fetchAddReclaim(DEQ)   # The article ommits the deq
    if prev == (ENQ or SLOT):                         # algorithm but I'm guessing i
      deallocNode(t)                                  # swap these vals to DEQ and ENQ