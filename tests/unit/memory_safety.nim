## Unit Tests: Memory Safety & Reference Handling
## Contract: Queue correctly manages ref types without corruption

import balls
import ../../loony

type
  SimpleObj = ref object
    id: int
    data: seq[int]

suite "Memory Safety & Reference Handling":
  
  test "Reference type with mutable state maintained":
    let q = newLoonyQueue[SimpleObj]()
    let obj = new SimpleObj
    obj.id = 42
    obj.data = @[1, 2, 3, 4, 5]
    
    q.push(obj)
    let popped = q.pop()
    
    assert popped.id == 42
    assert popped.data.len == 5
    for i in 0..<5:
      assert popped.data[i] == i + 1
  
  test "Nil reference values work correctly":
    type OptionalRef = ref object
      value: int
    
    let q = newLoonyQueue[OptionalRef]()
    let nilRef: OptionalRef = nil
    
    q.push(nilRef)
    let popped = q.pop()
    
    assert popped == nil
  
  test "Multiple reference types maintain independence":
    type TypeA = ref object
      a: int
    type TypeB = ref object
      b: int
    
    let qa = newLoonyQueue[TypeA]()
    let qb = newLoonyQueue[TypeB]()
    
    let objA = new TypeA
    objA.a = 100
    let objB = new TypeB
    objB.b = 200
    
    qa.push(objA)
    qb.push(objB)
    
    assert qa.pop().a == 100
    assert qb.pop().b == 200
  
  test "Sequence type data integrity":
    type SeqBox = ref object
      data: seq[int]
    
    let q = newLoonyQueue[SeqBox]()
    let box = new SeqBox
    box.data = @[10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
    
    q.push(box)
    let popped = q.pop()
    
    assert popped.data.len == 10
    for i in 0..<10:
      assert popped.data[i] == (i + 1) * 10
  
  test "String type data integrity":
    type StringBox = ref object
      str: string
    
    let q = newLoonyQueue[StringBox]()
    let box = new StringBox
    box.str = "Hello, World! This is a test string with special chars: !@#$%^&*()"
    
    q.push(box)
    let popped = q.pop()
    
    assert popped.str == box.str
  
  test "Nested structure complex object":
    type Inner = object
      x: uint32
      y: uint32
    
    type Outer = ref object
      inner: Inner
      values: array[10, uint16]
    
    let q = newLoonyQueue[Outer]()
    let obj = new Outer
    obj.inner.x = 0xDEADBEEFu32
    obj.inner.y = 0xCAFEBABEu32
    for i in 0..<10:
      obj.values[i] = uint16(i * 256)
    
    q.push(obj)
    let popped = q.pop()
    
    assert popped.inner.x == 0xDEADBEEFu32
    assert popped.inner.y == 0xCAFEBABEu32
    for i in 0..<10:
      assert popped.values[i] == uint16(i * 256)
  
  test "Multiple ref objects maintain independence":
    type Box = ref object
      id: int
      value: int
    
    let q = newLoonyQueue[Box]()
    
    let b1 = new Box
    b1.id = 1
    b1.value = 100
    let b2 = new Box
    b2.id = 2
    b2.value = 200
    let b3 = new Box
    b3.id = 3
    b3.value = 300
    
    q.push(b1)
    q.push(b2)
    q.push(b3)
    
    let p1 = q.pop()
    let p2 = q.pop()
    let p3 = q.pop()
    
    assert p1.value == 100
    assert p2.value == 200
    assert p3.value == 300
