import loony/spec {.all.}
import loony/node {.all.}
import loony {.all.}

import std/atomics
import std/setutils

type
  WardFlag* {.size: sizeof(uint16).} = enum
    PopPausable = "popping off the queue with this ward can be paused"
    PushPausable= "pushing onto the queue with this ward can be paused"
    Clearable   = "this ward is capable of clearing the queue"

    Pausable    = "accessing the queue with this ward can be paused" # Keep this flag on the end
    # This flag will automatically infer PopPausable and PushPausable.
  WardFlags* = uint16

  Ward*[T; F: static[uint16]] = ref object
    queue: LoonyQueue[T]
    values: Atomic[uint16]


converter toWardFlags*(flags: set[WardFlag]): WardFlags =
  # The vm cannot cast between set and integers
  when nimvm:
    for flag in items(flags):
      block:
        if flag == Pausable:
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
    if flags.contains Pausable:
      result = result or (cast[uint16]({PopPausable, PushPausable}))

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

proc push*[T, F](ward: Ward[T, F], el: T): bool =
  if not ward.isFlagOn PushPausable:
    ward.queue.push el
    result = true
proc unsafePush*[T, F](ward: Ward[T, F], el: T): bool =
  if not ward.isFlagOn PushPausable:
    ward.queue.unsafePush el
    result = true

proc pop*[T, F](ward: Ward[T, F]): T =
  if not ward.isFlagOn PopPausable:
    ward.queue.pop()
proc unsafePop*[T, F](ward: Ward[T, F]): T =
  if not ward.isFlagOn PopPausable:
    ward.queue.unsafePop()


template pauseImpl*[T, F](ward: Ward[T, F], flags: set[WardFlag]): bool =
  when flags.intersection ward.flags == flags:
    if `and`(ward.values.fetchOr(flags, moRelease), flags) > 0'u16:
      true
    else:
      false
  else:
    raise ValueError.newException:
      "You require this flag on the ward: " & $flags
template resumeImpl*[T, F](ward: Ward[T, F], flag: set[WardFlag]): bool =
  when flags.intersection ward.flags == flags:
    if `and`(ward.values.fetchAnd(complement flags, moRelease), flags) > 0'u16:
      true
    else:
      false
  else:
    raise ValueError.newException:
      "You require this flag on the ward: " & $flags
# These pause functions will only stop ward access that have not yet begun.
# This must be kept in mind when considering activity on the queue else.
proc pause*[T, F](ward: Ward[T, F]): bool =
  ward.pauseImpl {PushPausable, PopPausable}
proc pausePush*[T, F](ward: Ward[T, F]): bool =
  ward.pauseImpl {PushPausable}
proc pausePop*[T, F](ward: Ward[T, F]): bool =
  ward.pauseImpl {PopPausable}
proc resume*[T, F](ward: Ward[T, F]): bool =
  ward.resumeImpl {PushPausable, PopPausable}
proc resumePush*[T, F](ward: Ward[T, F]): bool =
  ward.resumeImpl {PushPausable}
proc resumePop*[T, F](ward: Ward[T, F]): bool =
  ward.resumeImpl {PopPausable}

template isImpl[T, F](ward: Ward[T, F], flags: set[WardFlag]): bool =
  when flags.intersection ward.flags == flags:
    if `and`(ward.values.load(moRelaxed), flags) == flags:
      result = true
  else:
    raise ValueError.newException:
      "You require this flag on the ward: " & $flags

proc isPaused*[T, F](ward: Ward[T, F]): bool =
  ward.isImpl {PushPausable, PopPausable}
proc isPopPaused*[T, F](ward: Ward[T, F]): bool =
  ward.isImpl {PopPausable}
proc isPushPaused*[T, F](ward: Ward[T, F]): bool =
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
          if not el.isNil:
            GC_unref el
      # After unrefing the slots, we will load the next node in the list
      var dehead = deepCopy(head)
      head = head.node.fetchNext()
      # Deallocate the consumed node
      deallocNode(dehead.nptr)
      
  # and now hopefully  nothing bad happens.


proc clear*[T, F](ward: Ward[T, F]) =
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
  countImpl ward.queue