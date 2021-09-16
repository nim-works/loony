# Loony

This is just my attempt to do the base translation of the algorithm from ["Fast and Portable Concurrent FIFO Queues With Deterministic Memory Reclamation" by Giersch & Nolte](papers/GierschEtAl.pdf).

I originally just wanted a high throughput MPMC queue for [CPS](https://github.com/disruptek/cps) since that is already such a great avenue for concurrency. Disruptek thinks it is worth recreating. This experiment will be handed off to the cps team when most of the basic rubbish is done and tested.

- [Benchmarks](https://github.com/oliver-giersch/lfqueue-benchmarks/tree/master/lib)
- [c++ impl](https://github.com/oliver-giersch/looqueue/tree/master)
- [Algorithms](https://github.com/oliver-giersch/looqueue/blob/master/ALGORITHMS.md)

---
