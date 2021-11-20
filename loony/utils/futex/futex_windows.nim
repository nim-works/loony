const
  INFINITE = -1

proc waitOnAddress[T](address: ptr T; compare: ptr T; size: int32;
                      dwMilliseconds: int32): bool {.stdcall, dynlib: "API-MS-Win-Core-Synch-l1-2-0", importc: "WaitOnAddress".}
proc wakeByAddressSingle(address: pointer) {.stdcall, dynlib: "API-MS-Win-Core-Synch-l1-2-0", importc: "WakeByAddressSingle".}
proc wakeByAddressAll(address: pointer) {.stdcall, dynlib: "API-MS-Win-Core-Synch-l1-2-0", importc: "WakeByAddressAll".}

proc wait*[T](monitor: ptr T; compare: T) {.inline.} =
  # win api says this can spuriously wake and should be in a loop which does
  # a comparison to ensure it is appropriate for the thread to wake up
  # while monitor[] == compare:
    # discard waitOnAddress(monitor, compare.unsafeAddr, sizeof(T).int32, INFINITE)
  discard waitOnAddress(monitor, compare.unsafeAddr, sizeof(T).int32, INFINITE)

proc wake*(monitor: pointer) {.inline.} =
  wakeByAddressSingle(monitor)

proc wakeAll*(monitor: pointer) {.inline.} =
  wakeByAddressAll(monitor)