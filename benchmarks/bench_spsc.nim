## Benchmark: Single Producer / Single Consumer (SPSC)
## Baseline performance without contention

import std/[times, atomics, os, strformat, locks, cpuinfo]
import ../loony
import ./benchmark_framework

type
  IntBox = ref object
    value: int

proc benchmarkSPSC*(itemCount: int, sampleLatency: bool = false): BenchmarkResult =
  let q = newLoonyQueue[IntBox]()
  var timings: seq[float64] = @[]
  var itemsReceived = Atomic[int]()
  itemsReceived.store(0)
  var producerDone = Atomic[bool]()
  producerDone.store(false)
  var timingsLock: Lock
  initLock(timingsLock)
  
  let startTotal = now()
  
  # Producer thread
  var producerThread: Thread[tuple[q: LoonyQueue[IntBox], itemCount: int, sampleLatency: bool, producerDone: ptr Atomic[bool], timings: ptr seq[float64], lock: ptr Lock]]
  createThread(producerThread, proc(data: tuple[q: LoonyQueue[IntBox], itemCount: int, sampleLatency: bool, producerDone: ptr Atomic[bool], timings: ptr seq[float64], lock: ptr Lock]) =
    for i in 0..<data.itemCount:
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
  , (q, itemCount, sampleLatency, addr producerDone, addr timings, addr timingsLock))
  
  # Consumer thread
  var consumerThread: Thread[tuple[q: LoonyQueue[IntBox], itemCount: int, sampleLatency: bool, producerDone: ptr Atomic[bool], received: ptr Atomic[int], timings: ptr seq[float64], lock: ptr Lock]]
  createThread(consumerThread, proc(data: tuple[q: LoonyQueue[IntBox], itemCount: int, sampleLatency: bool, producerDone: ptr Atomic[bool], received: ptr Atomic[int], timings: ptr seq[float64], lock: ptr Lock]) =
    var count = 0
    var attempts = 0
    while count < data.itemCount and attempts < 10000000:
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
        if data.producerDone[].load():
          break
        attempts += 1
    
    data.received[].store(count)
  , (q, itemCount, sampleLatency, addr producerDone, addr itemsReceived, addr timings, addr timingsLock))
  
  # Wait for threads
  joinThread(producerThread)
  joinThread(consumerThread)
  
  let durationMs = (now() - startTotal).inMilliseconds.float64
  let itemsReceivedCount = itemsReceived.load()
  let throughput = (float64(itemsReceivedCount) / durationMs) * 1000.0
  
  result.name = "SPSC Baseline"
  result.producers = 1
  result.consumers = 1
  result.itemsPerThread = itemCount
  result.totalItems = itemsReceivedCount
  result.durationMs = durationMs
  result.throughput = throughput
  
  if sampleLatency and timings.len > 0:
    result.latencyStats = computeStats(timings)

proc runSPSCBenchmarks*() =
  echo "\n" & repeatStr("=", 80)
  echo "SPSC (Single Producer / Single Consumer) Benchmarks"
  echo repeatStr("=", 80)
  
  var results: seq[BenchmarkResult] = @[]
  
  # Warmup
  discard benchmarkSPSC(1000, sampleLatency=false)
  
  # SPSC with 10k items
  echo "\nRunning SPSC 10k items..."
  let r10k = benchmarkSPSC(10_000, sampleLatency=true)
  reportBenchmarkResult(r10k)
  results.add(r10k)
  
  # SPSC with 100k items
  echo "\nRunning SPSC 100k items..."
  let r100k = benchmarkSPSC(100_000, sampleLatency=true)
  reportBenchmarkResult(r100k)
  results.add(r100k)
  
  # SPSC with 1M items
  echo "\nRunning SPSC 1M items..."
  let r1m = benchmarkSPSC(1_000_000, sampleLatency=false)
  reportBenchmarkResult(r1m)
  results.add(r1m)
  
  reportBenchmarkSummary(results)

when isMainModule:
  runSPSCBenchmarks()
