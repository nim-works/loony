## Unit Tests: Ward Clear & Count
## Contract: Clear removes items; count is approximate
## NOTE: clear() marked as {.deprecated: "untested".} per API spec

import ../../loony
import ../../loony/ward

# count() on empty ward returns 0
block:
  let q = newLoonyQueue[int]()
  let w = newWard[int](q, {})
  let c = w.count()
  doAssert c == 0

# count() after push reflects item count
block:
  let q = newLoonyQueue[int]()
  let w = newWard[int](q, {})
  discard w.push(1)
  discard w.push(2)
  discard w.push(3)
  let c = w.count()
  doAssert c == 3

# count() after pop decreases
block:
  let q = newLoonyQueue[int]()
  let w = newWard[int](q, {})
  discard w.push(1)
  discard w.push(2)
  discard w.push(3)
  let c1 = w.count()
  discard w.pop()
  let c2 = w.count()
  doAssert c2 < c1

# clear() with Clearable flag - empties queue
block:
  let q = newLoonyQueue[int]()
  let w = newWard[int](q, {Clearable})
  discard w.push(1)
  discard w.push(2)
  discard w.push(3)
  let before = w.count()
  doAssert before > 0
  w.clear()
  let after = w.count()
  doAssert after == 0

# clear() - queue operations work after clear
block:
  let q = newLoonyQueue[int]()
  let w = newWard[int](q, {Clearable})
  discard w.push(1)
  discard w.push(2)
  w.clear()
  discard w.push(3)
  discard w.push(4)
  doAssert w.pop() == 3
  doAssert w.pop() == 4

# count() - rough proportionality test
block:
  let q = newLoonyQueue[int]()
  let w = newWard[int](q, {})
  for i in 0..<100:
    discard w.push(i)
  let count100 = w.count()
  doAssert count100 > 0
  for _ in 0..<50:
    discard w.pop()
  let count50 = w.count()
  doAssert count50 < count100
  doAssert count50 > 0

# clear() - FIFO order after second batch
block:
  let q = newLoonyQueue[int]()
  let w = newWard[int](q, {Clearable})
  discard w.push(1)
  discard w.push(2)
  w.clear()
  discard w.push(100)
  discard w.push(200)
  doAssert w.pop() == 100
  doAssert w.pop() == 200
