import sync/spsc

import std/osproc
import std/strutils
import std/logging
import std/atomics
import std/os
import std/macros
import benchy

import balls
import cps

import loony

const
  continuationCount = when defined(windows): 100_000 else: 100_000
let
  threadCount = 1

addHandler newConsoleLogger()
setLogFilter:
  when defined(danger):
    lvlNotice
  elif defined(release):
    lvlInfo
  else:
    lvlDebug

type
  C = ref object of Continuation

var q: LoonyQueue[Continuation]

proc runThings() {.thread.} =
  var chances: int
  while true:
    var job = pop q
    if job.dismissed:
      if chances == 100:
        break
      else:
        inc chances
        sleep 1
    else:
      while job.running:
        job = trampoline job

proc enqueue(c: C): C {.cpsMagic.} =
  check not q.isNil
  q.push(c)

var counter {.global.}: Atomic[int]

proc doContinualThings() {.cps: C.} =
  discard counter.fetchAdd(1)

template expectCounter(n: int): untyped =
  ## convenience
  try:
    check counter.load == n
  except Exception:
    checkpoint " counter: ", load counter
    checkpoint "expected: ", n
    raise

timeIt("Loony", 100):
  block:
    block:
      ## creation and initialization of the queue

      # Moment of truth
      q = initLoonyQueue[Continuation]()

    block:
      ## run some continuations through the queue in many threads
      var threads: seq[Thread[void]]
      newSeq(threads, threadCount)

      counter.store 0
      for i in 0 ..< continuationCount:
        var c = whelp doContinualThings()
        discard enqueue c

      for thread in threads.mitems:
        createThread(thread, runThings)

      for thread in threads.mitems:
        joinThread thread

      expectCounter continuationCount

type
  D = ref object of Continuation

var sq: SpscSender[Continuation]
var rq: SpscReceiver[Continuation]

proc doContinualThingsSq() {.cps: D.} =
  discard counter.fetchAdd(1)

proc runThingsSq() {.thread.} =
  var chances: int
  while true:
    var job: typeof(whelp doContinualThingsSq())
    discard rq.tryRecv(job)
    if job.dismissed:
      if chances == 100:
        break
      else:
        inc chances
        sleep 1
    else:
      while job.running:
        job = trampoline job

proc enqueueSq(c: D): D {.cpsMagic.} =
  check not q.isNil
  discard sq.trySend(c)

timeIt("Sync Spsc", 100):
  block:
    block:
      ## creation and initialization of the queue

      # Moment of truth
      (sq, rq) = newSpscChannel[Continuation](continuationCount)

    block:
      ## run some continuations through the queue in many threads
      var threads: seq[Thread[void]]
      newSeq(threads, threadCount)

      counter.store 0
      for i in 0 ..< continuationCount:
        var c = whelp doContinualThings()
        discard enqueue c

      for thread in threads.mitems:
        createThread(thread, runThings)

      for thread in threads.mitems:
        joinThread thread

      expectCounter continuationCount
