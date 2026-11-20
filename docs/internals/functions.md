# Functions and calls: how it works

Implementation detail moved out of the user guide, [functions.md](../functions.md). Each heading is the guide's heading.

## Freestanding functions

A failed check inside a freestanding function puts its code in the first argument register, the address of its source path in the second and its line in the third, and the target's trap instruction runs. The code's low byte is the trap kind the runtime numbers, and an assertion's clause is the next byte. On a device the bare runtime's fault handler (linked only into an image whose program has a freestanding fault; every other image keeps the plain handler) reads them from the stacked registers and reports `error[R_LIST_BOUNDS] PATH:LINE` and status 1, the form of a `--release` device build's traps. On x86-64 Linux the `ud2` is followed by the bytes `MYLF`, and a program that holds freestanding code installs a handler for `SIGILL` before `main`: it flushes the program's output as a trap does, prints `error[R_LIST_BOUNDS] PATH:LINE` on standard error with the trap's record, and exits with status 1, as a trap does; under `selka test` the test fails with the code. Any other illegal instruction keeps the default action, and a program with no freestanding code installs nothing, so its executable is unchanged.

A call from a freestanding function to C, by name or through an address, records no place and calls nothing before the jump: the `Host` token is compared inline with the value both runtimes give it.

After lowering, the emitted code of each freestanding function is checked to name no runtime symbol, counter or trap record; a compiler change that broke that is an internal error naming the function and the symbol.

## Code that runs from RAM

The image check tells code from data by the ARM mapping symbols (`$t`, `$d`) every Arm linker keeps, and decodes the Thumb instructions in the code. It is conservative: a word of the function's literal data whose value lies in flash is taken for an address. On QEMU the whole image is in RAM, and the check treats `.text` and `.rodata` as a device's flash, so a program proved there keeps the promise on a device. One exception: a failed check passes the address of its source path in `r1` and never reads it.

What counts as RAM is a section that is writable, that is loaded elsewhere than it runs (the device that copies its `.data` from flash), or that lies between `__data_start` and `__data_end`, the initialised data's extent every bare linker script defines. The last rule is for an image that runs from RAM, which the boot ROM loads straight into RAM: with no initialised variable its `.data` holds only `.ramfunc` code, which is neither writable nor loaded elsewhere. A script that puts `.ramfunc` in `.text`, or leaves it where the flash is, is still refused.

With the second core started, the two-core runtime is linked and the image check runs as for any other program. A freestanding function cannot take a function value, nor start a core. A `ram` function's own faults (`udf #83`) and its calls of `extern func`s, whose `Host` token is compared inline, call nothing in flash.

## Persistent function identity

The query can observe broader compilation dependencies than the ordinary rooted test key represents. Ordinary tests retain their existing reuse.
