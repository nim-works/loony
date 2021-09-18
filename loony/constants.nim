const
  ## Slot flag constants
  UNINIT*   =   uint8(   0   ) # 0000_0000
  RESUME*   =   uint8(1      ) # 0000_0001
  WRITER*   =   uint8(1 shl 1) # 0000_0010
  READER*   =   uint8(1 shl 2) # 0000_0100
  CONSUMED* =  READER or WRITER# 0000_0110

  SLOT*     =   uint8(1      ) # 0000_0001
  DEQ*      =   uint8(1 shl 1) # 0000_0010
  ENQ*      =   uint8(1 shl 2) # 0000_0100
  #
  N*        =         1024     # Number of slots per node in the queue
  #
  TAGBITS*   : uint = 11             # Each node must be aligned to this value
  NODEALIGN* : uint = 1 shl TAGBITS  # in order to store the required number of
  TAGMASK*   : uint = NODEALIGN - 1  # tag bits in every node pointer
  PTRMASK*   : uint = high(uint) xor TAGMASK
  # Ref-count constants
  SHIFT* = 16      # Shift to access 'high' 16 bits of uint32
  MASK*  = 0xFFFF  # Mask to access 'low' 16 bits of uint32
  #
  SLOTMASK*  : uint = high(uint) xor (RESUME or WRITER or READER)
