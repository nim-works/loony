when defined(windows):
  import ./futex/futex_windows
  export futex_windows
else:
  import ./futex/futex_linux
  export futex_linux