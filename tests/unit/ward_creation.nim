## Unit Tests: Ward Creation & Configuration
## Contract: Ward configuration flags control behavior correctly

import balls
import ../../loony
import ../../loony/ward

type
  IntBox = ref object
    value: int

suite "Ward Creation & Configuration":
  
  test "newWard with no flags creates valid ward":
    let q = newLoonyQueue[IntBox]()
    let w = newWard[IntBox](q, {})
    assert w != nil
  
  test "newWard with PopPausable flag":
    let q = newLoonyQueue[IntBox]()
    let w = newWard[IntBox](q, {PopPausable})
    assert w != nil
  
  test "newWard with PushPausable flag":
    let q = newLoonyQueue[IntBox]()
    let w = newWard[IntBox](q, {PushPausable})
    assert w != nil
  
  test "newWard with Pausable flag (both push and pop)":
    let q = newLoonyQueue[IntBox]()
    let w = newWard[IntBox](q, {Pausable})
    assert w != nil
  
  test "newWard with Clearable flag":
    let q = newLoonyQueue[IntBox]()
    let w = newWard[IntBox](q, {Clearable})
    assert w != nil
  
  test "Ward FIFO order maintained":
    let q = newLoonyQueue[IntBox]()
    let w = newWard[IntBox](q, {})
    
    for i in 1..5:
      let b = new IntBox
      b.value = i
      discard w.push(b)
    
    for i in 1..5:
      let v = w.pop()
      assert v.value == i
