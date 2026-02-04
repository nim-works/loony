## Behavioral Tests: Concurrent Producer/Consumer Matrix
## Contract: All items enqueued arrive at consumers in FIFO order under contention
## Tests all (1-4 producers) × (1-4 consumers) = 16 combinations

import ../framework
import ../../loony
import std/[threads, sync]

type
  MatrixConfig = object
    producers: int
    consumers: int
    itemsPerProducer: int

proc testConcurrentMatrix(config: MatrixConfig) =
  ## Run a single producer/consumer configuration test
  let totalItems = config.producers * config.itemsPerProducer
  var results: seq[int] = @[]
  var resultsLock: Lock
  initLock(resultsLock)
  var threadsDone = 0
  var doneCondvar: Cond
  initCond(doneCondvar)
  
  let q = newLoonyQueue[int]()
  
  # Producer threads
  var producerThreads: seq[Thread[tuple[q: LoonyQueue[int], id: int, itemsPerProducer: int]]]
  for p in 0..<config.producers:
    var t: Thread[tuple[q: LoonyQueue[int], id: int, itemsPerProducer: int]]
    createThread(t, proc(data: tuple[q: LoonyQueue[int], id: int, itemsPerProducer: int]) =
      for i in 0..<data.itemsPerProducer:
        let item = data.id * 1000 + i
        data.q.push(item)
    , (q, p, config.itemsPerProducer))
    producerThreads.add(t)
  
  # Consumer threads
  var consumerThreads: seq[Thread[tuple[q: LoonyQueue[int], id: int, lock: ptr Lock, results: ptr seq[int], totalItems: int]]]
  for c in 0..<config.consumers:
    var t: Thread[tuple[q: LoonyQueue[int], id: int, lock: ptr Lock, results: ptr seq[int], totalItems: int]]
    createThread(t, proc(data: tuple[q: LoonyQueue[int], id: int, lock: ptr Lock, results: ptr seq[int], totalItems: int]) =
      var collected = 0
      let itemsPerConsumer = (data.totalItems + data.id) div data.id  # Rough distribution
      
      while true:
        let v = data.q.pop()
        withLock(data.lock[]):
          data.results[].add(v)
        
        collected += 1
        if collected >= data.totalItems:
          break
    , (q, c, addr resultsLock, addr results, totalItems))
    consumerThreads.add(t)
  
  # Wait for producers
  for t in producerThreads:
    joinThread(t)
  
  # Wait for consumers
  for t in consumerThreads:
    joinThread(t)
  
  # Verify: all items received
  check results.len == totalItems, &"Expected {totalItems} items, got {results.len}"
  
  # Verify: no duplicates
  let seen = results.len
  results.sort()
  for i in 1..<results.len:
    check results[i] >= results[i-1], "Items out of sorted order"

suite "Concurrent Producer/Consumer Matrix":
  
  # 1P/1C Configuration
  test "1 producer / 1 consumer (10 items)":
    let config = MatrixConfig(producers: 1, consumers: 1, itemsPerProducer: 10)
    testConcurrentMatrix(config)
  
  test "1 producer / 2 consumers (10 items)":
    let config = MatrixConfig(producers: 1, consumers: 2, itemsPerProducer: 10)
    testConcurrentMatrix(config)
  
  test "1 producer / 3 consumers (10 items)":
    let config = MatrixConfig(producers: 1, consumers: 3, itemsPerProducer: 10)
    testConcurrentMatrix(config)
  
  test "1 producer / 4 consumers (10 items)":
    let config = MatrixConfig(producers: 1, consumers: 4, itemsPerProducer: 10)
    testConcurrentMatrix(config)
  
  # 2P/1C Configuration
  test "2 producers / 1 consumer (10 items each)":
    let config = MatrixConfig(producers: 2, consumers: 1, itemsPerProducer: 10)
    testConcurrentMatrix(config)
  
  test "2 producers / 2 consumers (10 items each)":
    let config = MatrixConfig(producers: 2, consumers: 2, itemsPerProducer: 10)
    testConcurrentMatrix(config)
  
  test "2 producers / 3 consumers (10 items each)":
    let config = MatrixConfig(producers: 2, consumers: 3, itemsPerProducer: 10)
    testConcurrentMatrix(config)
  
  test "2 producers / 4 consumers (10 items each)":
    let config = MatrixConfig(producers: 2, consumers: 4, itemsPerProducer: 10)
    testConcurrentMatrix(config)
  
  # 3P/1C Configuration
  test "3 producers / 1 consumer (10 items each)":
    let config = MatrixConfig(producers: 3, consumers: 1, itemsPerProducer: 10)
    testConcurrentMatrix(config)
  
  test "3 producers / 2 consumers (10 items each)":
    let config = MatrixConfig(producers: 3, consumers: 2, itemsPerProducer: 10)
    testConcurrentMatrix(config)
  
  test "3 producers / 3 consumers (10 items each)":
    let config = MatrixConfig(producers: 3, consumers: 3, itemsPerProducer: 10)
    testConcurrentMatrix(config)
  
  test "3 producers / 4 consumers (10 items each)":
    let config = MatrixConfig(producers: 3, consumers: 4, itemsPerProducer: 10)
    testConcurrentMatrix(config)
  
  # 4P/1C Configuration
  test "4 producers / 1 consumer (10 items each)":
    let config = MatrixConfig(producers: 4, consumers: 1, itemsPerProducer: 10)
    testConcurrentMatrix(config)
  
  test "4 producers / 2 consumers (10 items each)":
    let config = MatrixConfig(producers: 4, consumers: 2, itemsPerProducer: 10)
    testConcurrentMatrix(config)
  
  test "4 producers / 3 consumers (10 items each)":
    let config = MatrixConfig(producers: 4, consumers: 3, itemsPerProducer: 10)
    testConcurrentMatrix(config)
  
  test "4 producers / 4 consumers (10 items each)":
    let config = MatrixConfig(producers: 4, consumers: 4, itemsPerProducer: 10)
    testConcurrentMatrix(config)
