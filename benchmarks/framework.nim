## Custom Minimal Test Framework
## Features: suite/test blocks, parametrization, statistical aggregation
## Philosophy: Black-box contracts only, no implementation inspection

import std/[times, strformat, strutils, sequtils, algorithm]

type
  TestResult* = object
    name*: string
    passed*: bool
    message*: string
    duration*: float  # seconds

  StatAnalysis* = object
    min*: float
    max*: float
    mean*: float
    p50*: float
    p99*: float
    p999*: float

  SuiteContext* = object
    name*: string
    testResults*: seq[TestResult]
    passedCount*: int
    failedCount*: int

var currentSuite*: SuiteContext
var allResults*: seq[TestResult]

# ============================================================================
# Core Test Functions
# ============================================================================

proc suite*(name: string, body: proc()) =
  ## Create a test suite with a name
  currentSuite = SuiteContext(name: name, testResults: @[], passedCount: 0, failedCount: 0)
  body()
  
  # Print suite results
  echo "\n[Suite] " & currentSuite.name
  for result in currentSuite.testResults:
    let status = if result.passed: "✓" else: "✗"
    echo &"  {status} {result.name} ({result.duration*1000:.2f}ms)"
    if not result.passed:
      echo &"      Error: {result.message}"
  
  allResults.add(currentSuite.testResults)

proc test*(name: string, body: proc()) =
  ## Create a single test case
  let startTime = now()
  var passed = true
  var message = ""
  
  try:
    body()
  except:
    passed = false
    message = getCurrentExceptionMsg()
  
  let duration = (now() - startTime).inMilliseconds.float / 1000.0
  let result = TestResult(name: name, passed: passed, message: message, duration: duration)
  currentSuite.testResults.add(result)
  
  if passed:
    currentSuite.passedCount += 1
  else:
    currentSuite.failedCount += 1

proc check*(condition: bool, message: string = "") =
  ## Assert that condition is true
  if not condition:
    let msg = if message.len > 0: message else: "Assertion failed"
    raise newException(AssertionError, msg)

proc checkEqual*[T](actual: T, expected: T, message: string = "") =
  ## Assert that actual equals expected
  if actual != expected:
    let msg = if message.len > 0: message else: &"Expected {expected}, got {actual}"
    raise newException(AssertionError, msg)

proc checkNotEqual*[T](actual: T, expected: T, message: string = "") =
  ## Assert that actual does not equal expected
  if actual == expected:
    let msg = if message.len > 0: message else: &"Expected not {expected}, got {actual}"
    raise newException(AssertionError, msg)

# ============================================================================
# Parametrization Support
# ============================================================================

proc parametrize*[T](values: seq[T], testFn: proc(value: T)) =
  ## Run the same test with multiple parameter values
  for value in values:
    testFn(value)

# ============================================================================
# Performance Measurement
# ============================================================================

proc timeRuns*(iterations: int, body: proc()): seq[float] =
  ## Run a function multiple times and return the duration of each run
  result = newSeq[float](iterations)
  for i in 0..<iterations:
    let startTime = now()
    body()
    let duration = (now() - startTime).inMilliseconds.float
    result[i] = duration

proc analyze*(times: seq[float]): StatAnalysis =
  ## Compute statistics (min, max, mean, p50, p99, p999) from timing data
  if times.len == 0:
    return StatAnalysis()
  
  let sorted = times.sorted()
  result.min = sorted[0]
  result.max = sorted[^1]
  result.mean = sorted.foldl(a + b, 0.0) / times.len.float
  
  # Percentiles
  result.p50 = sorted[int(times.len.float * 0.50)]
  result.p99 = sorted[int(times.len.float * 0.99)]
  result.p999 = sorted[int(times.len.float * 0.999)]

proc reportTable*(results: seq[(string, StatAnalysis)]) =
  ## Generate a formatted performance report table
  echo "\nPerformance Analysis (milliseconds):"
  echo "────────────────────────────────────────────────────────────────────"
  let header = "Config              | p50      | p99      | p999     | mean    "
  echo header
  echo "────────────────────────────────────────────────────────────────────"
  
  for (config, analysis) in results:
    let line = &"{config:<20} | {analysis.p50:<8.3f} | {analysis.p99:<8.3f} | {analysis.p999:<8.3f} | {analysis.mean:<8.3f}"
    echo line
  
  echo "────────────────────────────────────────────────────────────────────"

# ============================================================================
# Summary & Final Report
# ============================================================================

proc printSummary*() =
  ## Print overall test suite summary
  let total = allResults.len
  let passed = allResults.countIt(it.passed)
  let failed = total - passed
  
  echo "\n" & "=".repeat(60)
  echo &"OVERALL RESULTS: {passed}/{total} tests passed"
  
  if failed > 0:
    echo &"FAILED: {failed} test(s)"
    for result in allResults:
      if not result.passed:
        echo &"  ✗ {result.name}: {result.message}"
  else:
    echo "✓ ALL TESTS PASSED"
  
  echo "=".repeat(60)
  
  if failed > 0:
    quit(1)
