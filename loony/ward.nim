import loony

import std/atomics
import std/setutils

type
  WardFlag* {.size: sizeof(uint16).} = enum
    None        = "Zero"
    PopPausable = "popping off the queue with this ward can be paused"
    PushPausable= "pushing onto the queue with this ward can be paused"
    Clearable   = "this ward is capable of clearing the queue"

    Pausable    = "accessing the queue with this ward can be paused" # Keep this flag on the end
    # This flag will automatically infer PopPausable and PushPausable.
  WardFlags* = uint16
  WardObj[T; F: static[uint16]] = object
    queue: LoonyQueue[T]
    values: Atomic[uint16]
  Ward*[T; F: static[uint16]] = ref WardObj[T, F]


converter toUInt16*(flags: set[WardFlag]): WardFlags =
  # The vm cannot cast between set and integers
  when nimvm:
    for flag in items(flags):
      block:
        if flag == Pausable:
          result = `or`(result, 1'u16 shl PopPausable.ord)
          result = `or`(result, 1'u16 shl PushPausable.ord)
        result = `or`(result, 1'u16 shl flag.ord)
      if flags.contains(PopPausable) and
          flags.contains(PushPausable) and
          not flags.contains(Pausable):
        result = `or`(result, 1'u16 shl Pausable.ord)

  else:
    result = cast[uint16](flags)
    if flags.contains(PopPausable) and
        flags.contains(PushPausable) and
        not flags.contains(Pausable):
      result = `or`(result, 1'u16 shl Pausable.ord)
    if flags.contains Pausable:
      result = `or`(result, cast[uint16]({PopPausable, PushPausable}))


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

proc newWard*[T, F](wd: Ward[T, F],
                    flags: static set[WardFlag]): auto =
  ## Creates a ward with a different set of flags that are settable/observable
  ## that shares state with the given ward for the same queue.
  ## This can be used to create a ward for instance that will respond to
  ## poppauses only. If the other ward is paused for both pop and push, this ward
  ## will only respect the poppause.
  result = Ward[T, toUInt16(flags)](queue: wd.queue, values: wd.values)

proc push*[T, F](ward: Ward[T, F], el: T): bool =
  block push:
    when ward.flags.contains PushPausable:
      if `and`(ward.values.load(moAcquire), {PushPausable}) > 0'u16:
        result = false
        break push
    ward.queue.push T
    result = true

proc unsafePush*[T, F](ward: Ward[T, F], el: T): bool =
  block push:
    when ward.flags.contains PushPausable:
      if `and`(ward.values.load(moAcquire), {PushPausable}) > 0'u16:
        result = false
        break push
    ward.queue.unsafePush T
    result = true

proc pop*[T, F](ward: Ward[T, F]): T =
  block pop:
    when ward.flags.contains PopPausable:
      # At the moment this being the only flag to be cautious
      # of means we can just check for any bit set in the flag vals
      if `and`(ward.values.load(moAcquire), {PopPausable}) > 0'u16:
        break pop
      # Do a atomic pause check here
    result = ward.queue.pop()

proc unsafePop*[T, F](ward: Ward[T, F]): T =
  block pop:
    when ward.flags.contains PopPausable:
      if `and`(ward.values.load(moAcquire), {PopPausable}) > 0'u16:
        break pop
    result = ward.queue.unsafePop()

proc pause*[T, F](ward: Ward[T, F]): bool =
  when ward.flags.contains Pausable:
    if `and`(ward.values.fetchOr({PopPausable, PushPausable}, moRelease), {PopPausable, PushPausable}) > 0'u16:
      # The ward has now been paused
      result = true
    else:
      # The ward was already paused
      result = false
  elif ward.flags.contains PushPausable:
    raise newException(ValueError, "Have to use pausePush unless the Pausable flag is used")
  elif ward.flags.contains PopPausable:
    raise newException(ValueError, "Have to use pausePop unless the Pausable flag is used")
  else:
    raise newException(ValueError, "Ward requires the pausable flag")

proc pausePush*[T, F](ward: Ward[T, F]): bool =
  when ward.flags.contains PushPausable:
    if `and`(ward.values.fetchOr({PushPausable}, moRelease), {PushPausable}) > 0'u16:
      # The ward pushes are now paused
      result = true
    else:
      # The pushes were already paused
      result = false
  else:
    raise newException(ValueError, "Ward requires the pushpausable or pausable flag")

proc pausePop*[T, F](ward: Ward[T, F]): bool =
  when ward.flags.contains PopPausable:
    if `and`(ward.values.fetchOr({PopPausable}, moRelease), {PopPausable}) > 0'u16:
      # The ward pops are now paused
      result = true
    else:
      # The pops were already paused
      result = false
  else:
    raise newException(ValueError, "Ward requires the poppausable or pausable flag")

proc resume*[T, F](ward: Ward[T, F]): bool =
  when ward.flags.contains Pausable:
    if `and`(ward.values.fetchAnd(complement({PushPausable, PopPausable}), moRelease), {PushPausable, PopPausable}) > 0'u16:
      # The ward is now resumed
      result = true
    else:
      # The ward was not paused
      result = false
  elif ward.flags.contains PushPausable:
    raise newException(ValueError, "Have to use resumePush unless the Pausable flag is used")
  elif ward.flags.contains PopPausable:
    raise newException(ValueError, "Have to use resumePop unless the Pausable flag is used")
  else:
    raise newException(ValueError, "Ward requires the pausable flag")

proc resumePush*[T, F](ward: Ward[T, F]): bool =
  when ward.flags.contains PushPausable:
    if `and`(ward.values.fetchAnd(complement({PushPausable}), moRelease), {PushPausable}) > 0'u16:
      # The ward is now resumed
      result = true
    else:
      # The ward was not paused
      result = false
  else:
    raise newException(ValueError, "Ward requires the pausable or pushpausable flag")

proc resumePop*[T, F](ward: Ward[T, F]): bool =
  when ward.flags.contains PopPausable:
    if `and`(ward.values.fetchAnd(complement({PopPausable}), moRelease), {PopPausable}) > 0'u16:
      # The ward is now resumed
      result = true
    else:
      # The ward was not paused
      result = false
  else:
    raise newException(ValueError, "Ward requires the pausable or poppausable flag")