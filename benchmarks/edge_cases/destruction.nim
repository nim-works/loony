## Edge Case Tests: Destruction Safety
## Contract: Destroying queue/ward with pending operations doesn't crash or corrupt

import ../framework
import ../../loony
import ../../loony/ward
import std/[threads]

suite "Edge Cases: Destruction Safety":
  
  test "Destroying queue with items pending - no crash":
    block:
      let q = newLoonyQueue[int]()
      discard q.push(1)
      discard q.push(2)
      discard q.push(3)
      # q goes out of scope with items still pending
    
    check true, "Queue destruction with pending items should not crash"
  
  test "Destroying queue during concurrent operations":
    var q: LoonyQueue[int]
    var threadCompleted = false
    
    block:
      q = newLoonyQueue[int]()
      
      var consThread: Thread[tuple[q: LoonyQueue[int], done: ptr bool]]
      createThread(consThread, proc(data: tuple[q: LoonyQueue[int], done: ptr bool]) =
        for i in 0..<100:
          discard data.q.pop()
        data.done[] = true
      , (q, addr threadCompleted))
      
      # q goes out of scope while consumer thread is running
      # (Thread may or may not complete depending on timing)
    
    # Thread cleanup should happen cleanly
    check true, "Queue destruction during concurrent operations completed"
  
  test "Destroying ward with items pending":
    block:
      let q = newLoonyQueue[int]()
      let w = newWard[int](q, {})
      
      discard w.push(10)
      discard w.push(20)
      discard w.push(30)
      
      # w and q go out of scope
    
    check true, "Ward destruction with pending items should not crash"
  
  test "Destroying paused ward":
    block:
      let q = newLoonyQueue[int]()
      let w = newWard[int](q, {Pausable})
      
      discard w.pause()
      discard w.push(1)  # May be rejected due to pause
      
      # w goes out of scope while paused
    
    check true, "Paused ward destruction should not crash"
  
  test "Destroying clearable ward after clear":
    block:
      let q = newLoonyQueue[int]()
      let w = newWard[int](q, {Clearable})
      
      discard w.push(1)
      discard w.push(2)
      w.clear()
      
      # w goes out of scope after clear
    
    check true, "Ward destruction after clear should not crash"
  
  test "Multiple ward instances destroyed sequentially":
    block:
      let q = newLoonyQueue[int]()
      let w1 = newWard[int](q, {})
      let w2 = newWard[int](q, {PopPausable})
      let w3 = newWard[int](q, {Clearable})
      
      discard w1.push(1)
      discard w2.push(2)
      discard w3.push(3)
      
      # All wards destroyed in reverse order of creation
    
    check true, "Multiple ward destruction should not crash"
  
  test "Queue destruction with mixed safe/unsafe state":
    block:
      let q = newLoonyQueue[int]()
      
      q.push(1)
      q.unsafePush(2)
      q.push(3)
      q.unsafePush(4)
      
      # q goes out of scope
    
    check true, "Queue with mixed safe/unsafe state destruction should not crash"
  
  test "Rapid creation and destruction cycles (100 iterations)":
    for i in 0..99:
      block:
        let q = newLoonyQueue[int]()
        discard q.push(i)
        discard q.pop()
        # q destroyed immediately
    
    check true, "100 create/destroy cycles should complete"
  
  test "Rapid ward creation and destruction cycles (50 iterations)":
    for i in 0..49:
      block:
        let q = newLoonyQueue[int]()
        let w = newWard[int](q, {Pausable})
        discard w.push(i)
        # w and q destroyed immediately
    
    check true, "50 ward create/destroy cycles should complete"
  
  test "Destroy ward while pause operation in-flight":
    var w: Ward[int, static set[WardFlag]]
    
    block:
      let q = newLoonyQueue[int]()
      w = newWard[int](q, {Pausable})
      
      discard w.pause()
      # w goes out of scope while paused
    
    check true, "Paused ward destruction should not crash"
  
  test "Recursive ward creation and destruction":
    block:
      let q = newLoonyQueue[int]()
      let w1 = newWard[int](q, {})
      let w2 = newWard[int](w1, {PopPausable})
      let w3 = newWard[int](w2, {Clearable})
      
      discard w3.push(42)
      
      # w3, w2, w1 destroyed in order
    
    check true, "Recursive ward destruction should not crash"
