version = "0.1.12"
author = "cabboose"
description = "Fast mpmc queue with sympathetic memory behavior"
license = "MIT"

requires "https://github.com/shayanhabibi/futexes < 1.0.0"

when not defined(release):
  requires "https://github.com/disruptek/balls >= 3.0.0 & < 4.0.0"
  requires "https://github.com/nim-works/cps < 1.0.0"

task test, "run tests for ci":
  when defined(windows):
    exec """env GITHUB_ACTIONS="false" balls.cmd"""
  else:
    exec """env GITHUB_ACTIONS="false" balls"""
