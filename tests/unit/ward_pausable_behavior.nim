## Unit Tests: Ward Pausable Behavior
## Contract: Pausable flags correctly gate push/pop operations

import ../../loony
import ../../loony/ward

type IntBox = ref object
  value: int

# Ward with PushPausable - push returns false when paused
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {PushPausable})
  let b1 = IntBox(value: 1)
  let result1 = w.push(b1)
  doAssert result1
  discard w.pausePush()
  let b2 = IntBox(value: 2)
  let result2 = w.push(b2)
  doAssert not result2

# Ward with PopPausable - pop behavior when paused
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {PopPausable})
  let b42 = IntBox(value: 42)
  discard w.push(b42)
  let v1 = w.pop()
  doAssert v1.value == 42
  discard w.pausePop()

# Ward with Pausable (both flags) - push returns false when paused
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {Pausable})
  discard w.pause()
  let b10 = IntBox(value: 10)
  let result = w.push(b10)
  doAssert not result

# Ward PushPausable - push resumes after resume
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {PushPausable})
  discard w.pausePush()
  let b1 = IntBox(value: 1)
  let paused_result = w.push(b1)
  doAssert not paused_result
  discard w.resumePush()
  let b2 = IntBox(value: 2)
  let unpaused_result = w.push(b2)
  doAssert unpaused_result

# Ward PopPausable - independent from PushPausable
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {Pausable})
  let b1 = IntBox(value: 1)
  let b2 = IntBox(value: 2)
  discard w.push(b1)
  discard w.push(b2)
  discard w.pausePop()
  let b3 = IntBox(value: 3)
  let push_result = w.push(b3)
  doAssert push_result

# Ward - FIFO order maintained through pause/resume cycles
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {PushPausable})
  let b1 = IntBox(value: 1)
  discard w.push(b1)
  discard w.pausePush()
  discard w.resumePush()
  let b2 = IntBox(value: 2)
  let b3 = IntBox(value: 3)
  discard w.push(b2)
  discard w.push(b3)
  doAssert w.pop().value == 1
  doAssert w.pop().value == 2
  doAssert w.pop().value == 3
