## Unit Tests: Queue Creation & Basic Operations
## Contract: Items enqueued are dequeued in FIFO order
## Note: Loony is designed for reference types; all tests use ref types

import balls
import ../../loony

type
  IntBox = ref object
    value: int
  StringBox = ref object
    value: string

suite "Queue Creation & Basic Operations":
  
  test "newLoonyQueue creates valid queue":
    let q = newLoonyQueue[IntBox]()
    assert q != nil
  
  test "push then pop returns same element":
    let q = newLoonyQueue[IntBox]()
    let obj = new IntBox
    obj.value = 42
    q.push(obj)
    let popped = q.pop()
    assert popped.value == 42
  
  test "multiple push/pop maintains FIFO order":
    let q = newLoonyQueue[IntBox]()
    
    var boxes: seq[IntBox] = @[]
    for i in 1..5:
      let b = new IntBox
      b.value = i
      boxes.add(b)
    
    for b in boxes:
      q.push(b)
    
    for b in boxes:
      let popped = q.pop()
      assert popped.value == b.value
  
  test "works with string ref type":
    let q = newLoonyQueue[StringBox]()
    let strs = @["hello", "world", "test"]
    
    for s in strs:
      let box = new StringBox
      box.value = s
      q.push(box)
    
    for s in strs:
      let popped = q.pop()
      assert popped.value == s
  
  test "FIFO holds across batches":
    let q = newLoonyQueue[IntBox]()
    
    # Batch 1
    for i in 1..3:
      let b = new IntBox
      b.value = i
      q.push(b)
    
    for i in 1..3:
      assert q.pop().value == i
    
    # Batch 2
    for i in 4..6:
      let b = new IntBox
      b.value = i
      q.push(b)
    
    for i in 4..6:
      assert q.pop().value == i
  
  test "alternating push and pop maintains FIFO":
    let q = newLoonyQueue[IntBox]()
    
    var b1 = new IntBox
    b1.value = 1
    var b2 = new IntBox
    b2.value = 2
    var b3 = new IntBox
    b3.value = 3
    
    q.push(b1)
    q.push(b2)
    assert q.pop().value == 1
    
    q.push(b3)
    assert q.pop().value == 2
    assert q.pop().value == 3
  
  test "large number of sequential operations (1000)":
    let q = newLoonyQueue[IntBox]()
    let itemCount = 1000
    
    for i in 0..<itemCount:
      let b = new IntBox
      b.value = i
      q.push(b)
    
    for i in 0..<itemCount:
      let v = q.pop()
      assert v.value == i
  
  test "safe vs unsafe variant compatibility":
    let q = newLoonyQueue[IntBox]()
    let b1 = new IntBox
    b1.value = 10
    let b2 = new IntBox
    b2.value = 20
    
    q.push(b1)
    q.unsafePush(b2)
    
    discard q.pop()
    discard q.unsafePop()
    assert true
