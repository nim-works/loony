## Unit Tests: Ward Clear & Count
## Contract: Clear removes items; count is approximate
## NOTE: clear() marked as {.deprecated: "untested".} per API spec

import ../../loony
import ../../loony/ward

type IntBox = ref object
  value: int

# count() on empty ward returns 0
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {})
  let c = w.count()
  doAssert c == 0

# count() after push reflects item count
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {})
  discard w.push(IntBox(value: 1))
  discard w.push(IntBox(value: 2))
  discard w.push(IntBox(value: 3))
  let c = w.count()
  doAssert c == 3

# count() after pop decreases
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {})
  discard w.push(IntBox(value: 1))
  discard w.push(IntBox(value: 2))
  discard w.push(IntBox(value: 3))
  let c1 = w.count()
  discard w.pop()
  let c2 = w.count()
  doAssert c2 < c1

# clear() with Clearable flag - empties queue
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {Clearable})
  discard w.push(IntBox(value: 1))
  discard w.push(IntBox(value: 2))
  discard w.push(IntBox(value: 3))
  let before = w.count()
  doAssert before > 0
  w.clear()
  let after = w.count()
  doAssert after == 0

# clear() - queue operations work after clear
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {Clearable})
  discard w.push(IntBox(value: 1))
  discard w.push(IntBox(value: 2))
  w.clear()
  discard w.push(IntBox(value: 3))
  discard w.push(IntBox(value: 4))
  doAssert w.pop().value == 3
  doAssert w.pop().value == 4

# count() - rough proportionality test
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {})
  for i in 0..<100:
    discard w.push(IntBox(value: i))
  let count100 = w.count()
  doAssert count100 > 0
  for _ in 0..<50:
    discard w.pop()
  let count50 = w.count()
  doAssert count50 < count100
  doAssert count50 > 0

# clear() - FIFO order after second batch
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {Clearable})
  discard w.push(IntBox(value: 1))
  discard w.push(IntBox(value: 2))
  w.clear()
  discard w.push(IntBox(value: 100))
  discard w.push(IntBox(value: 200))
  doAssert w.pop().value == 100
  doAssert w.pop().value == 200
