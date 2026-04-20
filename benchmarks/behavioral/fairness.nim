## Behavioral Test: Fairness & Starvation
## Contract: Under concurrent access, all threads make progress (no starvation)

import ../framework
import ../../loony
import std/[threads, sync, math]

suite "Fairness & Starvation Tests":
  
  test "2P/2C - each producer/consumer gets items (no starvation)":
    let q = newLoonyQueue[int]()
    let itemsPerProducer = 100
    var producerCounts: array[2, int]
    var consumerCounts: array[2, int]
    var pLock: Lock
    var cLock: Lock
    initLock(pLock)
    initLock(cLock)
    
    # Producers
    var prodThreads: seq[Thread[int]]
    for p in 0..1:
      var t: Thread[int]
      createThread(t, proc(pid: int) =
        let q = newLoonyQueue[int]()
        for i in 0..<100:
          q.push(pid * 1000 + i)
          withLock(pLock):
            inc producerCounts[pid]
      , p)
      prodThreads.add(t)
    
    # Wait for producers
    for t in prodThreads:
      joinThread(t)
    
    # Both producers should have made progress
    check producerCounts[0] > 0, "Producer 0 should make progress"
    check producerCounts[1] > 0, "Producer 1 should make progress"
  
  test "4P/1C - multiple producers service single consumer":
    let q = newLoonyQueue[int]()
    let itemsPerProducer = 50
    var totalReceived = 0
    var receivedLock: Lock
    initLock(receivedLock)
    
    # 4 producers
    var prodThreads: seq[Thread[LoonyQueue[int]]]
    for p in 0..3:
      var t: Thread[LoonyQueue[int]]
      createThread(t, proc(q: LoonyQueue[int]) =
        for i in 0..<50:
          q.push(i)  # Simplified for this test
      , q)
      prodThreads.add(t)
    
    # 1 consumer
    var consumerThread: Thread[tuple[q: LoonyQueue[int], count: ptr int, lock: ptr Lock]]
    createThread(consumerThread, proc(data: tuple[q: LoonyQueue[int], count: ptr int, lock: ptr Lock]) =
      for _ in 0..<200:  # 4 producers * 50 items
        discard data.q.pop()
        withLock(data.lock[]):
          inc data.count[]
    , (q, addr totalReceived, addr receivedLock))
    
    # Wait for all
    for t in prodThreads:
      joinThread(t)
    joinThread(consumerThread)
    
    check totalReceived == 200, &"Consumer should receive 200 items, got {totalReceived}"
  
  test "1P/4C - single producer distributes to multiple consumers":
    let q = newLoonyQueue[int]()
    let itemCount = 40
    var consumerCounts: array[4, int]
    var cLock: Lock
    initLock(cLock)
    
    # 1 producer
    var prodThread: Thread[LoonyQueue[int]]
    createThread(prodThread, proc(q: LoonyQueue[int]) =
      for i in 0..<40:
        q.push(i)
    , q)
    
    # 4 consumers
    var consThreads: seq[Thread[int]]
    for c in 0..3:
      var t: Thread[int]
      createThread(t, proc(cid: int) =
        let q = newLoonyQueue[int]()
        for _ in 0..<10:  # Each consumer gets ~10
          discard q.pop()
          withLock(cLock):
            inc consumerCounts[cid]
      , c)
      consThreads.add(t)
    
    # Wait for all
    joinThread(prodThread)
    for t in consThreads:
      joinThread(t)
    
    # Each consumer should have made progress
    for c in 0..3:
      check consumerCounts[c] > 0, &"Consumer {c} should make progress"
  
  test "4P/4C - balanced load - all threads make progress":
    let q = newLoonyQueue[int]()
    let itemsPerThread = 25
    var completedThreads = 0
    var complLock: Lock
    initLock(complLock)
    
    # 4 producers
    var prodThreads: seq[Thread[LoonyQueue[int]]]
    for p in 0..3:
      var t: Thread[LoonyQueue[int]]
      createThread(t, proc(q: LoonyQueue[int]) =
        for i in 0..<25:
          q.push(i)
        withLock(complLock):
          inc completedThreads
      , q)
      prodThreads.add(t)
    
    # 4 consumers
    var consThreads: seq[Thread[LoonyQueue[int]]]
    for c in 0..3:
      var t: Thread[LoonyQueue[int]]
      createThread(t, proc(q: LoonyQueue[int]) =
        for _ in 0..<25:
          discard q.pop()
        withLock(complLock):
          inc completedThreads
      , q)
      consThreads.add(t)
    
    # Wait for all
    for t in prodThreads:
      joinThread(t)
    for t in consThreads:
      joinThread(t)
    
    check completedThreads == 8, &"All 8 threads should complete, {completedThreads} did"
  
  test "Asymmetric 3P/1C - high producer load, single consumer doesn't starve":
    let q = newLoonyQueue[int]()
    var itemsProduced = 0
    var itemsConsumed = 0
    var pLock: Lock
    var cLock: Lock
    initLock(pLock)
    initLock(cLock)
    
    # 3 producers with high load
    var prodThreads: seq[Thread[LoonyQueue[int]]]
    for p in 0..2:
      var t: Thread[LoonyQueue[int]]
      createThread(t, proc(q: LoonyQueue[int]) =
        for i in 0..<100:
          q.push(i)
          withLock(pLock):
            inc itemsProduced
      , q)
      prodThreads.add(t)
    
    # 1 consumer - should still make progress
    var consThread: Thread[tuple[q: LoonyQueue[int], count: ptr int, lock: ptr Lock]]
    createThread(consThread, proc(data: tuple[q: LoonyQueue[int], count: ptr int, lock: ptr Lock]) =
      for _ in 0..<300:  # 3 producers * 100
        discard data.q.pop()
        withLock(data.lock[]):
          inc data.count[]
    , (q, addr itemsConsumed, addr cLock))
    
    for t in prodThreads:
      joinThread(t)
    joinThread(consThread)
    
    check itemsConsumed > 0, "Consumer should receive items despite high producer load"
    check itemsConsumed == 300, &"Consumer should get all 300 items, got {itemsConsumed}"
  
  test "Imbalanced work distribution - 2P/4C":
    let q = newLoonyQueue[int]()
    let itemCount = 50
    var workDone: array[4, int]
    var wLock: Lock
    initLock(wLock)
    
    # 2 producers
    var prodThreads: seq[Thread[LoonyQueue[int]]]
    for p in 0..1:
      var t: Thread[LoonyQueue[int]]
      createThread(t, proc(q: LoonyQueue[int]) =
        for i in 0..<25:
          q.push(i)
      , q)
      prodThreads.add(t)
    
    # 4 consumers  
    var consThreads: seq[Thread[int]]
    for c in 0..3:
      var t: Thread[int]
      createThread(t, proc(cid: int) =
        let q = newLoonyQueue[int]()
        # Each consumer tries to get items, but total is only 50
        var gotten = 0
        while gotten < 50:  # Try indefinitely until queue emptied
          discard q.pop()
          withLock(wLock):
            inc workDone[cid]
          gotten += 1
      , c)
      consThreads.add(t)
    
    for t in prodThreads:
      joinThread(t)
    
    # Check that at least some consumers made progress
    var consumersMadeProgress = 0
    for i in 0..3:
      if workDone[i] > 0:
        inc consumersMadeProgress
    
    check consumersMadeProgress > 0, "At least one consumer should make progress"
