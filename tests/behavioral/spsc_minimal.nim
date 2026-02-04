## Behavioral Test: Minimal SPSC Test
## Single Producer / Single Consumer basic correctness
## Contract: All items delivered in FIFO order, no losses

import balls
import ../../loony

suite "Behavioral: SPSC Correctness":
  
  test "1000 items push/pop sequence maintains FIFO":
    let q = newLoonyQueue[int]()
    let itemCount = 1000
    
    # Push all
    for i in 0..<itemCount:
      q.push(i)
    
    # Pop and verify
    for i in 0..<itemCount:
      let v = q.pop()
      assert v == i
  
  test "String type FIFO order":
    let q = newLoonyQueue[string]()
    let values = @["first", "second", "third", "fourth", "fifth"]
    
    for v in values:
      q.push(v)
    
    for v in values:
      let p = q.pop()
      assert p == v
  
  test "Alternating push/pop pattern":
    let q = newLoonyQueue[int]()
    
    q.push(1)
    q.push(2)
    assert q.pop() == 1
    
    q.push(3)
    assert q.pop() == 2
    assert q.pop() == 3
  
  test "Large objects maintain integrity":
    type LargeData = array[256, uint32]
    let q = newLoonyQueue[LargeData]()
    
    var data: LargeData
    for i in 0..<256:
      data[i] = uint32(i * 17)
    
    q.push(data)
    let popped = q.pop()
    
    for i in 0..<256:
      assert popped[i] == uint32(i * 17)
  
  test "Reference types maintain identity":
    type Item = ref object
      id: int
      value: string
    
    let q = newLoonyQueue[Item]()
    let obj1 = new Item
    obj1.id = 1
    obj1.value = "first"
    
    let obj2 = new Item
    obj2.id = 2
    obj2.value = "second"
    
    q.push(obj1)
    q.push(obj2)
    
    let p1 = q.pop()
    assert p1.id == 1 and p1.value == "first"
    
    let p2 = q.pop()
    assert p2.id == 2 and p2.value == "second"
  
  test "Mixed safe and unsafe operations":
    let q = newLoonyQueue[int]()
    
    for i in 0..<100:
      if i % 2 == 0:
        q.push(i)
      else:
        q.unsafePush(i)
    
    for i in 0..<100:
      let v = if i % 2 == 0: q.pop() else: q.unsafePop()
      assert v == i
  
  test "Ward wrapper maintains FIFO":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {})
    
    for i in 0..<500:
      discard w.push(i)
    
    for i in 0..<500:
      let v = w.pop()
      assert v == i
  
  test "Batched push then batched pop":
    let q = newLoonyQueue[int]()
    let batchSize = 100
    let batchCount = 10
    
    for batch in 0..<batchCount:
      for item in 0..<batchSize:
        q.push(batch * batchSize + item)
    
    for i in 0..<(batchSize * batchCount):
      let v = q.pop()
      assert v == i
