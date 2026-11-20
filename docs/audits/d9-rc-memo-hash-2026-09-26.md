# WP-4 arena escape memo distribution

The frozen integration gate at `9192db49` completed its native RC arena wrapper
in 576.01 seconds. Sampling attributed essentially all active CPU time to the
linear probe in `native_rc_transfer.c:memo_at`. The half-full memo was finite,
but its pointer shift/xor hash left aligned arena and slab addresses clustered
after the power-of-two capacity mask.

The memo now avalanches the complete source address and destination region
before masking. The key, half-load reservation, rollback, and allocation-free
release contracts are unchanged. The regression adds a production-allocator
escape of 32,768 nodes separated by 2 KiB arena allocation strides, alongside
the existing million-node arena chain and shared-graph cases.

The focused Debug `test-units` arena wrapper completed in 2.46 seconds with all
12 selected/import tests passing. Its ten C scenarios also passed strict C
warnings, AddressSanitizer and UndefinedBehaviorSanitizer. The existing focused
native RC contract wrapper passed 12/12 in 0.99 seconds. These timings establish
that the gate regression is resolved; they are not the matched WP-4 application
performance acceptance run.
