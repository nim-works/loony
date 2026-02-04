## Unit Tests: Ward Clear & Count
## Contract: Clear removes items; count is approximate
## NOTE: clear() marked as {.deprecated: "untested".} per API spec

import balls
import ../../loony
import ../../loony/ward

suite "Ward Clear & Count":
  
  test "count() on empty ward returns 0":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {})
    
    let c = w.count()
    assert c == 0
  
  test "count() after push reflects item count":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {})
    
    discard w.push(1)
    discard w.push(2)
    discard w.push(3)
    
    let c = w.count()
    assert c == 3
  
  test "count() after pop decreases":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {})
    
    discard w.push(1)
    discard w.push(2)
    discard w.push(3)
    
    let c1 = w.count()
    discard w.pop()
    let c2 = w.count()
    
    assert c2 < c1
  
  test "clear() with Clearable flag - empties queue":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Clearable})
    
    discard w.push(1)
    discard w.push(2)
    discard w.push(3)
    
    let before = w.count()
    assert before > 0
    
    w.clear()
    
    let after = w.count()
    assert after == 0
  
  test "clear() - queue operations work after clear":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Clearable})
    
    discard w.push(1)
    discard w.push(2)
    w.clear()
    
    discard w.push(3)
    discard w.push(4)
    
    assert w.pop() == 3
    assert w.pop() == 4
  
  test "count() - rough proportionality test":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {})
    
    for i in 0..<100:
      discard w.push(i)
    
    let count100 = w.count()
    assert count100 > 0
    
    for _ in 0..<50:
      discard w.pop()
    
    let count50 = w.count()
    assert count50 < count100
    assert count50 > 0
  
  test "clear() - FIFO order after second batch":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Clearable})
    
    discard w.push(1)
    discard w.push(2)
    w.clear()
    
    discard w.push(100)
    discard w.push(200)
    
    assert w.pop() == 100
    assert w.pop() == 200
