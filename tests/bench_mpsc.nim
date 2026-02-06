## Benchmark: Multiple Producers / Single Consumer (MPSC)
## Tests contention from multiple producers

import std/[times, atomics, strformat, locks]
import ../loony
import ./benchmark_framework

type
  IntBox = ref object
    value: int

proc benchmarkMPSC*(producerCount: int, itemsPerProducer: int, sampleLatency: bool = false): BenchmarkResult =
  let q = newLoonyQueue[IntBox]()
  let totalItems = producerCount * itemsPerProducer
  var timings: seq[float64] = @[]
  var itemsReceived = Atomic[int]()
  itemsReceived.store(0)
  var producersDone = Atomic[int]()
  producersDone.store(0)
  var timingsLock: Lock
  initLock(timingsLock)
  
  let startTotal = now()
  
  # Create producer threads
  var producerThreads: seq[Thread[tuple[q: LoonyQueue[IntBox], producerId: int, itemsPerProducer: int, sampleLatency: bool, producersDone: ptr Atomic[int], timings: ptr seq[float64], lock: ptr Lock]]]
  
  for pid in 0..<producerCount:
    var producerThread: Thread[tuple[q: LoonyQueue[IntBox], producerId: int, itemsPerProducer: int, sampleLatency: bool, producersDone: ptr Atomic[int], timings: ptr seq[float64], lock: ptr Lock]]
    createThread(producerThread, proc(data: tuple[q: LoonyQueue[IntBox], producerId: int, itemsPerProducer: int, sampleLatency: bool, producersDone: ptr Atomic[int], timings: ptr seq[float64], lock: ptr Lock]) =
      for i in 0..<data.itemsPerProducer:
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
      
      # Increment the producers done counter
      discard data.producersDone[].fetchAdd(1)
    , (q, pid, itemsPerProducer, sampleLatency, addr producersDone, addr timings, addr timingsLock))
    
    producerThreads.add(producerThread)
  
  # Consumer thread
  var consumerThread: Thread[tuple[q: LoonyQueue[IntBox], totalItems: int, sampleLatency: bool, producersDone: ptr Atomic[int], producerCount: int, received: ptr Atomic[int], timings: ptr seq[float64], lock: ptr Lock]]
  createThread(consumerThread, proc(data: tuple[q: LoonyQueue[IntBox], totalItems: int, sampleLatency: bool, producersDone: ptr Atomic[int], producerCount: int, received: ptr Atomic[int], timings: ptr seq[float64], lock: ptr Lock]) =
    var count = 0
    var attempts = 0
    while count < data.totalItems and attempts < 10000000:
      let box = data.q.pop()
      if box != nil:
        count += 1
        attempts = 0
        if data.sampleLatency and count > 1:  # Skip first item
          let opStart = now()
          discard box.value  # Use value to prevent optimization
          let opDuration = (now() - opStart).inNanoseconds.float64
          withLock(data.lock[]):
            data.timings[].add(opDuration)
      else:
        if data.producersDone[].load() == data.producerCount:
          break
        attempts += 1
    
    data.received[].store(count)
  , (q, totalItems, sampleLatency, addr producersDone, producerCount, addr itemsReceived, addr timings, addr timingsLock))
  
  # Wait for all producer threads
  for thread in producerThreads.mitems():
    joinThread(thread)
  
  # Wait for consumer thread
  joinThread(consumerThread)
  
  let durationMs = (now() - startTotal).inMilliseconds.float64
  let itemsReceivedCount = itemsReceived.load()
  let throughput = (float64(itemsReceivedCount) / durationMs) * 1000.0
  
  result.name = &"MPSC {producerCount} Producers"
  result.producers = producerCount
  result.consumers = 1
  result.itemsPerThread = itemsPerProducer
  result.totalItems = itemsReceivedCount
  result.durationMs = durationMs
  result.throughput = throughput
  
  if sampleLatency and timings.len > 0:
    result.latencyStats = computeStats(timings)

proc runMPSCBenchmarks*() =
  echo "\n" & repeatStr("=", 80)
  echo "MPSC (Multiple Producers / Single Consumer) Benchmarks"
  echo repeatStr("=", 80)
  
  var results: seq[BenchmarkResult] = @[]
  
  # Warmup
  discard benchmarkMPSC(2, 1000, sampleLatency=false)
  
  # 2 Producers with 10k items each
  echo "\nRunning MPSC 2P 10k items each..."
  let r2p10k = benchmarkMPSC(2, 10_000, sampleLatency=true)
  reportBenchmarkResult(r2p10k)
  results.add(r2p10k)
  
  # 4 Producers with 10k items each
  echo "\nRunning MPSC 4P 10k items each..."
  let r4p10k = benchmarkMPSC(4, 10_000, sampleLatency=true)
  reportBenchmarkResult(r4p10k)
  results.add(r4p10k)
  
  # 8 Producers with 10k items each
  echo "\nRunning MPSC 8P 10k items each..."
  let r8p10k = benchmarkMPSC(8, 10_000, sampleLatency=false)
  reportBenchmarkResult(r8p10k)
  results.add(r8p10k)
  
  reportBenchmarkSummary(results)

when isMainModule:
  runMPSCBenchmarks()
