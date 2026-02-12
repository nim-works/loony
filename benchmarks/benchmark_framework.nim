## Loony Queue - Comprehensive Benchmark Framework
## Provides exhaustive performance measurement across all access patterns
## Supports SPSC, MPSC, SPMC, MPMC with statistical analysis

import std/[times, atomics, os, strformat, sequtils, algorithm, math, strutils]

proc repeatStr*(s: string, n: int): string =
  ## Repeat a string n times
  result = ""
  for _ in 0..<n:
    result.add(s)

type
  TimingStats* = object
    min*: float64        # Nanoseconds
    max*: float64
    mean*: float64
    median*: float64
    p99*: float64
    p999*: float64
    stddev*: float64
    samples*: int

  BenchmarkResult* = object
    name*: string
    producers*: int
    consumers*: int
    itemsPerThread*: int
    totalItems*: int
    durationMs*: float64
    throughput*: float64  # items/sec
    latencyStats*: TimingStats

  BenchmarkConfig* = object
    producers*: int
    consumers*: int
    itemsPerThread*: int
    iterations*: int
    sampleLatency*: bool  # If true, measure individual operation latency

proc computeStats*(timings: seq[float64]): TimingStats =
  ## Compute statistical analysis of timing data (in nanoseconds)
  if timings.len == 0:
    return TimingStats()
  
  let sorted = timings.sorted()
  result.samples = timings.len
  result.min = sorted[0]
  result.max = sorted[^1]
  result.mean = timings.foldl(a + b, 0.0) / float64(timings.len)
  
  # Percentiles
  result.median = sorted[timings.len div 2]
  result.p99 = sorted[int(float64(timings.len) * 0.99)]
  result.p999 = sorted[int(float64(timings.len) * 0.999)]
  
  # Standard deviation
  let variance = timings.mapIt((it - result.mean) * (it - result.mean))
    .foldl(a + b, 0.0) / float64(timings.len)
  result.stddev = sqrt(variance)

proc reportBenchmarkResult*(result: BenchmarkResult) =
  ## Print formatted benchmark result
  echo "\n" & repeatStr("=", 80)
  echo &"Benchmark: {result.name}"
  echo &"Producers: {result.producers}, Consumers: {result.consumers}"
  echo &"Items/Thread: {result.itemsPerThread}, Total: {result.totalItems}"
  echo repeatStr("=", 80)
  echo &"Duration: {result.durationMs:.2f}ms"
  echo &"Throughput: {result.throughput:.0f} items/sec"
  
  if result.latencyStats.samples > 0:
    let stats = result.latencyStats
    echo "\nLatency Statistics (nanoseconds):"
    echo &"  Min:    {stats.min:.0f}"
    echo &"  p50:    {stats.median:.0f}"
    echo &"  p99:    {stats.p99:.0f}"
    echo &"  p999:   {stats.p999:.0f}"
    echo &"  Max:    {stats.max:.0f}"
    echo &"  Mean:   {stats.mean:.0f}"
    echo &"  StdDev: {stats.stddev:.0f}"
    echo &"  Samples: {stats.samples}"

proc reportBenchmarkSummary*(results: seq[BenchmarkResult]) =
  ## Print summary table of all benchmarks
  echo "\n" & repeatStr("=", 100)
  echo "BENCHMARK SUMMARY"
  echo repeatStr("=", 100)
  echo ""
  
  # Print header
  echo "Config              | Duration     | Throughput      | Latency (ns)     | p99 (ns)    "
  echo repeatStr("-", 100)
  
  # Print each result
  for result in results:
    let configStr = &"{result.producers}P/{result.consumers}C"
    let durationStr = &"{result.durationMs:.2f}ms"
    let throughputStr = &"{result.throughput:.0f} items/s"
    let latencyStr = if result.latencyStats.samples > 0:
      &"{result.latencyStats.mean:.0f}"
    else:
      "N/A"
    let p99Str = if result.latencyStats.samples > 0:
      &"{result.latencyStats.p99:.0f}"
    else:
      "N/A"
    
    echo configStr.alignLeft(20) & "| " & durationStr.alignLeft(12) & "| " & throughputStr.alignLeft(15) & "| " & latencyStr.alignLeft(17) & "| " & p99Str.alignLeft(11)
  
  echo repeatStr("=", 100)

proc formatBytes*(bytes: uint64): string =
  ## Format bytes to human readable form
  const units = ["B", "KB", "MB", "GB"]
  var size = float64(bytes)
  var unitIdx = 0
  
  while size > 1024 and unitIdx < units.len - 1:
    size /= 1024
    unitIdx += 1
  
  &"{size:.2f} {units[unitIdx]}"

proc reportMemoryStats*(name: string, bytes: uint64) =
  ## Print memory usage stats
  echo &"{name}: {formatBytes(bytes)}"
