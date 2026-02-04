import std/[locks, os]
import std/atomics
import loony

type
  Message = ref object
    value: string

let fifo = newLoonyQueue[Message]()
var terminate: Atomic[bool]


proc producer() {.thread.} =
  for i in 1..10:
    let msg = Message(value: "Message " & $i)
    # don't try to access msg after depositing it in the queue (!)
    echo "Producing ", repr(msg)
    fifo.push msg
    sleep(100)

proc consumer() {.thread.} =
  while not terminate.load:
    let item = fifo.pop
    if not item.isNil:
      echo "Consumed: ", repr(item)
    sleep(10)

# Create worker threads
var producerThread, consumerThread: Thread[void]

# Start worker threads
createThread(producerThread, producer)
createThread(consumerThread, consumer)

joinThread(producerThread)
terminate.store(true)
joinThread(consumerThread)
