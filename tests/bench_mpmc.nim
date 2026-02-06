## Benchmark: Multiple Producers / Multiple Consumers (MPMC)
## Tests high contention scenarios

import std/[times, atomics, strformat, locks]
import ../loony
import ./benchmark_framework

type
  IntBox = ref object
    value: int

proc benchmarkMPMC*(producerCount: int, consumerCount: int, itemsPerThread: int, sampleLatency: bool = false): BenchmarkResult =
  let q = newLoonyQueue[IntBox]()
  var timings: seq[float64] = @[]
  var totalItemsReceived = 0
  var totalItemsLock: Lock
  initLock(totalItemsLock)
  var producersCompleted = Atomic[int]()
  producersCompleted.store(0)
  var timingsLock: Lock
  initLock(timingsLock)
  
  let startTotal = now()
  
  # Create producer threads
  var producerThreads: seq[Thread[tuple[q: LoonyQueue[IntBox], producerId: int, itemsPerThread: int, sampleLatency: bool, timings: ptr seq[float64], lock: ptr Lock]]] = @[]
  
  for p in 0..<producerCount:
    var t: Thread[tuple[q: LoonyQueue[IntBox], producerId: int, itemsPerThread: int, sampleLatency: bool, timings: ptr seq[float64], lock: ptr Lock]]
    createThread(t, proc(data: tuple[q: LoonyQueue[IntBox], producerId: int, itemsPerThread: int, sampleLatency: bool, timings: ptr seq[float64], lock: ptr Lock]) =
      for i in 0..<data.itemsPerThread:
        let box = new IntBox
        box.value = data.producerId * 1000000 + i
        
        if data.sampleLatency:
          let opStart = now()
          data.q.push(box)
          let opDuration = (now() - opStart).inNanoseconds.float64
          withLock(data.lock[]):
            data.timings[].add(opDuration)
        else:
          data.q.push(box)
    , (q, p, itemsPerThread, sampleLatency, addr timings, addr timingsLock))
    
    producerThreads.add(t)
  
  # Create consumer threads
  var consumerThreads: seq[Thread[tuple[q: LoonyQueue[IntBox], consumerCount: int, itemsPerThread: int, sampleLatency: bool, producersCompleted: ptr Atomic[int], received: ptr int, receivedLock: ptr Lock, timings: ptr seq[float64], timingsLock: ptr Lock]]] = @[]
  
  for c in 0..<consumerCount:
    var t: Thread[tuple[q: LoonyQueue[IntBox], consumerCount: int, itemsPerThread: int, sampleLatency: bool, producersCompleted: ptr Atomic[int], received: ptr int, receivedLock: ptr Lock, timings: ptr seq[float64], timingsLock: ptr Lock]]
    createThread(t, proc(data: tuple[q: LoonyQueue[IntBox], consumerCount: int, itemsPerThread: int, sampleLatency: bool, producersCompleted: ptr Atomic[int], received: ptr int, receivedLock: ptr Lock, timings: ptr seq[float64], timingsLock: ptr Lock]) =
      var count = 0
      var attempts = 0
      # Each consumer should pop roughly itemsPerThread items
      let targetItems = data.itemsPerThread
      
      while count < targetItems and attempts < 10000000:
        let box = data.q.pop()
        if box != nil:
          count += 1
          attempts = 0
          if data.sampleLatency and count > 1:  # Skip first item
            let opStart = now()
            discard box.value  # Use value to prevent optimization
            let opDuration = (now() - opStart).inNanoseconds.float64
            withLock(data.timingsLock[]):
              data.timings[].add(opDuration)
        else:
          if data.producersCompleted[].load() == data.consumerCount:
            break
          attempts += 1
      
      # Add count for this consumer to total (with lock)
      withLock(data.receivedLock[]):
        data.received[] += count
    , (q, consumerCount, itemsPerThread, sampleLatency, addr producersCompleted, addr totalItemsReceived, addr totalItemsLock, addr timings, addr timingsLock))
    
    consumerThreads.add(t)
  
  # Wait for all producer threads to complete
  for t in producerThreads:
    joinThread(t)
  
  # Signal that all producers are done
  producersCompleted.store(producerCount)
  
  # Wait for all consumer threads to complete
  for t in consumerThreads:
    joinThread(t)
  
  let durationMs = (now() - startTotal).inMilliseconds.float64
  let itemsReceivedCount = totalItemsReceived
  let throughput = (float64(itemsReceivedCount) / durationMs) * 1000.0
  
  result.name = &"MPMC {producerCount}P/{consumerCount}C"
  result.producers = producerCount
  result.consumers = consumerCount
  result.itemsPerThread = itemsPerThread
  result.totalItems = itemsReceivedCount
  result.durationMs = durationMs
  result.throughput = throughput
  
  if sampleLatency and timings.len > 0:
    result.latencyStats = computeStats(timings)

proc runMPMCBenchmarks*() =
  echo "\n" & repeatStr("=", 80)
  echo "MPMC (Multiple Producers / Multiple Consumers) Benchmarks"
  echo repeatStr("=", 80)
  
  var results: seq[BenchmarkResult] = @[]
  
  # Warmup
  discard benchmarkMPMC(2, 2, 1000, sampleLatency=false)
  
  # 2P/2C with 10k items per producer
  echo "\nRunning MPMC 2P/2C 10k items each..."
  let r2p2c = benchmarkMPMC(2, 2, 10_000, sampleLatency=true)
  reportBenchmarkResult(r2p2c)
  results.add(r2p2c)
  
  # 4P/4C with 10k items per producer
  echo "\nRunning MPMC 4P/4C 10k items each..."
  let r4p4c = benchmarkMPMC(4, 4, 10_000, sampleLatency=true)
  reportBenchmarkResult(r4p4c)
  results.add(r4p4c)
  
  # 8P/8C with 5k items per producer (to keep total reasonable)
  echo "\nRunning MPMC 8P/8C 5k items each..."
  let r8p8c = benchmarkMPMC(8, 8, 5_000, sampleLatency=false)
  reportBenchmarkResult(r8p8c)
  results.add(r8p8c)
  
  # Asymmetric: 4P/2C
  echo "\nRunning MPMC 4P/2C 10k items each..."
  let r4p2c = benchmarkMPMC(4, 2, 10_000, sampleLatency=false)
  reportBenchmarkResult(r4p2c)
  results.add(r4p2c)
  
  # Asymmetric: 2P/4C
  echo "\nRunning MPMC 2P/4C 10k items each..."
  let r2p4c = benchmarkMPMC(2, 4, 10_000, sampleLatency=false)
  reportBenchmarkResult(r2p4c)
  results.add(r2p4c)
  
  reportBenchmarkSummary(results)

when isMainModule:
  runMPMCBenchmarks()
