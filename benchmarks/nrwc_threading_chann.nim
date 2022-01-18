import threading/channels

import std/osproc
import std/strutils
import std/logging
import std/atomics
import std/os
import std/macros
import benchy

import balls

import loony

const
  continuationCount = 1024
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
  Continuation = ref object
    running: bool



var q: LoonyQueue[Continuation]
var counter {.global.}: Atomic[int]

proc runThings() {.thread.} =
  var chances: int
  while true:
    var job = pop q
    if job.isNil() or not job.running:
      if chances == 100:
        break
      else:
        inc chances
    else:
      discard counter.fetchAdd(1)

template expectCounter(n: int): untyped =
  ## convenience
  try:
    check counter.load == n
  except Exception:
    checkpoint " counter: ", load counter
    checkpoint "expected: ", n
    raise

timeIt("Loony", 10000):
  block:
    block:
      ## creation and initialization of the queue

      # Moment of truth
      q = newLoonyQueue[Continuation]()

    block:
      ## run some continuations through the queue in many threads
      var threads: seq[Thread[void]]
      newSeq(threads, threadCount)

      counter.store 0
      for i in 0 ..< continuationCount:
        q.push Continuation(running: true)

      for thread in threads.mitems:
        createThread(thread, runThings)

      for thread in threads.mitems:
        joinThread thread

      expectCounter continuationCount

var chan: Chan[Continuation]

proc runThingsSq() {.thread.} =
  var chances: int
  while true:
    var job: Continuation
    discard chan.tryRecv(job)
    if job.isNil() or not job.running:
      if chances == 100:
        break
      else:
        inc chances
    else:
      discard counter.fetchAdd(1)


timeIt("Sync Spsc", 10000):
  block:
    block:
      ## creation and initialization of the queue

      # Moment of truth
      chan = newChan[Continuation](continuationCount)

    block:
      ## run some continuations through the queue in many threads
      var threads: seq[Thread[void]]
      newSeq(threads, threadCount)

      counter.store 0
      for i in 0 ..< continuationCount:
        var c = Continuation(running: true)
        discard chan.trySend(c)

      for thread in threads.mitems:
        createThread(thread, runThingsSq)

      for thread in threads.mitems:
        joinThread thread

      expectCounter continuationCount
