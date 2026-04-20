## Unit Tests: Ward Pause/Resume State Machine
## Contract: Pause/resume state machine transitions are well-defined

import ../../loony
import ../../loony/ward

type IntBox = ref object
  value: int

# pause() with Pausable flag sets paused state
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {Pausable})
  let wasPaused = w.pause()
  doAssert not wasPaused
  doAssert w.isPaused()

# resume() clears paused state
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {Pausable})
  discard w.pause()
  let wasPaused = w.resume()
  doAssert wasPaused
  doAssert not w.isPaused()

# pausePop() sets pop-paused state only
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {Pausable})
  let wasPaused = w.pausePop()
  doAssert not wasPaused
  doAssert w.isPopPaused()
  doAssert not w.isPushPaused()

# pausePush() sets push-paused state only
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {Pausable})
  let wasPaused = w.pausePush()
  doAssert not wasPaused
  doAssert w.isPushPaused()
  doAssert not w.isPopPaused()

# resumePop() clears pop-paused state
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {Pausable})
  discard w.pausePop()
  let wasPaused = w.resumePop()
  doAssert wasPaused
  doAssert not w.isPopPaused()

# resumePush() clears push-paused state
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {Pausable})
  discard w.pausePush()
  let wasPaused = w.resumePush()
  doAssert wasPaused
  doAssert not w.isPushPaused()

# pausePop() then pausePush() - both flags set
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {Pausable})
  discard w.pausePop()
  discard w.pausePush()
  doAssert w.isPopPaused()
  doAssert w.isPushPaused()
  doAssert w.isPaused()

# Calling pause twice on Pausable ward
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {Pausable})
  let first = w.pause()
  let second = w.pause()
  doAssert not first
  doAssert second  # Second call returns true (was paused)

# isPaused() reflects actual state
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {Pausable})
  doAssert not w.isPaused()
  discard w.pause()
  doAssert w.isPaused()
  discard w.resume()
  doAssert not w.isPaused()

# isPopPaused() reflects pop state
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {Pausable})
  doAssert not w.isPopPaused()
  discard w.pausePop()
  doAssert w.isPopPaused()
  discard w.resumePop()
  doAssert not w.isPopPaused()

# isPushPaused() reflects push state
block:
  let q = newLoonyQueue[IntBox]()
  let w = newWard[IntBox](q, {Pausable})
  doAssert not w.isPushPaused()
  discard w.pausePush()
  doAssert w.isPushPaused()
  discard w.resumePush()
  doAssert not w.isPushPaused()
