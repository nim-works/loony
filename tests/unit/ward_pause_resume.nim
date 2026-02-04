## Unit Tests: Ward Pause/Resume State Machine
## Contract: Pause/resume state machine transitions are well-defined

import balls
import ../../loony
import ../../loony/ward

suite "Ward Pause/Resume State Machine":
  
  test "pause() with Pausable flag sets paused state":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    
    let wasPaused = w.pause()
    assert not wasPaused
    assert w.isPaused()
  
  test "resume() clears paused state":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    
    discard w.pause()
    let wasPaused = w.resume()
    assert wasPaused
    assert not w.isPaused()
  
  test "pausePop() sets pop-paused state only":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    
    let wasPaused = w.pausePop()
    assert not wasPaused
    assert w.isPopPaused()
    assert not w.isPushPaused()
  
  test "pausePush() sets push-paused state only":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    
    let wasPaused = w.pausePush()
    assert not wasPaused
    assert w.isPushPaused()
    assert not w.isPopPaused()
  
  test "resumePop() clears pop-paused state":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    
    discard w.pausePop()
    let wasPaused = w.resumePop()
    assert wasPaused
    assert not w.isPopPaused()
  
  test "resumePush() clears push-paused state":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    
    discard w.pausePush()
    let wasPaused = w.resumePush()
    assert wasPaused
    assert not w.isPushPaused()
  
  test "pausePop() then pausePush() - both flags set":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    
    discard w.pausePop()
    discard w.pausePush()
    
    assert w.isPopPaused()
    assert w.isPushPaused()
    assert w.isPaused()
  
  test "Calling pause twice on Pausable ward":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    
    let first = w.pause()
    let second = w.pause()
    assert not first
    assert second  # Second call returns true (was paused)
  
  test "isPaused() reflects actual state":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    
    assert not w.isPaused()
    discard w.pause()
    assert w.isPaused()
    discard w.resume()
    assert not w.isPaused()
  
  test "isPopPaused() reflects pop state":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    
    assert not w.isPopPaused()
    discard w.pausePop()
    assert w.isPopPaused()
    discard w.resumePop()
    assert not w.isPopPaused()
  
  test "isPushPaused() reflects push state":
    let q = newLoonyQueue[int]()
    let w = newWard[int](q, {Pausable})
    
    assert not w.isPushPaused()
    discard w.pausePush()
    assert w.isPushPaused()
    discard w.resumePush()
    assert not w.isPushPaused()
