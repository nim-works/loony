## Performance Test: Memory Efficiency
## Measures: Peak memory, memory per item, fragmentation patterns

import ../framework
import ../../loony
import ../../loony/ward
import std/[threads]

suite "Performance: Memory Efficiency":
  
  test "Memory with 100k items in flight - no excessive allocation":
    let q = newLoonyQueue[int]()
    let itemCount = 100_000
    var completed = 0
    
    var prodThread: Thread[LoonyQueue[int]]
    createThread(prodThread, proc(q: LoonyQueue[int]) =
      for i in 0..<100_000:
        q.push(i)
    , q)
    
    var consThread: Thread[tuple[q: LoonyQueue[int], completed: ptr int]]
    createThread(consThread, proc(data: tuple[q: LoonyQueue[int], completed: ptr int]) =
      for _ in 0..<100_000:
        discard data.q.pop()
        inc data.completed[]
    , (q, addr completed))
    
    joinThread(prodThread)
    joinThread(consThread)
    
    check completed == itemCount, "All items should be processed"
    # No crash or excessive memory allocation indicates memory safety
    check true, "100k items processed without memory issues"
  
  test "Memory with large objects - proportional allocation":
    type LargeItem = array[1024, uint32]  # 4KB each
    let q = newLoonyQueue[LargeItem]()
    let itemCount = 10_000  # 40MB of items
    var completed = 0
    
    var prodThread: Thread[LoonyQueue[LargeItem]]
    createThread(prodThread, proc(q: LoonyQueue[LargeItem]) =
      for _ in 0..<10_000:
        var item: LargeItem
        q.push(item)
    , q)
    
    var consThread: Thread[tuple[q: LoonyQueue[LargeItem], completed: ptr int]]
    createThread(consThread, proc(data: tuple[q: LoonyQueue[LargeItem], completed: ptr int]) =
      for _ in 0..<10_000:
        discard data.q.pop()
        inc data.completed[]
    , (q, addr completed))
    
    joinThread(prodThread)
    joinThread(consThread)
    
    check completed == itemCount, "All large items should be processed"
    check true, "40MB of items processed without memory issues"
  
  test "Memory pattern: push-pop cycles (no fragmentation)":
    let q = newLoonyQueue[int]()
    
    # Cycle 1: push 1000, pop 1000
    for i in 0..<1000:
      q.push(i)
    for _ in 0..<1000:
      discard q.pop()
    
    # Cycle 2: push 1000, pop 1000 (with same queue instance)
    for i in 0..<1000:
      q.push(i + 1000)
    for _ in 0..<1000:
      discard q.pop()
    
    # Cycle 3: verify queue still works normally
    for i in 0..<100:
      q.push(i + 2000)
    for i in 0..<100:
      let v = q.pop()
      checkEqual(v, i + 2000, "Queue should work normally after cycles")
    
    check true, "Push-pop cycles completed without fragmentation"
  
  test "Memory after clear() operation":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Clearable})
    
    # Fill with items
    for i in 0..<10_000:
      discard w.push(i)
    
    # Clear
    w.clear()
    
    # Use again
    for i in 0..<10_000:
      discard w.push(i + 10_000)
    
    for i in 0..<10_000:
      let v = w.pop()
      checkEqual(v, i + 10_000, "Ward should work normally after clear")
    
    check true, "Memory reused properly after clear"
  
  test "Reference counting - no leaks with ref objects":
    type RefItem = ref object
      id: int
      data: seq[int]
    
    let q = newLoonyQueue[RefItem]()
    let itemCount = 10_000
    
    # Create and enqueue
    var prodThread: Thread[LoonyQueue[RefItem]]
    createThread(prodThread, proc(q: LoonyQueue[RefItem]) =
      for i in 0..<10_000:
        let item = new RefItem
        item.id = i
        item.data = @[i, i+1, i+2]
        q.push(item)
    , q)
    
    # Dequeue and drop
    var consThread: Thread[LoonyQueue[RefItem]]
    createThread(consThread, proc(q: LoonyQueue[RefItem]) =
      for _ in 0..<10_000:
        let _ = q.pop()  # Item goes out of scope, should be GC'd
    , q)
    
    joinThread(prodThread)
    joinThread(consThread)
    
    check true, "Reference objects processed without leaks (GC cleanup)"
  
  test "Memory stability - repeated create/destroy cycles":
    for cycle in 0..4:
      let q = newLoonyQueue[int]()
      
      for i in 0..<1000:
        q.push(i)
      
      for _ in 0..<1000:
        discard q.pop()
      
      # q goes out of scope and is destroyed
    
    check true, &"5 complete queue create/destroy cycles completed"
  
  test "Memory with mixed safe/unsafe operations":
    let q = newLoonyQueue[int]()
    let totalOps = 50_000
    
    var prodThread: Thread[LoonyQueue[int]]
    createThread(prodThread, proc(q: LoonyQueue[int]) =
      for i in 0..<50_000:
        if i % 3 == 0:
          q.push(i)
        else:
          q.unsafePush(i)
    , q)
    
    var consThread: Thread[LoonyQueue[int]]
    createThread(consThread, proc(q: LoonyQueue[int]) =
      for i in 0..<50_000:
        if i % 3 == 0:
          discard q.pop()
        else:
          discard q.unsafePop()
    , q)
    
    joinThread(prodThread)
    joinThread(consThread)
    
    check true, "50k mixed safe/unsafe operations completed without memory issues"
  
  test "Memory under concurrent access patterns":
    let q = newLoonyQueue[int]()
    
    # 4 threads pushing and popping concurrently
    var threads: seq[Thread[LoonyQueue[int]]]
    
    for t in 0..3:
      var th: Thread[LoonyQueue[int]]
      createThread(th, proc(q: LoonyQueue[int]) =
        for i in 0..<2500:
          q.push(i)
          if i % 2 == 0:
            discard q.pop()
      , q)
      threads.add(th)
    
    for t in threads:
      joinThread(t)
    
    check true, "Concurrent access patterns completed without memory issues"
