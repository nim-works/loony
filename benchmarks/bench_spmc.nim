## Benchmark: Single Producer / Multiple Consumers (SPMC)
## Tests contention from multiple consumers

import std/[times, atomics, os, strformat, locks, cpuinfo]
import ../loony
import ./benchmark_framework

type
  IntBox = ref object
    value: int

proc benchmarkSPMC*(consumerCount: int, itemsPerConsumer: int, sampleLatency: bool = false): BenchmarkResult =
  let q = newLoonyQueue[IntBox]()
  let totalItems = consumerCount * itemsPerConsumer
  var timings: seq[float64] = @[]
  var totalItemsReceived = Atomic[int]()
  totalItemsReceived.store(0)
  var producerDone = Atomic[bool]()
  producerDone.store(false)
  var timingsLock: Lock
  initLock(timingsLock)
  
  let startTotal = now()
  
  # Producer thread
  var producerThread: Thread[tuple[q: LoonyQueue[IntBox], totalItems: int, sampleLatency: bool, producerDone: ptr Atomic[bool], timings: ptr seq[float64], lock: ptr Lock]]
  createThread(producerThread, proc(data: tuple[q: LoonyQueue[IntBox], totalItems: int, sampleLatency: bool, producerDone: ptr Atomic[bool], timings: ptr seq[float64], lock: ptr Lock]) =
    for i in 0..<data.totalItems:
      let box = new IntBox
      box.value = i
      
      if data.sampleLatency:
        let opStart = now()
        data.q.push(box)
        let opDuration = (now() - opStart).inNanoseconds.float64
        withLock(data.lock[]):
          data.timings[].add(opDuration)
      else:
        data.q.push(box)
    
    data.producerDone[].store(true)
  , (q, totalItems, sampleLatency, addr producerDone, addr timings, addr timingsLock))
  
  # Consumer threads
  var consumerThreads: seq[Thread[tuple[q: LoonyQueue[IntBox], itemsPerConsumer: int, sampleLatency: bool, producerDone: ptr Atomic[bool], totalReceived: ptr Atomic[int], timings: ptr seq[float64], lock: ptr Lock]]] = @[]
  
  for c in 0..<consumerCount:
    var consumerThread: Thread[tuple[q: LoonyQueue[IntBox], itemsPerConsumer: int, sampleLatency: bool, producerDone: ptr Atomic[bool], totalReceived: ptr Atomic[int], timings: ptr seq[float64], lock: ptr Lock]]
    createThread(consumerThread, proc(data: tuple[q: LoonyQueue[IntBox], itemsPerConsumer: int, sampleLatency: bool, producerDone: ptr Atomic[bool], totalReceived: ptr Atomic[int], timings: ptr seq[float64], lock: ptr Lock]) =
      var count = 0
      var attempts = 0
      while count < data.itemsPerConsumer and attempts < 10000000:
        let box = data.q.pop()
        if box != nil:
          count += 1
          attempts = 0
          let current = data.totalReceived[].load()
          data.totalReceived[].store(current + 1)
          if data.sampleLatency and count > 1:  # Skip first item
            let opStart = now()
            discard box.value  # Use value to prevent optimization
            let opDuration = (now() - opStart).inNanoseconds.float64
            withLock(data.lock[]):
              data.timings[].add(opDuration)
        else:
          if data.producerDone[].load():
            break
          attempts += 1
    , (q, itemsPerConsumer, sampleLatency, addr producerDone, addr totalItemsReceived, addr timings, addr timingsLock))
    consumerThreads.add(consumerThread)
  
  # Wait for producer and all consumers
  joinThread(producerThread)
  for consumerThread in consumerThreads:
    joinThread(consumerThread)
  
  let durationMs = (now() - startTotal).inMilliseconds.float64
  let itemsReceivedCount = totalItemsReceived.load()
  let throughput = (float64(itemsReceivedCount) / durationMs) * 1000.0
  
  result.name = &"SPMC {consumerCount} Consumers"
  result.producers = 1
  result.consumers = consumerCount
  result.itemsPerThread = itemsPerConsumer
  result.totalItems = itemsReceivedCount
  result.durationMs = durationMs
  result.throughput = throughput
  
  if sampleLatency and timings.len > 0:
    result.latencyStats = computeStats(timings)

proc runSPMCBenchmarks*() =
  echo "\n" & repeatStr("=", 80)
  echo "SPMC (Single Producer / Multiple Consumers) Benchmarks"
  echo repeatStr("=", 80)
  
  var results: seq[BenchmarkResult] = @[]
  
  # Warmup
  discard benchmarkSPMC(2, 1000, sampleLatency=false)
  
  # 2 Consumers with 10k items each
  echo "\nRunning SPMC 2C 10k items each..."
  let r2c10k = benchmarkSPMC(2, 10_000, sampleLatency=true)
  reportBenchmarkResult(r2c10k)
  results.add(r2c10k)
  
  # 4 Consumers with 10k items each
  echo "\nRunning SPMC 4C 10k items each..."
  let r4c10k = benchmarkSPMC(4, 10_000, sampleLatency=true)
  reportBenchmarkResult(r4c10k)
  results.add(r4c10k)
  
  # 8 Consumers with 10k items each
  echo "\nRunning SPMC 8C 10k items each..."
  let r8c10k = benchmarkSPMC(8, 10_000, sampleLatency=false)
  reportBenchmarkResult(r8c10k)
  results.add(r8c10k)
  
  reportBenchmarkSummary(results)

when isMainModule:
  runSPMCBenchmarks()
