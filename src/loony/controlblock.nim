import std/atomics
import "."/[alias, constants]

type
  ## Control block for memory reclamation
  ControlBlock* = object
    ## high uint16 final observed count of slow-path enqueue ops
    ## low uint16: current count
    headMask* : Atomic[ControlMask]     # (uint16, uint16)  4 bytes
    ## high uint16, final observed count of slow-path dequeue ops,
    ## low uint16: current count
    tailMask* : Atomic[ControlMask]     # (uint16, uint16)  4 bytes
    ## Bitmask for storing current reclamation status
    ## All 3 bits set = node can be reclaimed
    reclaim*  : Atomic[ uint8]     #                   1 byte

proc getHigh*(mask: ControlMask): uint16 =
  return cast[uint16](mask shr SHIFT)
proc getLow*(mask: ControlMask): uint16 =
  return cast[uint16](mask)

proc fetchAddHigh*(mask: var Atomic[ControlMask]): uint16 =
  return cast[uint16]((mask.fetchAdd(1 shl SHIFT)) shr SHIFT)
proc fetchAddLow*(mask: var Atomic[ControlMask]): uint16 =
  return cast[uint16](mask.fetchAdd(1))
proc fetchAddMask*(mask: var Atomic[ControlMask], pos: int, val: uint32): ControlMask =
  if pos > 0:
    return mask.fetchAdd(val shl SHIFT)
  return mask.fetchAdd(val)

proc fetchAddTail*(ctrl: var ControlBlock, v: uint32 = 1): ControlMask =
  return ctrl.tailMask.fetchAdd(v)
proc fetchAddHead*(ctrl: var ControlBlock, v: uint32 = 1): ControlMask =
  return ctrl.headMask.fetchAdd(v)

proc fetchAddReclaim*(ctrl: var ControlBlock, v: uint8 = 1): uint8 =
  return ctrl.reclaim.fetchAdd(v)