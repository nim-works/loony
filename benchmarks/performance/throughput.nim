## Performance Tests: Throughput Benchmarks
## Measures: p50, p99, p999 latency and mean under various producer/consumer configurations

import ../framework
import ../../loony
import std/[threads, times]

type
  BenchmarkConfig = object
    producers: int
    consumers: int
    itemsPerThread: int
    iterations: int

proc runBenchmarkIteration(config: BenchmarkConfig): float =
  ## Run a single benchmark iteration and return elapsed time in milliseconds
  let totalItems = config.producers * config.itemsPerThread
  var startTime = now()
  
  let q = newLoonyQueue[int]()
  
  # Producers
  var prodThreads: seq[Thread[tuple[q: LoonyQueue[int], itemCount: int]]]
  for p in 0..<config.producers:
    var t: Thread[tuple[q: LoonyQueue[int], itemCount: int]]
    createThread(t, proc(data: tuple[q: LoonyQueue[int], itemCount: int]) =
      for i in 0..<data.itemCount:
        data.q.push(i)
    , (q, config.itemsPerThread))
    prodThreads.add(t)
  
  # Consumers
  var consThreads: seq[Thread[tuple[q: LoonyQueue[int], itemCount: int]]]
  for c in 0..<config.consumers:
    var t: Thread[tuple[q: LoonyQueue[int], itemCount: int]]
    createThread(t, proc(data: tuple[q: LoonyQueue[int], itemCount: int]) =
      for _ in 0..<data.itemCount:
        discard data.q.pop()
    , (q, config.itemsPerThread))
    consThreads.add(t)
  
  # Wait for completion
  for t in prodThreads:
    joinThread(t)
  for t in consThreads:
    joinThread(t)
  
  let duration = (now() - startTime).inMilliseconds.float
  return duration

proc benchmarkConfiguration(config: BenchmarkConfig) =
  ## Run benchmark with given configuration and report statistics
  let configName = &"{config.producers}P/{config.consumers}C-{config.itemsPerThread*config.producers}k"
  
  var times = newSeq[float](config.iterations)
  for i in 0..<config.iterations:
    times[i] = runBenchmarkIteration(config)
  
  let analysis = analyze(times)
  reportTable(@[(configName, analysis)])

suite "Performance: Throughput Benchmarks":
  
  test "SPSC 1P/1C - baseline (1000 items per thread, 5 iterations)":
    let config = BenchmarkConfig(producers: 1, consumers: 1, itemsPerThread: 1000, iterations: 5)
    benchmarkConfiguration(config)
  
  test "SPSC 1P/1C - high volume (10000 items per thread, 3 iterations)":
    let config = BenchmarkConfig(producers: 1, consumers: 1, itemsPerThread: 10000, iterations: 3)
    benchmarkConfiguration(config)
  
  test "MPSC 2P/1C (500 items per thread, 5 iterations)":
    let config = BenchmarkConfig(producers: 2, consumers: 1, itemsPerThread: 500, iterations: 5)
    benchmarkConfiguration(config)
  
  test "MPSC 4P/1C (500 items per thread, 5 iterations)":
    let config = BenchmarkConfig(producers: 4, consumers: 1, itemsPerThread: 500, iterations: 5)
    benchmarkConfiguration(config)
  
  test "SPMC 1P/2C (500 items per thread, 5 iterations)":
    let config = BenchmarkConfig(producers: 1, consumers: 2, itemsPerThread: 500, iterations: 5)
    benchmarkConfiguration(config)
  
  test "SPMC 1P/4C (500 items per thread, 5 iterations)":
    let config = BenchmarkConfig(producers: 1, consumers: 4, itemsPerThread: 500, iterations: 5)
    benchmarkConfiguration(config)
  
  test "MPMC 2P/2C (500 items per thread, 5 iterations)":
    let config = BenchmarkConfig(producers: 2, consumers: 2, itemsPerThread: 500, iterations: 5)
    benchmarkConfiguration(config)
  
  test "MPMC 4P/4C (500 items per thread, 5 iterations)":
    let config = BenchmarkConfig(producers: 4, consumers: 4, itemsPerThread: 500, iterations: 5)
    benchmarkConfiguration(config)
  
  test "High contention 4P/4C (1000 items per thread, 5 iterations)":
    let config = BenchmarkConfig(producers: 4, consumers: 4, itemsPerThread: 1000, iterations: 5)
    benchmarkConfiguration(config)
  
  test "Extreme imbalance 1P/4C (1000 items per thread, 3 iterations)":
    let config = BenchmarkConfig(producers: 1, consumers: 4, itemsPerThread: 1000, iterations: 3)
    benchmarkConfiguration(config)
