import std/atomics
import "."/[constants, controlblock, alias]
# Import the holy one
import pkg/cps

type
  Node* = object
    slots* : array[0..N, Atomic[uint]]    # Pointers to object
    next*  : Atomic[NodePtr]              # NodePtr - successor node
    ctrl*  : ControlBlock                 # Control block for mem recl

template toNodePtr*(pt: uint | ptr Node): NodePtr =  # Convert ptr Node into NodePtr uint
  cast[NodePtr](pt)
template toNode*(pt: NodePtr | uint): Node =         # Convert NodePtr to ptr Node and deref
  cast[ptr Node](pt)[]
template toUInt*(node: var Node): uint =             # Get address to node
  cast[uint](node.addr)
template toUInt*(nodeptr: ptr Node): uint =          # Equivalent to toNodePtr
  cast[uint](nodeptr)

template prepareElement*(el: Continuation): uint =
  (cast[uint](el) or WRITER)  # BIT or

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

template incrEnqCount*(t: NodePtr, v: uint = 0'u) =
  discard # TODO
template incrDeqCount*(t: NodePtr, v: uint = 0'u) =
  discard # TODO

proc tryReclaim*(idx: uint): Node =
  discard # TODO

template deallocNode*(n: var Node) =
  freeShared(n.addr)
template deallocNode*(n: NodePtr) =
  freeShared(cast[ptr Node](n))

proc allocNode*(): NodePtr =     # Is this for some reason better if template?
  var res {.align(NODEALIGN).} = createShared(Node)
  return res.toNodePtr
proc allocNode*(el: Continuation): NodePtr =
  ## Allocate a fresh node with the first slot assigned
  ## to element el with the writer slot set
  var res {.align(NODEALIGN).} = createShared(Node)
  res[].slots[0].store(el.prepareElement())
  return res.toNodePtr

proc initNode*(): Node =
  var res {.align(NODEALIGN).} = Node(); return res # Should I still use mem alloc createShared?
proc init*[T: Node](t: T): T =
  var res {.align(NODEALIGN).} = Node(); return res

proc isConsumed*(slot: uint): bool =
  discard
  # TODO
