## Unit Tests: Ward Creation & Configuration
## Contract: Ward configuration flags control behavior correctly

import ../../loony
import ../../loony/ward

type
  IntBox = ref object
    value: int

# Test: newWard with no flags creates valid ward
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {})
  doAssert w != nil

# Test: newWard with PopPausable flag
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {PopPausable})
  doAssert w != nil

# Test: newWard with PushPausable flag
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {PushPausable})
  doAssert w != nil

# Test: newWard with Pausable flag (both push and pop)
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {Pausable})
  doAssert w != nil

# Test: newWard with Clearable flag
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {Clearable})
  doAssert w != nil

# Test: Ward FIFO order maintained
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {})
  for i in 1..5:
    let b = new IntBox
    b.value = i
    discard w.push(b)
  for i in 1..5:
    let v = w.pop()
    doAssert v.value == i

echo "ward_creation: all tests passed"
