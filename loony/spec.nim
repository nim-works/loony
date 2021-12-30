const
  loonyNodeAlignment* {.intdefine.} = 11
  loonySlotCount* {.intdefine.} = 1024   # Number of slots per node in the queue

doAssert (1 shl loonyNodeAlignment) > loonySlotCount, "Your LoonySlot count exceeds your alignment!"

const
  ## Slot flag constants
  UNINIT*   =   uint8(   0   ) # 0000_0000
  RESUME*   =   uint8(1      ) # 0000_0001
  WRITER*   =   uint8(1 shl 1) # 0000_0010
  READER*   =   uint8(1 shl 2) # 0000_0100
  CONSUMED* =  READER or WRITER# 0000_0110

  SLOT*     =   uint8(1      ) # 0000_0001
  DEQ*      =   uint8(1 shl 1) # 0000_0010
  ENQ*      =   uint8(1 shl 2) # 0000_0100
  #
  TAGBITS*   : uint = loonyNodeAlignment  # Each node must be aligned to this value
  NODEALIGN* : uint = 1 shl TAGBITS       # in order to store the required number of
  TAGMASK*   : uint = NODEALIGN - 1       # tag bits in every node pointer
  PTRMASK*   : uint = high(uint) xor TAGMASK
  # Ref-count constants
  SHIFT* = 16      # Shift to access 'high' 16 bits of uint32
  MASK*  = 0xFFFF  # Mask to access 'low' 16 bits of uint32
  #
  SLOTMASK*  : uint = high(uint) xor (RESUME or WRITER or READER)

type
  Node* {.byref.} = object
    slots* : array[loonySlotCount, uint]  # Pointers to object
    next*  : ptr Node            # NodePtr - successor node
    ctrl*  : ControlBlock               # Control block for mem recl  NodePtr* = uint

  TagPtr* {.byref.} = object
    when littleEndian == cpuEndian:
      tag* {.bitsize: (loonyNodeAlignment).}: uint
      pntr* {.bitsize: (64 - loonyNodeAlignment).}: uint
    else:
      pntr* {.bitsize: (64 - loonyNodeAlignment).}: uint
      tag* {.bitsize: (loonyNodeAlignment).}: uint
      ## Aligned pointer with 12 bit prefix containing the tag.
      ## Access using procs nptr and idx
  ControlMask* {.byref.} = object
    when littleEndian == cpuEndian:
      lower* {.bitsize: 16.}: uint16
      upper* {.bitsize: 16.}: uint16
    else:
      upper* {.bitsize: 16.}: uint16
      lower* {.bitsize: 16.}: uint16
  ## Control block for memory reclamation
  ControlBlock* {.byref.} = object
    ## high uint16 final observed count of slow-path enqueue ops
    ## low uint16: current count
    headMask* : ControlMask     # (uint16, uint16)  4 bytes
    ## high uint16, final observed count of slow-path dequeue ops,
    ## low uint16: current count
    tailMask* : ControlMask     # (uint16, uint16)  4 bytes
    ## Bitmask for storing current reclamation status
    ## All 3 bits set = node can be reclaimed
    reclaim*  : uint8     #                   1 byte

proc sizeof*(td: TagPtr): int {.compileTime.} = 8
proc sizeof*(td: ControlMask): int {.compileTime.} = 4

template getTag*(tptr: TagPtr): uint =
  # TODO handle be
  tptr.tag
template getPtr*(tptr: TagPtr): ptr Node =
  # TODO handle be
  cast[ptr Node](cast[uint](tptr) and PTRMASK)

converter toUint*(x: TagPtr): uint = cast[uint](x)
converter toTagPtr*(x: uint): TagPtr = cast[TagPtr](x)
converter toUint32*(x: ControlMask): uint32 = cast[uint32](x)
converter toCtrlMask*(x: uint32): ControlMask = cast[ControlMask](x)
converter toUint*(x: ptr Node): uint = cast[uint](x)
converter toNodePtr*(x: uint): ptr Node = cast[ptr Node](x)

include loony/utils/atomics

template fetchAddTail*(ctrl: var ControlBlock, v: uint32 = 1, moorder = Rel): ControlMask =
  ctrl.tailMask.fetchAdd(v, moorder)

template fetchAddHead*(ctrl: var ControlBlock, v: uint32 = 1, moorder = Rel): ControlMask =
  ctrl.headMask.fetchAdd(v, moorder)

template fetchAddReclaim*(ctrl: var ControlBlock, v: uint8 = 1, moorder = AcqRel): uint8 =
  ctrl.reclaim.fetchAdd(v, moorder)
