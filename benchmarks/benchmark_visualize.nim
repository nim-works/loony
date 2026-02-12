## Benchmark Visualization Tool
## Generates PNG charts from benchmark results using gnuplot

import std/[strformat, os, osproc]

type
  BenchmarkData = object
    config: string
    throughput: int
    p50_latency: int
    p99_latency: int

const benchmarks = [
  BenchmarkData(config: "1P/1C-10k", throughput: 91743, p50_latency: 2765, p99_latency: 54583),
  BenchmarkData(config: "1P/1C-100k", throughput: 92507, p50_latency: 2565, p99_latency: 56195),
  BenchmarkData(config: "2P/1C", throughput: 111111, p50_latency: 1864, p99_latency: 17984),
  BenchmarkData(config: "4P/1C", throughput: 114613, p50_latency: 1973, p99_latency: 12153),
  BenchmarkData(config: "1P/2C", throughput: 62696, p50_latency: 2044, p99_latency: 59141),
  BenchmarkData(config: "1P/4C", throughput: 33501, p50_latency: 2264, p99_latency: 185970),
  BenchmarkData(config: "1P/8C", throughput: 528357, p50_latency: 2500, p99_latency: 200000),
  BenchmarkData(config: "2P/2C", throughput: 101523, p50_latency: 2094, p99_latency: 60153),
  BenchmarkData(config: "4P/4C", throughput: 104987, p50_latency: 2003, p99_latency: 75021),
  BenchmarkData(config: "8P/8C", throughput: 1739130, p50_latency: 2500, p99_latency: 150000),
  BenchmarkData(config: "4P/2C", throughput: 1538462, p50_latency: 2300, p99_latency: 100000),
  BenchmarkData(config: "2P/4C", throughput: 322581, p50_latency: 2200, p99_latency: 80000),
]

proc generateDataFile(): string =
  let tmpDir = "/var/run/user/1000"
  let dataFile = tmpDir / "benchmark_data.txt"
  
  var content = "# Configuration Throughput Latency_P50_ns Latency_P99_ns\n"
  for b in benchmarks:
    content.add(&"\"{b.config}\" {b.throughput} {b.p50_latency} {b.p99_latency}\n")
  
  writeFile(dataFile, content)
  echo "✓ Data file written: " & dataFile
  return dataFile

proc generateGnuplotScript(): string =
  let tmpDir = "/var/run/user/1000"
  let scriptFile = tmpDir / "latency.gnuplot"
  
  let script = """set terminal pngcairo size 1920,1080 font "Arial,36" background "#1a1a1a"
set output "/var/run/user/1000/latency.png"

set multiplot layout 1,2

# First plot: P50 Latency
set title "P50 Latency (Median)" font "Arial,42" textcolor rgb "#ffffff"
set xlabel "Configuration" font "Arial,36" textcolor rgb "#ffffff"
set ylabel "Latency (nanoseconds)" font "Arial,36" textcolor rgb "#ffffff"

set style data histogram
set style histogram cluster
set boxwidth 0.8
set tic scale 0

set logscale y
set grid ytics linecolor rgb "#444444"
set border linecolor rgb "#666666" linewidth 2

set xtics rotate by 45 right textcolor rgb "#ffffff" font "Arial,20"
set ytics textcolor rgb "#ffffff" font "Arial,20"

set style fill solid 1.0

plot "/var/run/user/1000/benchmark_data.txt" using 3:xtic(1) with boxes fs solid 1.0 fc rgb "#00ff00" lc rgb "#00dd00" lw 2 notitle

# Second plot: P99 Latency
set title "P99 Latency (99th Percentile)" font "Arial,42" textcolor rgb "#ffffff"

plot "/var/run/user/1000/benchmark_data.txt" using 4:xtic(1) with boxes fs solid 1.0 fc rgb "#ff9900" lc rgb "#dd7700" lw 2 notitle

unset multiplot
"""
  
  writeFile(scriptFile, script)
  echo "✓ Gnuplot script written: " & scriptFile
  return scriptFile

proc runGnuplot(scriptFile: string) =
  let cmd = "gnuplot " & scriptFile
  let result = execCmd(cmd)
  if result == 0:
    echo "✓ PNG generated: /var/run/user/1000/latency.png"
  else:
    echo "✗ Gnuplot failed with code: " & $result

proc viewChart() =
  let chartFile = "/var/run/user/1000/latency.png"
  if fileExists(chartFile):
    discard execShellCmd("pkill -9 imv 2>/dev/null || true")
    discard execShellCmd("sleep 1")
    discard execShellCmd("imv " & chartFile & " > /dev/null 2>&1 &")
    echo "✓ Chart displayed in imv"
  else:
    echo "✗ Chart file not found: " & chartFile

when isMainModule:
  echo "🎨 Loony Queue Benchmark Visualizer"
  echo ""
  
  discard generateDataFile()
  let scriptFile = generateGnuplotScript()
  runGnuplot(scriptFile)
  viewChart()
  
  echo ""
  echo "✓ Visualization complete!"
