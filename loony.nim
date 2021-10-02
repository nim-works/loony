## This contains the LoonyQueue object and associated push/pop operations.
##
## There is a detailed explanation of the algorithm operation within the src
## files if you are having issues or want to contribute.

import std/atomics

import loony/spec
import loony/node

export
  node.echoDebugNodeCounter, node.debugNodeCounter  
# sprinkle some raise defect
# raise Defect(nil) | yes i am the
# raise Defect(nil) | salt bae of defects
# raise Defect(nil) |
# raise Defect(nil) | I am defect bae
# raise Defect(nil) |
# and one more for haxscrampers pleasure
# raise Defect(nil)

type
  LoonyQueue*[T: ref] = ref object
    head     : Atomic[TagPtr]     ## Whereby node contains the slots and idx
    tail     : Atomic[TagPtr]     ## is the uint16 index of the slot array
    currTail : Atomic[NodePtr]    ## 8 bytes Current NodePtr

  ## Result types for the private
  ## advHead and advTail functions
  AdvTail = enum
    AdvAndInserted  # 0000_0000
    AdvOnly         # 0000_0001
  AdvHead = enum
    QueueEmpty      # 0000_0000
    Advanced        # 0000_0001

# TagPtr is an alias for 8 byte uint (pointer). We reserve a portion of
# the tail to contain the index of the slot to its corresponding node
# by aligning the node pointers on allocation. Since the index value is
# stored in the same memory word as its associated node pointer, the FAA
# operations could potentially affect both values if too many increments
# were to occur. This is accounted for in the algorithm and with space
# for overflow in the alignment. See Section 5.2 for the paper to see
# why an overflow would prove impossible except under extraordinarily
# large number of thread contention.

template nptr(tag: TagPtr): NodePtr = toNodePtr(tag and PTRMASK)
template node(tag: TagPtr): var Node = cast[ptr Node](nptr(tag))[]
template idx(tag: TagPtr): uint16 = uint16(tag and TAGMASK)
proc toStrTuple*(tag: TagPtr): string =
  var res = (nptr:tag.nptr, idx:tag.idx)
  return $res

proc fetchAddSlot(tag: TagPtr; w: uint): uint =
  ## A convenience to fetchAdd the node's slot.
  fetchAddSlot(cast[ptr Node](nptr tag)[], idx tag, w)

template fetchTail(queue: LoonyQueue, moorder: MemoryOrder = moRelaxed): TagPtr =
  ## get the TagPtr of the tail (nptr: NodePtr, idx: uint16)
  TagPtr(load(queue.tail, order = moorder))

template fetchHead(queue: LoonyQueue, moorder: MemoryOrder = moRelaxed): TagPtr =
  ## get the TagPtr of the head (nptr: NodePtr, idx: uint16)
  TagPtr(load(queue.head, order = moorder))

template maneAndTail(queue: LoonyQueue): (TagPtr, TagPtr) =
  (fetchHead queue, fetchTail queue)
template tailAndMane(queue: LoonyQueue): (TagPtr, TagPtr) =
  (fetchTail queue, fetchHead queue)

template fetchCurrTail(queue: LoonyQueue): NodePtr {.used.} =
  # get the NodePtr of the current tail
  cast[NodePtr](load(queue.currTail, moRelaxed))

# Bug #11 - Using these as templates would cause errors unless the end user
# imported std/atomics or we export atomics.
# For the sake of not polluting the users namespace I have changed these into procs.
# Atomic inc of idx in (nptr: NodePtr, idx: uint16)
proc fetchIncTail(queue: LoonyQueue, moorder: MemoryOrder = moAcquire): TagPtr =
  cast[TagPtr](queue.tail.fetchAdd(1, order = moorder))
proc fetchIncHead(queue: LoonyQueue, moorder: MemoryOrder = moAcquire): TagPtr =
  cast[TagPtr](queue.head.fetchAdd(1, order = moorder))


template compareAndSwapTail(queue: LoonyQueue, expect: var uint, swap: uint | TagPtr): bool =
  queue.tail.compareExchange(expect, swap)

template compareAndSwapHead(queue: LoonyQueue, expect: var uint, swap: uint | TagPtr): bool =
  queue.head.compareExchange(expect, swap)

template compareAndSwapCurrTail(queue: LoonyQueue, expect: var uint,
                                swap: uint | TagPtr): bool {.used.} =
  queue.currTail.compareExchange(expect, swap)

proc clearImpl*[T](queue: LoonyQueue[T]) =
  ## This is used internally by the Ward objects. The queue
  ## should only be cleared using that object. However, there
  ## is no harm necessarily with using this procedure directly atm.
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

# Both enqueue and dequeue enter FAST PATH operations 99% of the time,
# however in cases we enter the SLOW PATH operations represented in both
# enq and deq by advTail and advHead respectively.
#
# This path requires the threads to first help updating the linked list
# struct before retrying and entering the fast path in the next attempt.

proc advTail[T](queue: LoonyQueue[T]; pel: uint; tag: TagPtr): AdvTail =
  # Modified version of Michael-Scott algorithm
  # Attempt allocate & append new node on previous tail
  var origTail = tag.nptr
  block done:
    while true:
      # First we get the current tail
      var currTTag = queue.fetchTail()
      if origTail != currTTag.nptr:
        # Another thread has appended a new node already. Help clean node up.
        incrEnqCount origTail.toNode
        result = AdvOnly
        break done
      # Get current tails next node
      var next = origTail.fetchNext()
      if cast[ptr Node](next).isNil():
        # Prepare the new node with our element in it
        var (node, null) = (allocNode pel, 0'u)  # Atomic compareExchange requires variables
        if origTail.compareAndSwapNext(null, node.toUint):
          # Successfully inserted our node into current/original nodes next
          # Since we have already inserted a slot, we try to replace the queues
          # tail tagptr with the new node with an index of 1
          while not queue.compareAndSwapTail(currTTag, node.toUint + 1):
            # Loop is not relevant to compareAndSwapStrong; consider weak swap?
            if currTTag.nptr != origTail:
              # REVIEW This does not make sense unless we reload the
              #        the current tag?
              incrEnqCount origTail.toNode
              result = AdvAndInserted
              break done
          # Successfully updated the queue.tail and node.next with our new node
          # Help clean up this node
          incrEnqCount(origTail.toNode, currTTag.idx - N)
          result = AdvAndInserted
          break done
        # Another thread inserted a new node before we could; deallocate and try
        # again. New currTTag will mean we enter the first if condition statement.
        deallocNode node
      else:
        # The next node has already been set, help the thread to set the next
        # node in the queue tail
        while not queue.tail.compareExchange(currTTag, next + 1):
          # Loop is not relevant to CAS-strong; consider weak CAS?
          if currTTag.nptr != origTail:
            # REVIEW this does not make sense unless we reload the current tag?
            incrEnqCount origTail.toNode
            result = AdvOnly
            break done
        # Successfully updated the queue.tail with another threads node; we
        # help clean up this node and thread is free to adv and try push again
        incrEnqCount(origTail.toNode, currTTag.idx - N)
        result = AdvOnly
        break done



    

proc advHead(queue: LoonyQueue; curr, h, t: var TagPtr): AdvHead =
  if h.idx == N:
    # This should reliably trigger reclamation of the node memory on the last
    # read of the head.
    tryReclaim(h.node, 0'u8)
  result =
    if t.nptr == h.nptr:
      incrDeqCount h.node
      QueueEmpty
    else:
      var next = fetchNext h.nptr
      # Equivalent to (nptr: NodePtr, idx: idx+=1)
      curr += 1
      block done:
        while not queue.compareAndSwapHead(curr, next):
          if curr.nptr != h.nptr:
            incrDeqCount h.node
            break done
        incrDeqCount(h.node, curr.idx - N)
      Advanced

# Fundamentally, both enqueue and dequeue operations attempt to
# exclusively reserve access to a slot in the array of their associated
# queue node by automatically incremementing the appropriate index value
# and retrieving the previous value of the index as well as the current
# node pointer.
#
# Threads that retrieve an index i < N (length of the slots array) gain
# *exclusive* rights to perform either write/consume operation on the
# corresponding slot.
#
# This guarantees there can only be exactly one of each for any given
# slot.
#
# Where i < N, we use FAST PATH operations. These operations are
# designed to be as fast as possible while only dealing with memory
# contention in rare edge cases.
#
# if not i < N, we enter SLOW PATH operations. See AdvTail and AdvHead
# above.
#
# Fetch And Add (FAA) primitives are used for both incrementing index
# values as well as performing read(consume) and write operations on
# reserved slots which drastically improves scalability compared to
# Compare And Swap (CAS) primitives.
#
# Note that all operations on slots must modify the slots state bits to
# announce both operations completion (in case of a read) and also makes
# determining the order in which two operations occured possible.

proc pushImpl[T](queue: LoonyQueue[T], el: T,
                    forcedCoherance: static bool = false) =
  doAssert not queue.isNil(), "The queue has not been initialised"
  # Begin by tagging pointer el with WRITER bit
  var pel = prepareElement el
  # Ensure all writes in STOREBUFFER are committed. By far the most costly
  # primitive; it will be preferred while proving safety before working towards
  # optimisation by atomic reads/writes of cache lines related to el
  when forcedCoherance:
    atomicThreadFence(ATOMIC_RELEASE)
  while true:
    # Enq proc begins with incr the index of node in TagPtr
    var tag = fetchIncTail(queue)
    if likely(tag.idx < N):
      # FAST PATH OPERATION - 99% of push will enter here; we want the minimal
      # amount of necessary operations in this path.
      # Perform a FAA on our reserved slot which should be 0'd.
      let prev = tag.fetchAddSlot pel
      case prev
      of 0, RESUME:
        break           # the slot was empty; we're good to go

      # If READER bit already set,then the corresponding deq op arrived
      # early; we must consequently abandon the slot and retry.

      of RESUME or READER:
        # Checking RESUME bit pertains to memory reclamation mechanism;
        # only relevant in rare edge cases in which the Enq op significantly
        # delayed and lags behind other ops on the same node
        tryReclaim(tag.node, tag.idx + 1)
      else:
        # Should the case above occur or we detect that the slot has been
        # filled by some gypsy magic then we will retry on the next loop.
        discard

    else:
      # SLOW PATH; modified version of Michael-Scott algorithm
      case queue.advTail(pel, tag)
      of AdvAndInserted:
        break
      of AdvOnly:
        discard



proc push*[T](queue: LoonyQueue[T], el: T) =
  ## Push an item onto the end of the LoonyQueue.
  ## This operation ensures some level of cache coherency using atomic thread fences.
  ## 
  ## Use unsafePush to avoid this cost.
  pushImpl(queue, el, forcedCoherance = true)
proc unsafePush*[T](queue: LoonyQueue[T], el: T) =
  ## Push an item onto the end of the LoonyQueue.
  ## Unlike push, this operation does not use atomic thread fences. This means you
  ## may get undefined behaviour if the receiving thread has old cached memory
  ## related to this element
  pushImpl(queue, el, forcedCoherance = false)

proc isEmptyImpl(head, tail: TagPtr): bool {.inline.} =
  if head.idx >= N or head.idx >= tail.idx:
    result = head.nptr == tail.nptr

proc isEmpty*(queue: LoonyQueue): bool =
  ## This operation should only be used by internal code. The response for this
  ## operation is not precise.
  let (head, tail) = maneAndTail queue
  isEmptyImpl(head, tail)

proc popImpl[T](queue: LoonyQueue[T]; forcedCoherance: static bool = false): T =
  doAssert not queue.isNil(), "The queue has not been initialised"
  while true:
    # Before incr the deq index, init check performed to determine if queue is empty.
    # Ensure head is loaded last to keep mem hot
    var (tail, curr) = tailAndMane queue
    if isEmptyImpl(curr, tail):
      # Queue was empty; nil can be caught in cps w/ "while cont.running"
      return nil

    var head = queue.fetchIncHead()
    if likely(head.idx < N):
      # FAST PATH OPS
      var prev = head.fetchAddSlot READER
      # Last slot in a node - init reclaim proc; if WRITER bit set then upper bits
      # contain a valid pointer to an enqd el that can be returned (see enqueue)
      if not unlikely((prev and SLOTMASK) == 0):
        if (prev and spec.WRITER) != 0:
          if unlikely((prev and RESUME) != 0):
            tryReclaim(head.node, head.idx + 1)

          # Ideally before retrieving the ref object itself, we want to allow
          # CPUs to communicate cache line changes and resolve invalidations
          # to dirty memory.
          when forcedCoherance:
            atomicThreadFence(ATOMIC_ACQUIRE)
          # CPU halt and clear STOREBUFFER; overwritten cache lines will be
          # syncd and invalidated ensuring fresh memory from this point in line
          # with the PUSH operations atomicThreadFence(ATOMIC_RELEASE)
          # This is the most costly primitive fill the requirement and will be
          # preferred to prove safety before optimising by targetting specific
          # cache lines with atomic writes and loads rather than requiring a
          # CPU to completely commit its STOREBUFFER

          result = cast[T](prev and SLOTMASK)
          assert result != nil
          GC_unref result
          break
    else:
      # SLOW PATH OPS
      case queue.advHead(curr, head, tail)
      of Advanced:
        discard
      of QueueEmpty:
        break

proc pop*[T](queue: LoonyQueue[T]): T =
  ## Remove and return to the caller the next item in the LoonyQueue.
  ## This operation ensures some level of cache coherency using atomic thread fences.
  ## 
  ## Use unsafePop to avoid this cost.
  popImpl(queue, forcedCoherance = true)
proc unsafePop*[T](queue: LoonyQueue[T]): T =
  ## Remove and return to the caller the next item in the LoonyQueue.
  ## Unlike pop, this operation does not use atomic thread fences. This means you
  ## may get undefined behaviour if the caller has old cached memory that is
  ## related to the item.
  popImpl(queue, forcedCoherance = false)

# Consumed slots have been written to and then read. If a concurrent
# deque operation outpaces the corresponding enqueue operation then both
# operations have to abandon and try again. Once all slots in the node
# have been consumed or abandoned, the node is considered drained and
# unlinked from the list. Node can be reclaimed and de-allocated.
#
# Queue manages an enqueue index and a dequeue index. Each are modified
# by fetchAndAdd; gives thread reserves previous index for itself which
# may be used to address a slot in the respective nodes array.
#
# both node pointers are tagged with their assoc index value ->
# they store both address to respective node as well as the current
# index value in the same memory word.
#
# Requires a sufficient number of available bits that are not used to
# present the nodes addresses themselves.

proc initLoonyQueue*(q: LoonyQueue) =
  ## Initialize an existing LoonyQueue.
  var headTag = cast[uint](allocNode())
  var tailTag = headTag
  q.head.store headTag
  q.tail.store tailTag
  q.currTail.store tailTag
  for i in 0..<N:
    var h = load headTag.toNode().slots[i]
    var t = load tailTag.toNode().slots[i]
    assert h == 0, "Slot found to not be nil on initialisation"
    assert t == 0, "Slot found to not be nil on initialisation"
  # I mean the enqueue and dequeue pretty well handle any issues with
  # initialising, but I might as well help allocate the first ones right?

proc initLoonyQueue*[T](): LoonyQueue[T] {.deprecated: "Use newLoonyQueue instead".} =
  ## Return an initialized LoonyQueue.
  # TODO destroy proc
  new result
  initLoonyQueue result

proc newLoonyQueue*[T](): LoonyQueue[T] =
  ## Return an intialized LoonyQueue.
  new result
  initLoonyQueue result