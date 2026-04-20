## Edge Case Tests: Nil Handling
## Contract: Nil values are handled correctly for reference types

import ../framework
import ../../loony
import ../../loony/ward

suite "Edge Cases: Nil Handling":
  
  test "Pushing nil value (ref type)":
    type Item = ref object
      value: int
    
    let q = newLoonyQueue[Item]()
    let nilValue: Item = nil
    
    q.push(nilValue)
    let popped = q.pop()
    
    check popped == nil, "Nil value should be preserved"
  
  test "Multiple nil values in sequence":
    type Item = ref object
      data: string
    
    let q = newLoonyQueue[Item]()
    
    q.push(nil)
    q.push(nil)
    q.push(nil)
    
    let p1 = q.pop()
    let p2 = q.pop()
    let p3 = q.pop()
    
    check p1 == nil, "First nil should be preserved"
    check p2 == nil, "Second nil should be preserved"
    check p3 == nil, "Third nil should be preserved"
  
  test "Mixed nil and non-nil values":
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
    let p2 = q.pop()
    let p3 = q.pop()
    
    check p1 != nil and p1.id == 1, "First object should be preserved"
    check p2 == nil, "Nil in middle should be preserved"
    check p3 != nil and p3.id == 2, "Second object should be preserved"
  
  test "Ward with nil values":
    type Item = ref object
      value: int
    
    let q = newLoonyQueue[Item]()
    let w = newWard[Item](q, {})
    
    discard w.push(nil)
    discard w.push(nil)
    
    let p1 = w.pop()
    let p2 = w.pop()
    
    check p1 == nil, "Ward should preserve nil"
    check p2 == nil, "Ward should preserve nil"
  
  test "Nil in complex type":
    type Inner = ref object
      x: int
    
    type Outer = object
      inner: Inner
      other: int
    
    let q = newLoonyQueue[Outer]()
    
    var obj: Outer
    obj.inner = nil
    obj.other = 42
    
    q.push(obj)
    let popped = q.pop()
    
    check popped.inner == nil, "Nil inner reference should be preserved"
    checkEqual(popped.other, 42, "Other field should be preserved")
  
  test "Queue with only nil values (1000 items)":
    type Item = ref object
      data: seq[int]
    
    let q = newLoonyQueue[Item]()
    
    for _ in 0..<1000:
      q.push(nil)
    
    for _ in 0..<1000:
      let v = q.pop()
      check v == nil, "All nils should be preserved"
  
  test "Nil comparison after pop":
    type Item = ref object
      id: int
    
    let q = newLoonyQueue[Item]()
    
    discard q.push(nil)
    let popped = q.pop()
    
    if popped == nil:
      check true, "Nil check after pop should work"
    else:
      check false, "Popped nil should compare equal to nil"
  
  test "Nil in optional-like usage":
    type Maybe = ref object
      hasValue: bool
      value: int
    
    let q = newLoonyQueue[Maybe]()
    
    let none: Maybe = nil
    let some = new Maybe
    some.hasValue = true
    some.value = 42
    
    q.push(none)
    q.push(some)
    
    let p1 = q.pop()
    let p2 = q.pop()
    
    check p1 == nil, "None variant should be nil"
    check p2 != nil and p2.value == 42, "Some variant should have value"
  
  test "Nil values FIFO preserved":
    type Item = ref object
      tag: string
    
    let q = newLoonyQueue[Item]()
    
    let obj1 = new Item
    obj1.tag = "first"
    
    q.push(obj1)
    q.push(nil)
    q.push(nil)
    
    let obj2 = new Item
    obj2.tag = "last"
    
    q.push(obj2)
    
    let p1 = q.pop()
    let p2 = q.pop()
    let p3 = q.pop()
    let p4 = q.pop()
    
    check p1.tag == "first", "First object preserved"
    check p2 == nil, "First nil in correct position"
    check p3 == nil, "Second nil in correct position"
    check p4.tag == "last", "Last object preserved"
  
  test "Nil in sequence type":
    type Item = ref object
      items: seq[int]
    
    let q = newLoonyQueue[Item]()
    
    discard q.push(nil)
    
    let obj = new Item
    obj.items = @[1, 2, 3]
    discard q.push(obj)
    
    let p1 = q.pop()
    let p2 = q.pop()
    
    check p1 == nil, "Nil object should be nil"
    check p2.items.len == 3, "Object with sequence should be preserved"
