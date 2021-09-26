## This contains the LoonyQueue object and associated push/pop operations.
## 
## There is a detailed explanation of the algorithm operation within the src
## files if you are having issues or want to contribute.

import std/atomics

import loony/spec
import loony/node

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

proc nptr(tag: TagPtr): NodePtr = toNodePtr(tag and PTRMASK)
proc node(tag: TagPtr): var Node = cast[ptr Node](tag.nptr)[]
proc idx(tag: TagPtr): uint16 = uint16(tag and TAGMASK)
proc tag(tag: TagPtr): uint16 = tag.idx
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

template fetchCurrTail(queue: LoonyQueue): NodePtr =
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

# Both enqueue and dequeue enter FAST PATH operations 99% of the time,
# however in cases we enter the SLOW PATH operations represented in both
# enq and deq by advTail and advHead respectively.
#
# This path requires the threads to first help updating the linked list
# struct before retrying and entering the fast path in the next attempt.

proc advTail[T](queue: LoonyQueue[T]; el: T; t: NodePtr): AdvTail =
  ## Modified Michael-Scott algorithm

  while true:
    var tail = queue.fetchTail
    if t != tail.nptr:
      incrEnqCount t.toNode
      result = AdvOnly
      break

    template tailSwapper(with: uint): untyped {.dirty.} =
      while not queue.compareAndSwapTail(tail, with + 1):
        if t != tail.nptr:
          incrEnqCount t.toNode
          break
      incrEnqCount(t.toNode, tail.idx - N)

    var next = t.fetchNext()
    if cast[ptr Node](next).isNil():
      var node = cast[uint](allocNode el) # REVIEW no writer bit set?
      var null = 0'u
      if t.compareAndSwapNext(null, node):
        result = AdvAndInserted
        tailSwapper(node)
        break
      else:
        `=destroy`(cast[ptr Node](node)[])
    else: # T20
      result = AdvOnly
      tailSwapper(next)
      break

proc advHead(queue: LoonyQueue; curr: var TagPtr;
             h, t: NodePtr): AdvHead =
  if h.idx == N:
    # This should reliably trigger reclamation of the node memory on the last
    # read of the head.
    tryReclaim(h.toNode, 0'u8)
  var next = fetchNext h
  result =
    if cast[ptr Node](next).isNil() or (t == h):
      incrDeqCount h.toNode
      QueueEmpty
    else:
      # Equivalent to (nptr: NodePtr, idx: idx+=1)
      curr += 1
      block done:
        while not queue.compareAndSwapHead(curr, next.nptr):
          if curr.nptr != h:
            incrDeqCount h.toNode
            break done
        incrDeqCount(h.toNode, curr.idx - N)
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

proc push*[T](queue: LoonyQueue[T], el: T) =
  # Begin by tagging pointer el with WRITER bit
  var pel = prepareElement el
  # Ensure all writes in STOREBUFFER are committed. By far the most costly
  # primitive; it will be preferred while proving safety before working towards
  # optimisation by atomic reads/writes of cache lines related to el
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
      case queue.advTail(pel, tag.nptr)
      of AdvAndInserted:
        break
      of AdvOnly:
        discard

proc isEmptyImpl(head, tail: TagPtr): bool {.inline.} =
  if head.idx >= N or head.idx >= tail.idx:
    result = head.nptr == tail.nptr

proc isEmpty*(queue: LoonyQueue): bool =
  let (head, tail) = maneAndTail queue
  isEmptyImpl(head, tail)

proc pop*[T](queue: LoonyQueue[T]): T =
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
      case queue.advHead(curr, head.nptr, tail.nptr)
      of Advanced:
        discard
      of QueueEmpty:
        break

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
  for i in 0..N:
    var h = load headTag.toNode().slots[i]
    var t = load tailTag.toNode().slots[i]
    assert h == 0, "Slot found to not be nil on initialisation"
    assert t == 0, "Slot found to not be nil on initialisation"
  # I mean the enqueue and dequeue pretty well handle any issues with
  # initialising, but I might as well help allocate the first ones right?

proc initLoonyQueue*[T](): LoonyQueue[T] =
  ## Return an initialized LoonyQueue.
  # TODO destroy proc
  new result
  initLoonyQueue result
