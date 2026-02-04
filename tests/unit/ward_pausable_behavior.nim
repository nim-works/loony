## Unit Tests: Ward Pausable Behavior
## Contract: Pausable flags correctly gate push/pop operations

import balls
import ../../loony
import ../../loony/ward

suite "Ward Pausable Behavior":
  
  test "Ward with PushPausable - push returns false when paused":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {PushPausable})
    
    let result1 = w.push(1)
    assert result1
    
    discard w.pausePush()
    
    let result2 = w.push(2)
    assert not result2
  
  test "Ward with PopPausable - pop behavior when paused":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {PopPausable})
    
    discard w.push(42)
    
    let v1 = w.pop()
    assert v1 == 42
    
    discard w.pausePop()
    assert true
  
  test "Ward with Pausable (both flags) - push returns false when paused":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    
    discard w.pause()
    
    let result = w.push(10)
    assert not result
  
  test "Ward PushPausable - push resumes after resume":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {PushPausable})
    
    discard w.pausePush()
    let paused_result = w.push(1)
    assert not paused_result
    
    discard w.resumePush()
    let unpaused_result = w.push(2)
    assert unpaused_result
  
  test "Ward PopPausable - independent from PushPausable":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    
    discard w.push(1)
    discard w.push(2)
    
    discard w.pausePop()
    
    let push_result = w.push(3)
    assert push_result
  
  test "Ward - FIFO order maintained through pause/resume cycles":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {PushPausable})
    
    discard w.push(1)
    discard w.pausePush()
    discard w.resumePush()
    discard w.push(2)
    discard w.push(3)
    
    assert w.pop() == 1
    assert w.pop() == 2
    assert w.pop() == 3
