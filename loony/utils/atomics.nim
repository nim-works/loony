# Included by loony/spec to ensure compilation

template t[T](x: T): typedesc =
  bind sizeof
  when sizeof(T) == 8: uint64
  elif sizeof(T) == 4: uint32
  elif sizeof(T) == 2: uint16
  elif sizeof(T) == 1: uint8

var
  SeqCst* = ATOMIC_SEQ_CST
  Rlx* = ATOMIC_RELAXED
  Acq* = ATOMIC_ACQUIRE
  Rel* = ATOMIC_RELEASE
  AcqRel* = ATOMIC_ACQ_REL

template load*[T](dest: var T, mem: AtomMemModel = SeqCst): T =
  when T is AtomType:
    dest.addr.atomicLoadN(mem)
  else:
    cast[T](cast[ptr t(T)](dest.addr).atomicLoadN(mem))
template store*[T](dest: var T, val: T, mem: AtomMemModel = SeqCst) =
  when T is AtomType:
    dest.addr.atomicStoreN(val, mem)
  else:
    cast[ptr t(T)](dest.addr).atomicStoreN(cast[t(T)](val), mem)
template fetchAdd*[T](dest: var T, val: SomeInteger, mem: AtomMemModel = SeqCst): T =  
  when T is AtomType:
    dest.addr.atomicFetchAdd(val, mem)
  else:
    cast[T](cast[ptr t(T)](dest.addr).atomicFetchAdd(cast[t(T)](val), mem))
template fetchAdd*[T](dest: T, val: SomeInteger, mem: AtomMemModel = SeqCst): T =
  when T is AtomType:
    dest.unsafeAddr.atomicFetchAdd(val, mem)
  else:
    cast[T](cast[ptr t(T)](dest.unsafeAddr).atomicFetchAdd(cast[t(T)](val), mem))
template fetchSub*[T](dest: var T, val: SomeInteger, mem: AtomMemModel = SeqCst): T =
  when T is AtomType:
    dest.addr.atomicFetchSub(val, mem)
  else:
    cast[T](cast[ptr t(T)](dest.addr).atomicFetchSub(cast[t(T)](val), mem))
template fetchSub*[T](dest: T, val: SomeInteger, mem: AtomMemModel = SeqCst): T =
  when T is AtomType:
    dest.unsafeAddr.atomicFetchSub(val, mem)
  else:
    cast[T](cast[ptr t(T)](dest.unsafeAddr).atomicFetchSub(cast[t(T)](val), mem))
template compareExchange*[T](dest, expected, desired: T; succ, fail: AtomMemModel): bool =
  when T is AtomType:
    dest.unsafeAddr.atomicCompareExchangeN(expected.unsafeAddr, desired, false, succ, fail)
  else:
    cast[ptr t(T)](dest.unsafeAddr).atomicCompareExchangeN(cast[ptr t(T)](expected.unsafeAddr), cast[t(T)](desired), false, succ, fail)
template compareExchangeWeak*[T](dest, expected, desired: T; succ, fail: AtomMemModel): bool =
  when T is AtomType:
    dest.unsafeAddr.atomicCompareExchangeN(expected.unsafeAddr, desired, true, succ, fail)
  else:
    cast[ptr t(T)](dest.unsafeAddr).atomicCompareExchangeN(cast[ptr t(T)](expected.unsafeAddr), cast[t(T)](desired), true, succ, fail)
template compareExchange*[T](dest, expected, desired: T; order: AtomMemModel = SeqCst): bool =
  when T is AtomType:
    dest.unsafeAddr.atomicCompareExchangeN(expected.unsafeAddr, desired, false, order, order)
  else:
    cast[ptr t(T)](dest.unsafeAddr).atomicCompareExchangeN(cast[ptr t(T)](expected.unsafeAddr), cast[t(T)](desired), false, order, order)
template compareExchangeWeak*[T](dest, expected, desired: T; order: AtomMemModel = SeqCst): bool =
  when T is AtomType:
    dest.unsafeAddr.atomicCompareExchangeN(expected.unsafeAddr, desired, true, order, order)
  else:
    cast[ptr t(T)](dest.unsafeAddr).atomicCompareExchangeN(cast[ptr t(T)](expected.unsafeAddr), cast[t(T)](desired), true, order, order)
