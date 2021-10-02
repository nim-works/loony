import loony

import std/atomics

type
  WardFlag* {.size: sizeof(uint16).} = enum
    None        = "Zero"
    Pausable    = "accessing the queue with this ward can be paused"
    Clearable   = "this ward is capable of clearing the queue"
  WardFlags* = uint16
  WardObj[T; F: static[uint16]] = object
    queue: LoonyQueue[T]
    values: Atomic[uint16]
  Ward*[T; F: static[uint16]] = ref WardObj[T, F]

converter toUInt16*(flags: set[WardFlag]): WardFlags =
  # The vm cannot cast between set and integers
  when nimvm:
    for flag in items(flags):
      result = `or`(result, 1'u16 shl flag.ord)
  else:
    result = cast[uint16](flags)

converter toFlags*(value: WardFlags): set[WardFlag] =
  # The vm cannot cast between integers and sets
  when nimvm:
    # Iterate over the values of ward flag
    # If they are in the value then we add them to the result
    for flag in items(WardFlag):
      if `and`(value, 1'u16 shl flag.ord) != 0:
        result.incl flag
  else:
    result = cast[set[WardFlag]](value)

template flags*[T, F](ward: Ward[T, F]): set[WardFlag] =
  F.toFlags()

proc init*(ward: Ward) =
  ward.values.store(0'u16)

proc newWard*[T](lq: LoonyQueue[T],
                flags: static set[WardFlag]): auto =
  ## Create a new ward for the queue with the flags given
  result = Ward[T, toUInt16(flags)](queue: lq)
  init result

proc pop*[T, F](ward: Ward[T, F]): T =
  block pop:
    when ward.flags.contains Pausable:
      # At the moment this being the only flag to be cautious
      # of means we can just check for any bit set in the flag vals
      if ward.values.fetchAnd(high(uint16), moAcquire) > 0'u16:
        break pop
      # Do a atomic pause check here
    result = ward.queue.pop()

proc unsafePop*[T, F](ward: Ward[T, F]): T =
  block pop:
    when ward.flags.contains Pausable:
      if ward.values.fetchAnd(high(uint16), moAcquire) > 0'u16:
        break pop
    result = ward.queue.unsafePop()

proc pause*[T, F](ward: Ward[T, F]): bool =
  when ward.flags.contains Pausable:
    if ward.values.fetchOr({Pausable}, moRelease) > 0'u16:
      # The ward has now been paused
      result = true
    else:
      # The ward was already paused
      result = false
  else:
    raise newException(ValueError, "Ward requires the pausable flag")

proc resume*[T, F](ward: Ward[T, F]): bool =
  when ward.flags.contains Pausable:
    if ward.values.fetchAnd(0'u16, moRelease) > 0'u16:
      # The ward is now resumed
      result = true
    else:
      # The ward was not paused
      result = false
  else:
    raise newException(ValueError, "Ward requires the pausable flag")