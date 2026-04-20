## Behavioral Test: SPSC Stress Test
## Single Producer / Single Consumer with high item count
## Contract: All items delivered in FIFO order, no losses, no corruption

import ../framework
import ../../loony
import std/[threads]

suite "SPSC Stress Test":
  
  test "Single Producer / Single Consumer (10,000 items)":
    let q = newLoonyQueue[int]()
    let itemCount = 10_000
    var consumerResults: seq[int] = @[]
    
    # Producer thread
    var producerThread: Thread[LoonyQueue[int]]
    createThread(producerThread, proc(q: LoonyQueue[int]) =
      for i in 0..<10_000:
        q.push(i)
    , q)
    
    # Consumer thread
    var consumerThread: Thread[tuple[q: LoonyQueue[int], results: ptr seq[int]]]
    createThread(consumerThread, proc(data: tuple[q: LoonyQueue[int], results: ptr seq[int]]) =
      for _ in 0..<10_000:
        let v = data.q.pop()
        data.results[].add(v)
    , (q, addr consumerResults))
    
    # Wait for both threads
    joinThread(producerThread)
    joinThread(consumerThread)
    
    # Verify all items received
    check consumerResults.len == itemCount, &"Expected {itemCount} items, got {consumerResults.len}"
    
    # Verify FIFO order
    for i in 0..<itemCount:
      checkEqual(consumerResults[i], i, &"FIFO order violation at position {i}")
  
  test "SPSC - String type (10,000 items)":
    let q = newLoonyQueue[string]()
    let itemCount = 10_000
    var results: seq[string] = @[]
    
    var producerThread: Thread[LoonyQueue[string]]
    createThread(producerThread, proc(q: LoonyQueue[string]) =
      for i in 0..<10_000:
        q.push("item_" & $i)
    , q)
    
    var consumerThread: Thread[tuple[q: LoonyQueue[string], results: ptr seq[string]]]
    createThread(consumerThread, proc(data: tuple[q: LoonyQueue[string], results: ptr seq[string]]) =
      for _ in 0..<10_000:
        let v = data.q.pop()
        data.results[].add(v)
    , (q, addr results))
    
    joinThread(producerThread)
    joinThread(consumerThread)
    
    check results.len == itemCount, "Should receive all items"
    for i in 0..<itemCount:
      checkEqual(results[i], "item_" & $i, &"String FIFO violated at {i}")
  
  test "SPSC - Alternating pattern (5,000 push-pop pairs)":
    let q = newLoonyQueue[int]()
    let pairCount = 5_000
    var allCorrect = true
    
    var producerThread: Thread[LoonyQueue[int]]
    createThread(producerThread, proc(q: LoonyQueue[int]) =
      for i in 0..<5_000:
        q.push(i * 2)
    , q)
    
    var consumerThread: Thread[tuple[q: LoonyQueue[int], correct: ptr bool]]
    createThread(consumerThread, proc(data: tuple[q: LoonyQueue[int], correct: ptr bool]) =
      for i in 0..<5_000:
        let v = data.q.pop()
        if v != i * 2:
          data.correct[] = false
    , (q, addr allCorrect))
    
    joinThread(producerThread)
    joinThread(consumerThread)
    
    check allCorrect, "All FIFO checks should pass"
  
  test "SPSC - Large objects (1,000 items of 512 bytes each)":
    type LargeData = array[128, uint32]
    let q = newLoonyQueue[LargeData]()
    let itemCount = 1_000
    var resultsValid = true
    
    var producerThread: Thread[LoonyQueue[LargeData]]
    createThread(producerThread, proc(q: LoonyQueue[LargeData]) =
      for i in 0..<1_000:
        var data: LargeData
        for j in 0..<128:
          data[j] = uint32(i * 128 + j)
        q.push(data)
    , q)
    
    var consumerThread: Thread[tuple[q: LoonyQueue[LargeData], valid: ptr bool]]
    createThread(consumerThread, proc(data: tuple[q: LoonyQueue[LargeData], valid: ptr bool]) =
      for i in 0..<1_000:
        let v = data.q.pop()
        for j in 0..<128:
          if v[j] != uint32(i * 128 + j):
            data.valid[] = false
    , (q, addr resultsValid))
    
    joinThread(producerThread)
    joinThread(consumerThread)
    
    check resultsValid, "All large object items should be uncorrupted"
  
  test "SPSC - Reference types (5,000 items)":
    type Item = ref object
      id: int
      value: string
    
    let q = newLoonyQueue[Item]()
    let itemCount = 5_000
    var resultsValid = true
    
    var producerThread: Thread[LoonyQueue[Item]]
    createThread(producerThread, proc(q: LoonyQueue[Item]) =
      for i in 0..<5_000:
        let item = new Item
        item.id = i
        item.value = "item_" & $i
        q.push(item)
    , q)
    
    var consumerThread: Thread[tuple[q: LoonyQueue[Item], valid: ptr bool]]
    createThread(consumerThread, proc(data: tuple[q: LoonyQueue[Item], valid: ptr bool]) =
      for i in 0..<5_000:
        let v = data.q.pop()
        if v.id != i or v.value != "item_" & $i:
          data.valid[] = false
    , (q, addr resultsValid))
    
    joinThread(producerThread)
    joinThread(consumerThread)
    
    check resultsValid, "All reference items should preserve identity"
  
  test "SPSC - Mixed safe and unsafe operations":
    let q = newLoonyQueue[int]()
    let itemCount = 10_000
    var consumerResults: seq[int] = @[]
    
    var producerThread: Thread[LoonyQueue[int]]
    createThread(producerThread, proc(q: LoonyQueue[int]) =
      for i in 0..<10_000:
        if i % 2 == 0:
          q.push(i)
        else:
          q.unsafePush(i)
    , q)
    
    var consumerThread: Thread[tuple[q: LoonyQueue[int], results: ptr seq[int]]]
    createThread(consumerThread, proc(data: tuple[q: LoonyQueue[int], results: ptr seq[int]]) =
      for _ in 0..<10_000:
        if _ % 2 == 0:
          let v = data.q.pop()
          data.results[].add(v)
        else:
          let v = data.q.unsafePop()
          data.results[].add(v)
    , (q, addr consumerResults))
    
    joinThread(producerThread)
    joinThread(consumerThread)
    
    check consumerResults.len == itemCount, "Should receive all items"
    for i in 0..<itemCount:
      checkEqual(consumerResults[i], i, &"Mixed safe/unsafe violated at {i}")
  
  test "SPSC with Ward (10,000 items)":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {})
    let itemCount = 10_000
    var results: seq[int] = @[]
    
    var producerThread: Thread[Ward[int, static set[WardFlag]]]
    createThread(producerThread, proc(w: Ward[int, static set[WardFlag]]) =
      for i in 0..<10_000:
        discard w.push(i)
    , w)
    
    var consumerThread: Thread[tuple[w: Ward[int, static set[WardFlag]], results: ptr seq[int]]]
    createThread(consumerThread, proc(data: tuple[w: Ward[int, static set[WardFlag]], results: ptr seq[int]]) =
      for _ in 0..<10_000:
        let v = data.w.pop()
        data.results[].add(v)
    , (w, addr results))
    
    joinThread(producerThread)
    joinThread(consumerThread)
    
    check results.len == itemCount, "Ward should deliver all items"
    for i in 0..<itemCount:
      checkEqual(results[i], i, &"Ward FIFO violated at {i}")
  
  test "SPSC - Bursting pattern (batches of 100, 100 times)":
    let q = newLoonyQueue[int]()
    let batchSize = 100
    let batchCount = 100
    var results: seq[int] = @[]
    
    var producerThread: Thread[LoonyQueue[int]]
    createThread(producerThread, proc(q: LoonyQueue[int]) =
      for batch in 0..<100:
        for item in 0..<100:
          q.push(batch * 100 + item)
    , q)
    
    var consumerThread: Thread[tuple[q: LoonyQueue[int], results: ptr seq[int]]]
    createThread(consumerThread, proc(data: tuple[q: LoonyQueue[int], results: ptr seq[int]]) =
      for _ in 0..<10_000:
        let v = data.q.pop()
        data.results[].add(v)
    , (q, addr results))
    
    joinThread(producerThread)
    joinThread(consumerThread)
    
    check results.len == 10_000, "Should get all items"
    for i in 0..<10_000:
      checkEqual(results[i], i, &"Batching FIFO violated at {i}")
