## Loony Queue - Exhaustive Benchmark Suite
## Runs comprehensive performance tests across all access patterns
## Validates correctness, throughput, and latency characteristics

import std/[times, strformat]
import ./bench_spsc
import ./bench_mpsc
import ./bench_spmc
import ./bench_mpmc
import ./benchmark_framework

proc runAllBenchmarks*() =
  echo "\n" & repeatStr("=", 100)
  echo "LOONY QUEUE - EXHAUSTIVE BENCHMARK SUITE"
  echo repeatStr("=", 100)
  echo &"Start Time: {now()}"
  echo &"Platform: {system.hostOS}"
  echo repeatStr("=", 100)
  
  let startTime = now()
  
  # Run each benchmark category
  runSPSCBenchmarks()
  runMPSCBenchmarks()
  runSPMCBenchmarks()
  runMPMCBenchmarks()
  
  let totalDuration = (now() - startTime).inSeconds.float64
  
  echo "\n" & repeatStr("=", 100)
  echo "BENCHMARK SUITE COMPLETE"
  echo &"Total Duration: {totalDuration:.1f} seconds"
  echo repeatStr("=", 100)

when isMainModule:
  runAllBenchmarks()
