type
  NodePtr* = uint
  TagPtr* = uint   # Aligned pointer with 12 bit prefix containing the tag. Access using procs nptr and idx
  ControlMask* = uint32
