## Copyright (c) 2021 Shayan Habibi
## 
## Original algorithm and research conducted by Oliver Giersch. Please see the
## linked article from our github repo.
## 
## An in depth explanation of the algorithm is found within the source code.
## 
## For clarity, the use of `Atomic[T]` types are not used, however atomic
## operations are employed.

import loony/debug
import loony/spec
import loony/node

export
  debug.echoDebugNodeCounter, debug.debugNodeCounter

type
  LoonyQueue*[T] = ref LoonyQueueImpl[T]
  LoonyQueueImpl*[T] = object
    head     : TagPtr     ## Whereby node contains the slots and idx
    tail     : TagPtr     ## is the uint16 index of the slot array
    currTail : ptr Node   ## 8 bytes Current NodePtr
  SCLoonyQueue*[T] = ref LoonyQueueImpl[T]
  ## Result types for the private
  ## advHead and advTail functions
  AdvTail = enum
    AdvAndInserted  # 0000_0000
    AdvOnly         # 0000_0001
  AdvHead = enum
    QueueEmpty      # 0000_0000
    Advanced        # 0000_0001

#[
  TagPtr is an alias for 8 byte uint (pointer). We reserve a portion of
  the tail to contain the index of the slot to its corresponding node
  by aligning the node pointers on allocation. Since the index value is
  stored in the same memory word as its associated node pointer, the FAA
  operations could potentially affect both values if too many increments
  were to occur. This is accounted for in the algorithm and with space
  for overflow in the alignment. See Section 5.2 for the paper to see
  why an overflow would prove impossible except under extraordinarily
  large number of thread contention.
]#

template fetchAddSlot(tag: TagPtr; w: uint, order = AcqRel): uint =
  mixin getPtr
  mixin getTag
  tag.getPtr.slots[tag.getTag].fetchAdd(w, order)

template maneAndTail(queue: LoonyQueue): (TagPtr, TagPtr) =
  mixin load
  (queue.head.load(Rlx), queue.tail.load(Rlx))
template tailAndMane(queue: LoonyQueue): (TagPtr, TagPtr) =
  mixin load
  (queue.tail.load(Rlx), queue.head.load(Rlx))

template fetchIncTail(queue: LoonyQueue, order = Acq): TagPtr =
  queue.tail.fetchAdd(1, order)
template fetchIncHead(queue: LoonyQueue, order = Acq): TagPtr =
  queue.head.fetchAdd(1, order)

proc `=destroy`*[T](x: var LoonyQueueImpl[T]) =
  ## Destroy is completely operated on the basis that no other threads are
  ## operating on the queue at the same time. To not follow this will result in
  ## SIGSEGVs and undefined behaviour.
  var loadedLine: int # we want to track what cache line we have loaded and
                      # ensure we perform an atomic load at least once on each cache line
  var headNodeIdx: (ptr Node, uint16)
  var tailNode: ptr Node
  var tailIdx: uint16
  var slotptr: ptr uint
  var slotval: uint
  block:

    template getHead: untyped =
      let tptr = x.head.load()
      headNodeIdx = (tptr.getPtr, tptr.getTag.uint16)

    template getTail: untyped =
      if tailNode.isNil():
        let tptr = x.tail.load()
        tailNode = tptr.getPtr
        tailIdx = tptr.getTag.uint16
        loadedLine = cast[int](tailNode)
      else:
        let oldNode = tailNode
        tailNode = tailNode.next.load()
        tailIdx = 0'u16
        deallocNode oldNode

    template loadSlot: untyped =
      slotptr = cast[ptr uint](tailNode.slots[tailIdx].addr())
      if (loadedLine + 64) < cast[int](slotptr):
        slotval = slotptr.atomicLoadN(ATOMIC_RELAXED)
        loadedLine = cast[int](slotptr)
      elif not slotptr.isNil():
        slotval = slotptr[]
      else:
        slotval = 0'u
        

    template truthy: bool =
      (tailNode, tailIdx) == headNodeIdx
    template idxTruthy: bool =
      if tailNode == headNodeIdx[1]:
        tailIdx < loonySlotCount
      else:
        tailIdx <= headNodeIdx[1]


    getHead()
    getTail()
    if (loadedLine mod 64) != 0:
      loadedLine = loadedLine - (loadedLine mod 64)

    while not truthy:
      
      while idxTruthy:
        loadSlot()
        if (slotval and spec.WRITER) == spec.WRITER:
          if (slotval and CONSUMED) == CONSUMED:
            inc tailIdx
          elif (slotval and PTRMASK) != 0'u:
            var el = cast[T](slotval and PTRMASK)
            when T is ref:
              GC_unref el
            else:
              `=destroy`(el)
            inc tailIdx
        else:
          break
      getTail()
      if tailNode.isNil():
        break
    if not tailNode.isNil():
      deallocNode(tailNode)

#[
  Both enqueue and dequeue enter FAST PATH operations 99% of the time,
  however in cases we enter the SLOW PATH operations represented in both
  enq and deq by advTail and advHead respectively.

  This path requires the threads to first help updating the linked list
  struct before retrying and entering the fast path in the next attempt.
]#

template prepareElement[T](el: T): uint =
  ## Prepare an item to be taken into the queue; we bump the RC first to
  ## ensure that no other operations free it, then add the WRITER bit.
  when T is ref:
    GC_ref el
  cast[uint](el) or WRITER

proc advTail[T](queue: LoonyQueue[T] | SCLoonyQueue[T]; pel: uint; tag: TagPtr): AdvTail =
  # Modified version of Michael-Scott algorithm
  # Attempt allocate & append new node on previous tail
  var origTail = tag.getPtr
  block done:
    while true:
      # First we get the current tail
      var currTTag = queue.tail.load(Rlx)
      if origTail != currTTag.getPtr:
        # Another thread has appended a new node already. Help clean node up.
        incrEnqCount origTail
        result = AdvOnly
        break done
      # Get current tails next node
      var next = origTail.next.load()
      if next.isNil():
        # Prepare the new node with our element in it
        var (node, null) = (allocNode pel, (0u).toNodePtr)  # Atomic compareExchange requires variables
        if origTail.next.compareExchange(null, node):
          # Successfully inserted our node into current/original nodes next
          # Since we have already inserted a slot, we try to replace the queues
          # tail tagptr with the new node with an index of 1
          while not queue.tail.compareExchange(currTTag, node.toUint + 1):
            # Loop is not relevant to compareAndSwapStrong; consider weak swap?
            if currTTag.getPtr != origTail:
              # REVIEW This does not make sense unless we reload the
              #        the current tag?
              incrEnqCount origTail
              result = AdvAndInserted
              break done
          # Successfully updated the queue.tail and node.next with our new node
          # Help clean up this node
          incrEnqCount(origTail, uint16(currTTag.getTag - loonySlotCount))
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
          if currTTag.getPtr != origTail:
            # REVIEW this does not make sense unless we reload the current tag?
            incrEnqCount origTail
            result = AdvOnly
            break done
        # Successfully updated the queue.tail with another threads node; we
        # help clean up this node and thread is free to adv and try push again
        incrEnqCount(origTail, uint16(currTTag.getTag - loonySlotCount))
        result = AdvOnly
        break done

proc advHead(queue: LoonyQueue; curr, h, t: var TagPtr): AdvHead =
  if h.getTag == loonySlotCount:
    # This should reliably trigger reclamation of the node memory on the last
    # read of the head.
    tryReclaim(h.getPtr, 0'u8)
  result =
    if t.getPtr == h.getPtr:
      incrDeqCount h.getPtr
      QueueEmpty
    else:
      var next = h.getPtr.next.load()
      # Equivalent to (nptr: NodePtr, idx: idx+=1)
      curr.tag += 1
      block done:
        while not queue.head.compareExchange(curr, cast[TagPtr](next)):
          if curr.getPtr != h.getPtr:
            incrDeqCount h.getPtr
            break done
        incrDeqCount(h.getPtr, uint16(curr.tag - loonySlotCount))
      Advanced

#[
  Fundamentally, both enqueue and dequeue operations attempt to
  exclusively reserve access to a slot in the array of their associated
  queue node by automatically incremementing the appropriate index value
  and retrieving the previous value of the index as well as the current
  node pointer.

  Threads that retrieve an index i < loonySlotCount (length of the slots array) gain
  *exclusive* rights to perform either write/consume operation on the
  corresponding slot.

  This guarantees there can only be exactly one of each for any given
  slot.

  Where i < loonySlotCount, we use FAST PATH operations. These operations are
  designed to be as fast as possible while only dealing with memory
  contention in rare edge cases.

  if not i < loonySlotCount, we enter SLOW PATH operations. See AdvTail and AdvHead
  above.

  Fetch And Add (FAA) primitives are used for both incrementing index
  values as well as performing read(consume) and write operations on
  reserved slots which drastically improves scalability compared to
  Compare And Swap (CAS) primitives.

  Note that all operations on slots must modify the slots state bits to
  announce both operations completion (in case of a read) and also makes
  determining the order in which two operations occured possible.
]#

template pushImpl[T](queue: LoonyQueue[T] | SCLoonyQueue[T], el: T,
                    forcedCoherance: static bool = false) =
  mixin fetchAddSlot
  mixin getPtr
  mixin advTail

  doAssert not queue.isNil(), "The queue has not been initialised"
  # Begin by tagging pointer el with WRITER bit and increasing the ref
  # count if necessary
  var pel = prepareElement el
  # Ensure all writes in STOREBUFFER are committed. By far the most costly
  # primitive; it will be preferred while proving safety before working towards
  # optimisation by atomic reads/writes of cache lines related to el
  when forcedCoherance:
    atomicThreadFence(ATOMIC_RELEASE)
  while true:
    # Enq proc begins with incr the index of node in TagPtr
    var tag = fetchIncTail(queue)
    if likely(tag.tag < loonySlotCount):
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
        tryReclaim(tag.getPtr, tag.tag + 1)
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

proc push*[T](queue: LoonyQueue[T] | SCLoonyQueue[T], el: T) =
  ## Push an item onto the end of the LoonyQueue.
  ## This operation ensures some level of cache coherency using atomic thread fences.
  ##
  ## Use unsafePush to avoid this cost.
  pushImpl(queue, el, forcedCoherance = true)
proc unsafePush*[T](queue: LoonyQueue[T] | SCLoonyQueue[T], el: T) =
  ## Push an item onto the end of the LoonyQueue.
  ## Unlike push, this operation does not use atomic thread fences. This means you
  ## may get undefined behaviour if the receiving thread has old cached memory
  ## related to this element
  pushImpl(queue, el, forcedCoherance = false)

template isEmptyImpl(head, tail: TagPtr): bool =
  mixin getPtr
  if head.tag >= loonySlotCount or head.tag >= tail.tag:
    (head.getPtr == tail.getPtr)
  else:
    false

proc isEmpty*(queue: LoonyQueue): bool =
  ## This operation should only be used by internal code. The response for this
  ## operation is not precise.
  let (head, tail) = maneAndTail queue
  isEmptyImpl(head, tail)

template popImpl[T](queue: LoonyQueue[T]; forcedCoherance: static bool = false): T =
  mixin fetchIncHead
  mixin fetchAddSlot
  mixin getPtr
  mixin advHead
  var res: T

  doAssert not queue.isNil(), "The queue has not been initialised"
  while true:
    # Before incr the deq index, init check performed to determine if queue is empty.
    # Ensure head is loaded last to keep mem hot
    var (tail, curr) = tailAndMane queue
    if isEmptyImpl(curr, tail):
      # Queue was empty; nil can be caught in cps w/ "while cont.running"
      when T is object:
        res = default(T)
        break
      else:
        break

    var head = queue.fetchIncHead()
    if likely(head.tag < loonySlotCount):
      # FAST PATH OPS
      var prev = head.fetchAddSlot READER
      # Last slot in a node - init reclaim proc; if WRITER bit set then upper bits
      # contain a valid pointer to an enqd el that can be returned (see enqueue)
      if not unlikely((prev and SLOTMASK) == 0):
        if (prev and spec.WRITER) != 0:
          if unlikely((prev and RESUME) != 0):
            tryReclaim(head.getPtr, head.tag + 1)

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

          res = cast[T](prev and SLOTMASK)
          when T is ref:
            GC_unref res # We incref on the push, so we have to make sure to
                            # to decref or we will get memory leaks
          break
    else:
      # SLOW PATH OPS
      case queue.advHead(curr, head, tail)
      of Advanced:
        discard
      of QueueEmpty:
        break
  res

template popImplSC[T](queue: SCLoonyQueue[T]; forcedCoherance: static bool = false): T =
  mixin load
  mixin fetchAddSlot
  mixin getTag
  mixin getPtr
  doAssert not queue.isNil(), "The queue has not been initialised"
  var res: T
  while true:
    var tail = queue.tail.load(Rlx)
    var head = queue.head
    if isEmptyImpl(head, tail):
      when T is object:
        res = default(T)
      break
    elif likely(head.tag < loonySlotCount):
      var prev = head.fetchAddSlot READER
      if not unlikely((prev and SLOTMASK) == 0) and (prev and spec.WRITER) != 0:
        when forcedCoherance:
          atomicThreadFence(ATOMIC_ACQUIRE)
        
        res = cast[T](prev and SLOTMASK)
        when T is ref:
          GC_unref res
        queue.head.tag += 1
        break
    else:
      if head.getTag == loonySlotCount:
        tryReclaim(head.getPtr, 0'u8)
      if tail.getPtr == head.getPtr:
        queue.head.tag += 1
        break
      else:
        var next = head.getPtr.next.load(Rlx)
        queue.head = cast[TagPtr](next)
  res


proc pop*[T](queue: LoonyQueue[T] | SCLoonyQueue[T]): T =
  ## Remove and return to the caller the next item in the LoonyQueue.
  ## This operation ensures some level of cache coherency using atomic thread fences.
  ##
  ## Use unsafePop to avoid this cost.
  when queue is LoonyQueue:
    popImpl(queue, forcedCoherance = true)
  else:
    popImplSC(queue, forcedCoherance = true)
proc unsafePop*[T](queue: LoonyQueue[T] | SCLoonyQueue[T]): T =
  ## Remove and return to the caller the next item in the LoonyQueue.
  ## Unlike pop, this operation does not use atomic thread fences. This means you
  ## may get undefined behaviour if the caller has old cached memory that is
  ## related to the item.
  when queue is LoonyQueue:
    popImpl(queue, forcedCoherance = false)
  else:
    popImplSC(queue, forcedCoherance = false)
#[
  Consumed slots have been written to and then read. If a concurrent
  deque operation outpaces the corresponding enqueue operation then both
  operations have to abandon and try again. Once all slots in the node
  have been consumed or abandoned, the node is considered drained and
  unlinked from the list. Node can be reclaimed and de-allocated.

  Queue manages an enqueue index and a dequeue index. Each are modified
  by fetchAndAdd; gives thread reserves previous index for itself which
  may be used to address a slot in the respective nodes array.

  both node pointers are tagged with their assoc index value ->
  they store both address to respective node as well as the current
  index value in the same memory word.

  Requires a sufficient number of available bits that are not used to
  present the nodes addresses themselves.
]#

      
      

proc initLoonyQueue*(q: LoonyQueue) =
  ## Initialize an existing LoonyQueue.
  var headTag = cast[uint](allocNode())
  var tailTag = headTag
  q.head.store headTag
  q.tail.store tailTag
  q.currTail.store tailTag
  for i in 0..<loonySlotCount:
    var h = load headTag.getPtr.slots[i]
    var t = load tailTag.getPtr.slots[i]
    assert h == 0, "Slot found to not be nil on initialisation"
    assert t == 0, "Slot found to not be nil on initialisation"
  # Allocate the first nodes on initialisation to optimise use.

proc initLoonyQueue*[T](): LoonyQueue[T] {.deprecated: "Use newLoonyQueue instead".} =
  ## Return an initialized LoonyQueue.
  # TODO destroy proc
  new result
  initLoonyQueue result

proc newLoonyQueue*[T](): LoonyQueue[T] =
  ## Return an intialized LoonyQueue.
  new result
  initLoonyQueue result

proc newSCLoonyQueue*[T](): SCLoonyQueue[T] =
  new result
  let nptr = allocNode()
  result.head = cast[TagPtr](nptr)
  result.tail = result.head
  result.currTail = nptr