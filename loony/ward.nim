## Ward introduces a state management container for the LoonyQueue.
##
## Principally, all interactions that you want to do with a LoonyQueue you
## can do through the ward ontop of any added behaviours you pass in as
## flags. This design separates added functionality from hampering the speed
## of loony operations when you do not use them. For instance, all wards
## that access a loony queue with a Pausable flag will prefix the operation
## with an atomic check to see if the ward is paused (this is not blocking, you
## simply receive a nil in the case of pop operations and a false bool on push ops).
##
## However, if you were to set only a PushPausable flag, then only the push operations
## will introduce the extra cost.
##
## Wards are ref objects and can therefore share the same many-to-one relationship
## that you expect from LoonyQueue. You can have separate wards pointing to the same
## queue but with separate flags and flag switches. Or you can have separate wards
## pointing to the same, with separate flags but THE SAME flag switches.

import loony/spec {.all.}
import loony/node {.all.}
import loony {.all.}

import loony/utils/futex

import std/atomics
import std/setutils
import std/sets

type
  WardFlag* {.size: sizeof(uint16).} = enum
    PopPausable = "popping off the queue with this ward can be paused"
    PushPausable= "pushing onto the queue with this ward can be paused"
    Clearable   = "this ward is capable of clearing the queue"
    Pausable    = "accessing the queue with this ward can be paused"
    # This flag will automatically infer PopPausable and PushPausable.
    PoolWaiter  = "you can"

  WardFlags = uint16

  Ward*[T; F: static[uint16]] = ref object
    queue*: LoonyQueue[T]
    values: Atomic[uint16]


converter toWardFlags*(flags: set[WardFlag]): WardFlags =
  ## Internal use
  # The vm cannot cast between set and integers
  when nimvm:
    for flag in items(flags):
      block:
        if flag == Pausable or flag == PoolWaiter:
          result = result or (1'u16 shl PopPausable.ord)
          result = result or (1'u16 shl PushPausable.ord)
        result = result or (1'u16 shl flag.ord)
      if PopPausable in flags and
          PushPausable in flags and
          not (Pausable in flags):
        result = result or (1'u16 shl Pausable.ord)

  else:
    result = cast[uint16](flags)
    if PopPausable in flags and
        PushPausable in flags and
        not (Pausable in flags):
      result = result or (1'u16 shl Pausable.ord)
    if flags.contains(Pausable) or flags.contains(PoolWaiter):
      result = result or (cast[uint16]({PopPausable, PushPausable}))

converter toFlags*(value: WardFlags): set[WardFlag] =
  ## Internal use
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
  ## Get the flags for the given ward
  F.toFlags()

proc init*(ward: Ward) =
  ## Initiate a ward object (for the moment this just 0's the atomic values)
  ward.values.store(0'u16)

proc newWard*[T](lq: LoonyQueue[T],
                flags: static set[WardFlag]): auto =
  ## Create a new ward for the queue with the flags given
  result = Ward[T, toWardFlags(flags)](queue: lq)
  init result

proc newWard*[T, F](wd: Ward[T, F],
                    flags: static set[WardFlag]): auto =
  ## Creates a ward with a different set of flags that are settable/observable
  ## that shares state with the given ward for the same queue.
  ## This can be used to create a ward for instance that will respond to
  ## poppauses only. If the other ward is paused for both pop and push, this ward
  ## will only respect the poppause.
  result = Ward[T, toWardFlags(flags)](queue: wd.queue, values: wd.values)

template isFlagOn(ward: Ward, flag: WardFlag): bool =
  when flag in ward.flags:
    `and`(ward.values.load(moAcquire), {flag}) > 0'u16
  else:
    false

import os

proc push*[T, F](ward: Ward[T, F], el: T): bool =
  ## Push the element through the ward onto the queue. If the ward is paused or
  ## there is some restriction on access, a false is returned (which means the
  ## el is still a valid reference/pointer).
  
  when PoolWaiter in F:
    if not ward.isFlagOn PushPausable:
      ward.queue.pushImpl(el, true)
      result = true
      wake(ward.values.addr())
  else:
    if not ward.isFlagOn PushPausable:
      ward.queue.push el
      result = true
proc unsafePush*[T, F](ward: Ward[T, F], el: T): bool =
  ## unsafePush the element through the ward onto the queue. If the ward is paused or
  ## there is some restriction on access, a false is returned (which means the
  ## el is still a valid reference/pointer)
  when PoolWaiter in F:
    if not ward.isFlagOn PushPausable:
      ward.queue.pushImpl(el, false)
      result = true
      wake(ward.values.addr())
  else:
    if not ward.isFlagOn PushPausable:
      ward.queue.unsafePush el
      result = true


proc pop*[T, F](ward: Ward[T, F]): T =
  ## Pop an element off the queue in the ward. If the ward is paused or
  ## there is some restriction on access, a nil pointer is returned
  when PoolWaiter in F and (T is ref or T is pointer):
    template truthy: untyped =
      not ward.isFlagOn(PopPausable) and
      (res = ward.queue.popImpl(true); res).isNil()
  elif PoolWaiter in F:
    template truthy: untyped =
      not ward.isFlagOn(PopPausable) and
      (res = ward.queue.popImpl(true); res) == default(T)

    var res: T
    while truthy:
      wait(ward.values.addr(), ward.values)
    return res

  else:
    if not ward.isFlagOn PopPausable:
      result = ward.queue.pop()

proc unsafePop*[T, F](ward: Ward[T, F]): T =
  ## unsafePop an element off the queue in the ward. If the ward is paused or
  ## there is some restriction on access, a nil pointer is returned
  when PoolWaiter in F:
    if not ward.isFlagOn PopPausable:
      while result.isNil:
        result = ward.queue.popImpl(false)
        if result.isNil:
          wait(ward.values.addr(), ward.values)
  else:
    if not ward.isFlagOn PopPausable:
      result = ward.queue.unsafePop()


template pauseImpl*[T, F](ward: Ward[T, F], flagset: set[WardFlag]): bool =
  when flagset * ward.flags == flagset:
    if `and`(cast[ptr uint16](ward.values.addr()).atomicFetchOr(flagset, ATOMIC_RELEASE), flagset) > 0'u16:
      true
    else:
      false
  else:
    raise ValueError.newException:
      "You require this flag on the ward: " & $flagset
template resumeImpl*[T, F](ward: Ward[T, F], flagset: set[WardFlag]): bool =
  when flagset * ward.flags == flagset:
    if `and`(ward.values.fetchAnd(complement flagset, moRelease), flagset) > 0'u16:
      true
    else:
      false
  else:
    raise ValueError.newException:
      "You require this flag on the ward: " & $flagset

proc killWaiters*[T, F](ward: Ward[T, F]) =
  when PoolWaiter in F:
    discard ward.pauseImpl({PopPausable})
    wakeAll(ward.values.addr())
# These pause functions will only stop ward access that have not yet begun.
# This must be kept in mind when considering activity on the queue else.
proc pause*[T, F](ward: Ward[T, F]): bool =
  ## Pause both push and pop operations for the ward.
  ## Will return a false if either pop or push were already paused (does not change outcome).
  ## Raises an error if the ward flags do not support this operation.
  ward.pauseImpl {PushPausable, PopPausable}
proc pausePush*[T, F](ward: Ward[T, F]): bool =
  ## Pause push operations for the ward
  ## Will return a false if push was already paused (does not change outcome).
  ## Raises an error if the ward flags do not support this operation.
  ward.pauseImpl {PushPausable}
proc pausePop*[T, F](ward: Ward[T, F]): bool =
  ## Pause pop operations for the ward
  ## Will return a false if pop was already paused (does not change outcome).
  ## Raises an error if the ward flags do not support this operation.
  ward.pauseImpl {PopPausable}
proc resume*[T, F](ward: Ward[T, F]): bool =
  ## Resume all operations for the ward
  ## Will return a false if push/pop were not paused (does not change outcome).
  ## Raises an error if the ward flags do not support this operation.
  ward.resumeImpl {PushPausable, PopPausable}
proc resumePush*[T, F](ward: Ward[T, F]): bool =
  ## Resume push operations for the ward
  ## Will return a false if push was not paused (does not change outcome).
  ## Raises an error if the ward flags do not support this operation.
  ward.resumeImpl {PushPausable}
proc resumePop*[T, F](ward: Ward[T, F]): bool =
  ## Resume pop operations for the ward
  ## Will return a false if pop was not paused (does not change outcome).
  ## Raises an error if the ward flags do not support this operation.
  ward.resumeImpl {PopPausable}

template isImpl[T, F](ward: Ward[T, F], flags: set[WardFlag]): bool =
  when flags.intersection ward.flags == flags:
    if `and`(ward.values.load(moRelaxed), flags) == flags:
      result = true
  else:
    raise ValueError.newException:
      "You require this flag on the ward: " & $flags

proc isPaused*[T, F](ward: Ward[T, F]): bool =
  ## Returns true if BOTH push and pop are paused.
  ## Raises an error if the ward flags do not support this operation.
  ward.isImpl {PushPausable, PopPausable}
proc isPopPaused*[T, F](ward: Ward[T, F]): bool =
  ## Returns true if pop is paused.
  ## Raises an error if the ward flags do not support this operation.
  ward.isImpl {PopPausable}
proc isPushPaused*[T, F](ward: Ward[T, F]): bool =
  ## Returns true if push is paused.
  ## Raises an error if the ward flags do not support this operation.
  ward.isImpl {PushPausable}

proc clearImpl[T](queue: LoonyQueue[T]) =
  var newNode = allocNode()
  # load the tail
  var currTail = queue.fetchTail()
  # Load the tails next node
  var tailNext = currTail.node.fetchNext()
  # New nodes will not have the next node set
  # If it has been set then the queue is in the process of having
  # the tail changed and we will continuosly load it until we get the nil next
  while not cast[ptr Node](tailNext).isNil():
    currTail = queue.fetchTail()
    tailNext = currTail.node.fetchNext()
  # We will replace the tails next node with our newNode. This ensures any ops
  # that were about to try and set a new node are prevented and will instead
  # help us to add our new node
  while not currTail.node.compareAndSwapNext(tailNext, newNode):
    # If it doesnt work then we must have just been beaten to it, load the next
    # node and swap that instead
    currTail = queue.fetchTail()
  # TODO I feel that I have to ensure that if I run into the situation where I have
  # intercepted threads setting new nodes, that memory reclamation occurs as it should

  # Now I will swap the queues current tail with the new tail that we set.
  # If it doesn't work its probably because another thread did a pop and changed
  # the index so I will keep increasing the currTail index until it is successful
  # REVIEW I might just do a store at this point instead of a CAS
  while not queue.compareAndSwapTail(currTail, newNode):
    currTail += 1
  # Get the head node
  var head = queue.fetchHead()
  # We will try straight up swap the head node with our new node
  while not queue.compareAndSwapHead(head, newNode):
    # Keep updating the head node till it works
    head = queue.fetchHead()
    # TODO will have to do a check here to see if the head is
    # the same as our newNode in which case can just stop

  # Now we can begin clearing the nodes
  block done:
    while true:
      # Check if the head is the same as our newNode in which
      # case we have already cleared all the previous nodes and
      # deallocated them
      if head.nptr == newNode.nptr:
        break done
      for i in 0..<N:
        # For every slot in the heads slot, load the value
        var slot = head.node.slots[i].load(moRelaxed)
        # If the slot has been consumed then we will move on (its already been derefd)
        if not (slot and CONSUMED):
          # Slot hasnt been consumed so we will load it
          var el = cast[T](slot and SLOTMASK)
          # If slot is not a nil ref then we will unref it
          when T is ref:
            if not el.isNil:
              GC_unref el
      # After unrefing the slots, we will load the next node in the list
      var dehead = deepCopy(head)
      head = head.node.fetchNext()
      # Deallocate the consumed node
      deallocNode(dehead.nptr)

  # and now hopefully  nothing bad happens.

proc clear*[T, F](ward: Ward[T, F]) =
  ## UNSTABLE/UNTESTED
  ## Clears the loonyQueue. This does not block any threads which are pushing/popping
  ## off the queue. It will be performed safely, however if you want a deterministic
  ## clear of the queue, it is recommended to have all threads pushing/popping through
  ## a ward with a Pause flag to call before you clear the queue.
  when Clearable in ward.flags:
    ward.queue.clearImpl()
  else:
    raise ValueError.newException:
      "This ward does not have the Clearable flag set"

proc countImpl[T](queue: LoonyQueue[T]): int =
  var head = queue.fetchHead()
  var nodes: int
  var andysBalls: TagPtr = head
  while true:
    andysBalls = andysBalls.node.next.load(moRelaxed)
    if andysBalls == 0'u:
      break
    inc nodes
  var (currHead, currTail) = queue.maneAndTail()
  if not currHead.nptr == head.nptr:
    dec nodes
  result = nodes * N + (N - currHead.idx) + currTail.idx

proc count*[T, F](ward: Ward[T, F]) =
  ## Does as labelled on the bottle. The nature of loony queue means that the returned
  ## value is not 100% accurate when there is high contention/activity on the queue.
  countImpl ward.queue
