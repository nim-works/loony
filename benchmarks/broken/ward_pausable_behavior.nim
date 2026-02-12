## Unit Tests: Ward Pausable Behavior
## Contract: Pausable flags correctly gate push/pop operations

import ../../loony
import ../../loony/ward

# Ward with PushPausable - push returns false when paused
block:
  let q = newLoonyQueue[int]()
  let w = newWard[int](q, {PushPausable})
  let result1 = w.push(1)
  doAssert result1
  discard w.pausePush()
  let result2 = w.push(2)
  doAssert not result2

# Ward with PopPausable - pop behavior when paused
block:
  let q = newLoonyQueue[int]()
  let w = newWard[int](q, {PopPausable})
  discard w.push(42)
  let v1 = w.pop()
  doAssert v1 == 42
  discard w.pausePop()

# Ward with Pausable (both flags) - push returns false when paused
block:
  let q = newLoonyQueue[int]()
  let w = newWard[int](q, {Pausable})
  discard w.pause()
  let result = w.push(10)
  doAssert not result

# Ward PushPausable - push resumes after resume
block:
  let q = newLoonyQueue[int]()
  let w = newWard[int](q, {PushPausable})
  discard w.pausePush()
  let paused_result = w.push(1)
  doAssert not paused_result
  discard w.resumePush()
  let unpaused_result = w.push(2)
  doAssert unpaused_result

# Ward PopPausable - independent from PushPausable
block:
  let q = newLoonyQueue[int]()
  let w = newWard[int](q, {Pausable})
  discard w.push(1)
  discard w.push(2)
  discard w.pausePop()
  let push_result = w.push(3)
  doAssert push_result

# Ward - FIFO order maintained through pause/resume cycles
block:
  let q = newLoonyQueue[int]()
  let w = newWard[int](q, {PushPausable})
  discard w.push(1)
  discard w.pausePush()
  discard w.resumePush()
  discard w.push(2)
  discard w.push(3)
  doAssert w.pop() == 1
  doAssert w.pop() == 2
  doAssert w.pop() == 3
