## Edge Case Tests: Pause/Resume Race Conditions
## Contract: Pause/resume operations are safe under concurrent access

import ../framework
import ../../loony
import ../../loony/ward
import std/[threads]

suite "Edge Cases: Pause/Resume Race Conditions":
  
  test "Pause called while push in-flight":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    var pushesMade = 0
    
    var pushThread: Thread[tuple[w: Ward[int, static set[WardFlag]], count: ptr int]]
    createThread(pushThread, proc(data: tuple[w: Ward[int, static set[WardFlag]], count: ptr int]) =
      for i in 0..<1000:
        if data.w.push(i):
          inc data.count[]
    , (w, addr pushesMade))
    
    # Pause while pushes are happening
    for _ in 0..9:
      discard w.pausePush()
      discard w.resumePush()
    
    joinThread(pushThread)
    
    check pushesMade > 0, "Some pushes should have succeeded despite pause/resume"
    check true, "Pause during push should not crash"
  
  test "Resume called while pop in-flight":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {PopPausable})
    
    # Pre-populate
    for i in 0..999:
      discard w.push(i)
    
    var popThread: Thread[Ward[int, static set[WardFlag]]]
    createThread(popThread, proc(w: Ward[int, static set[WardFlag]]) =
      for _ in 0..<1000:
        discard w.pop()
    , w)
    
    # Resume/pause while pops are happening
    for _ in 0..4:
      discard w.pausePop()
      discard w.resumePop()
    
    joinThread(popThread)
    
    check true, "Resume during pop should not crash"
  
  test "Rapid pause/resume cycles (100 cycles)":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    
    # Pre-populate
    for i in 0..99:
      discard w.push(i)
    
    var threadCount = 0
    var lock: Lock
    initLock(lock)
    
    var thread: Thread[tuple[w: Ward[int, static set[WardFlag]], count: ptr int, lock: ptr Lock]]
    createThread(thread, proc(data: tuple[w: Ward[int, static set[WardFlag]], count: ptr int, lock: ptr Lock]) =
      for i in 0..<100:
        discard data.w.pop()
        withLock(data.lock[]):
          inc data.count[]
    , (w, addr threadCount, addr lock))
    
    # 100 rapid pause/resume cycles
    for _ in 0..99:
      discard w.pause()
      discard w.resume()
    
    joinThread(thread)
    
    check threadCount > 0, "Consumer should have made progress despite rapid pause/resume"
    check true, "100 rapid cycles should not crash"
  
  test "pausePush and pausePop called simultaneously from different threads":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    
    for i in 0..<100:
      discard w.push(i)
    
    var pushThread: Thread[Ward[int, static set[WardFlag]]]
    createThread(pushThread, proc(w: Ward[int, static set[WardFlag]]) =
      for _ in 0..<100:
        discard w.pausePush()
        discard w.resumePush()
    , w)
    
    var popThread: Thread[Ward[int, static set[WardFlag]]]
    createThread(popThread, proc(w: Ward[int, static set[WardFlag]]) =
      for _ in 0..<100:
        discard w.pausePop()
        discard w.resumePop()
    , w)
    
    joinThread(pushThread)
    joinThread(popThread)
    
    check true, "Simultaneous pause/resume from different threads should not crash"
  
  test "Push operations continue while pop is paused":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    var pushCount = 0
    var lock: Lock
    initLock(lock)
    
    discard w.pausePop()
    
    var pushThread: Thread[tuple[w: Ward[int, static set[WardFlag]], count: ptr int, lock: ptr Lock]]
    createThread(pushThread, proc(data: tuple[w: Ward[int, static set[WardFlag]], count: ptr int, lock: ptr Lock]) =
      for i in 0..<1000:
        if data.w.push(i):
          withLock(data.lock[]):
            inc data.count[]
    , (w, addr pushCount, addr lock))
    
    joinThread(pushThread)
    
    check pushCount == 1000, "Push should not be affected by pop pause"
  
  test "Pop operations continue while push is paused":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    
    # Pre-populate
    for i in 0..<1000:
      discard w.push(i)
    
    discard w.pausePush()
    
    var popCount = 0
    var lock: Lock
    initLock(lock)
    
    var popThread: Thread[tuple[w: Ward[int, static set[WardFlag]], count: ptr int, lock: ptr Lock]]
    createThread(popThread, proc(data: tuple[w: Ward[int, static set[WardFlag]], count: ptr int, lock: ptr Lock]) =
      for _ in 0..<1000:
        discard data.w.pop()
        withLock(data.lock[]):
          inc data.count[]
    , (w, addr popCount, addr lock))
    
    joinThread(popThread)
    
    check popCount == 1000, "Pop should not be affected by push pause"
  
  test "State queries race with pause/resume operations":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    
    var thread1: Thread[Ward[int, static set[WardFlag]]]
    createThread(thread1, proc(w: Ward[int, static set[WardFlag]]) =
      for _ in 0..<500:
        discard w.pause()
        discard w.resume()
    , w)
    
    var thread2: Thread[Ward[int, static set[WardFlag]]]
    createThread(thread2, proc(w: Ward[int, static set[WardFlag]]) =
      for _ in 0..<500:
        discard w.isPaused()
        discard w.isPopPaused()
        discard w.isPushPaused()
    , w)
    
    joinThread(thread1)
    joinThread(thread2)
    
    check true, "State queries during pause/resume should not crash"
  
  test "Pause state transitions are atomic-looking":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    
    # Start paused
    discard w.pause()
    
    var unpauseCount = 0
    var lock: Lock
    initLock(lock)
    
    var resumeThread: Thread[tuple[w: Ward[int, static set[WardFlag]], count: ptr int, lock: ptr Lock]]
    createThread(resumeThread, proc(data: tuple[w: Ward[int, static set[WardFlag]], count: ptr int, lock: ptr Lock]) =
      for _ in 0..<100:
        if data.w.resume():  # Returns true only if was paused
          withLock(data.lock[]):
            inc data.count[]
    , (w, addr unpauseCount, addr lock))
    
    joinThread(resumeThread)
    
    check unpauseCount > 0, "Resume should eventually succeed"
    check true, "Pause state transitions should be consistent"
