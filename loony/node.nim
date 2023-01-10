import loony/spec
import loony/debug
import loony/utils/memalloc

proc deallocNode*(n: ptr Node) =
  decDebugCounter()
  deallocAligned(n, NODEALIGN.int)

proc allocNode*(): ptr Node =
  incDebugCounter()
  cast[ptr Node](allocAligned0(sizeof(Node), NODEALIGN.int))

proc allocNode*[T](pel: T): ptr Node =
  result = allocNode()
  result.slots[0].store(pel)

proc tryReclaim*(node: ptr Node; start: SomeInteger) =
  block done:
    for i in start.int..<loonySlotCount:
      template s: uint = node.slots[i]
      if (s.load(Acq) and CONSUMED) != CONSUMED:
        var prev = s.fetchAdd(RESUME, Rlx) and CONSUMED
        if prev != CONSUMED:
          incRecPathCounter()
          break done
    var flags = node.ctrl.fetchAddReclaim(SLOT)
    if flags == (ENQ or DEQ):
      deallocNode node
      incReclaimCounter()

proc incrEnqCount*(node: ptr Node; final: uint16 = 0) =
  var mask =
    node.ctrl.fetchAddTail:
      (final.uint32 shl 16) + 1
  template finalCount: uint16 =
    if final == 0:
      mask.upper
    else:
      final
  if finalCount == (mask.lower) + 1:
    if node.ctrl.fetchAddReclaim(ENQ) == (DEQ or SLOT):
      deallocNode node
      incEnqCounter()
  else:
    incEnqPathCounter()

proc incrDeqCount*(node: ptr Node; final: uint16 = 0) =
  incDeqPathCounter()
  var mask =
    node.ctrl.fetchAddHead:
      (final.uint32 shl 16) + 1
  template finalCount: uint16 =
    if final == 0:
      mask.upper
    else:
      final
  if finalCount == (mask.lower) + 1:
    if node.ctrl.fetchAddReclaim(DEQ) == (ENQ or SLOT):
      deallocNode node
      incDeqCounter()
  else:
    incDeqPathCounter()
