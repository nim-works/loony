version = "0.0.1"
author = "cabboose"
description = "fast mpmc queue with sympathetic memory behavior"
license = "MIT"

when not defined(release):
  requires "https://github.com/disruptek/balls >= 3.0.0 & < 4.0.0"

requires "https://github.com/disruptek/cps < 1.0.0"

task test, "run tests for ci":
  when defined(windows):
    exec "balls.cmd"
  else:
    exec findExe"balls"
