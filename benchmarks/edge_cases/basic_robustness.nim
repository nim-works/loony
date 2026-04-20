## Edge Case Tests: Basic Robustness
## Contract: Queue doesn't crash under unusual conditions

import balls
import ../../loony
import ../../loony/ward

suite "Edge Cases: Basic Robustness":
  
  test "Queue destroyed with items pending - no crash":
    block:
      let q = newLoonyQueue[int]()
      discard q.push(1)
      discard q.push(2)
      discard q.push(3)
    assert true
  
  test "Ward destroyed with items pending - no crash":
    block:
      let q = newLoonyQueue[int]()
      let w = newWard[int](q, {})
      discard w.push(10)
      discard w.push(20)
    assert true
  
  test "Paused ward destruction - no crash":
    block:
      let q = newLoonyQueue[int]()
      let w = newWard[int](q, {Pausable})
      discard w.pause()
      discard w.push(1)
    assert true
  
  test "Multiple wards on same queue destroyed sequentially - no crash":
    block:
      let q = newLoonyQueue[int]()
      let w1 = newWard[int](q, {})
      let w2 = newWard[int](q, {PopPausable})
      let w3 = newWard[int](q, {Clearable})
      discard w1.push(1)
      discard w2.push(2)
      discard w3.push(3)
    assert true
  
  test "Rapid create/destroy cycles (100 iterations) - no crash":
    for _ in 0..99:
      block:
        let q = newLoonyQueue[int]()
        discard q.push(42)
        discard q.pop()
    assert true
  
  test "Ward clear and reuse - no crash":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Clearable})
    
    discard w.push(1)
    discard w.push(2)
    w.clear()
    
    discard w.push(3)
    discard w.push(4)
    assert w.pop() == 3
    assert w.pop() == 4
  
  test "Nil value push/pop - preserved correctly":
    type Item = ref object
      value: int
    
    let q = newLoonyQueue[Item]()
    let nilValue: Item = nil
    
    q.push(nilValue)
    let popped = q.pop()
    
    assert popped == nil
  
  test "Multiple nils in sequence - all preserved":
    type Item = ref object
      id: int
    
    let q = newLoonyQueue[Item]()
    q.push(nil)
    q.push(nil)
    q.push(nil)
    
    let p1 = q.pop()
    let p2 = q.pop()
    let p3 = q.pop()
    
    assert p1 == nil
    assert p2 == nil
    assert p3 == nil
  
  test "Mixed nil and non-nil values - FIFO preserved":
    type Item = ref object
      id: int
    
    let q = newLoonyQueue[Item]()
    
    let obj1 = new Item
    obj1.id = 1
    q.push(obj1)
    q.push(nil)
    
    let obj2 = new Item
    obj2.id = 2
    q.push(obj2)
    
    let p1 = q.pop()
    assert p1 != nil and p1.id == 1
    
    let p2 = q.pop()
    assert p2 == nil
    
    let p3 = q.pop()
    assert p3 != nil and p3.id == 2
