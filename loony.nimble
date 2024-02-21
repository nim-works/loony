version = "0.1.14"
author = "cabboose"
description = "Fast mpmc queue with sympathetic memory behavior"
license = "MIT"

task test, "run tests for ci":
  when defined(windows):
    exec """env GITHUB_ACTIONS="false" balls.cmd"""
  else:
    exec """env GITHUB_ACTIONS="false" balls"""
