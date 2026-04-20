## Unit Tests: Queue Creation & Basic Operations
## Contract: Items enqueued are dequeued in FIFO order

import ../../loony

type
  IntBox = ref object
    value: int
  StringBox = ref object
    value: string

# Test: newLoonyQueue creates valid queue
block:
  let q = newLoonyQueue[IntBox]()
  doAssert q != nil

# Test: push then pop returns same element
block:
  let q = newLoonyQueue[IntBox]()
  let obj = new IntBox
  obj.value = 42
  q.push(obj)
  let popped = q.pop()
  doAssert popped.value == 42

# Test: multiple push/pop maintains FIFO order
block:
  let q = newLoonyQueue[IntBox]()
  var boxes: seq[IntBox] = @[]
  for i in 1..5:
    let b = new IntBox
    b.value = i
    boxes.add(b)
  for b in boxes:
    q.push(b)
  for b in boxes:
    let popped = q.pop()
    doAssert popped.value == b.value

# Test: works with string ref type
block:
  let q = newLoonyQueue[StringBox]()
  let strs = @["hello", "world", "test"]
  for s in strs:
    let box = new StringBox
    box.value = s
    q.push(box)
  for s in strs:
    let popped = q.pop()
    doAssert popped.value == s

# Test: FIFO holds across batches
block:
  let q = newLoonyQueue[IntBox]()
  # Batch 1
  for i in 1..3:
    let b = new IntBox
    b.value = i
    q.push(b)
  for i in 1..3:
    doAssert q.pop().value == i
  # Batch 2
  for i in 4..6:
    let b = new IntBox
    b.value = i
    q.push(b)
  for i in 4..6:
    doAssert q.pop().value == i

# Test: alternating push and pop maintains FIFO
block:
  let q = newLoonyQueue[IntBox]()
  var b1 = new IntBox
  b1.value = 1
  var b2 = new IntBox
  b2.value = 2
  var b3 = new IntBox
  b3.value = 3
  q.push(b1)
  q.push(b2)
  doAssert q.pop().value == 1
  q.push(b3)
  doAssert q.pop().value == 2
  doAssert q.pop().value == 3

# Test: large number of sequential operations (1000)
block:
  let q = newLoonyQueue[IntBox]()
  let itemCount = 1000
  for i in 0..<itemCount:
    let b = new IntBox
    b.value = i
    q.push(b)
  for i in 0..<itemCount:
    let v = q.pop()
    doAssert v.value == i

# Test: safe vs unsafe variant compatibility
block:
  let q = newLoonyQueue[IntBox]()
  let b1 = new IntBox
  b1.value = 10
  let b2 = new IntBox
  b2.value = 20
  q.push(b1)
  q.unsafePush(b2)
  discard q.pop()
  discard q.unsafePop()

echo "queue_basics: all tests passed"
