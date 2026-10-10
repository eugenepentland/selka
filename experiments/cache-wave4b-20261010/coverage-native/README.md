# Real libFuzzer adapter smoke

The supplied executable used LLVM 19 libFuzzer with actual inline 8-bit counters emitted by the pinned Zig compiler. Exploration certified exactly 32 executed units, with six counters and five observed PCs. Fixed-input replay certified all four exported raw inputs. This qualifies the coverage worker against a real engine on a small native fixture; it does not establish compiler fuzz coverage.

[provenance.json](provenance.json) records the official Ubuntu package URL, version and SHA256, exact successful commands, source/executable/runtime hashes, original input and local executable paths. The archive was downloaded and extracted beneath ignored `.mylang-cache`; nothing was installed system-wide. No executable, archive or package is tracked here. The fixture is [libfuzzer_target.c](../../../test/fixtures/fuzz-campaign/libfuzzer_target.c).

The first attempt with `zig cc -fsanitize=fuzzer` alone failed because no libFuzzer `main` was linked. Linking the extracted runtime with `-lstdc++` selected Zig's libc++ and produced ABI errors. The recorded successful command explicitly links `/usr/lib/x86_64-linux-gnu/libstdc++.so.6`. Three runtime warnings concern missing sanitizer stack/death callbacks; this smoke does not enable ASan.

The small result, corpus and log files preserve the original evidence. Result artifact references are relative to their original ignored worker directories; the corresponding logs are copied here with an `explore-` or `replay-` prefix. Reproduction must use fresh output directories. Copy the tracked fixture back to the recorded ignored source path to reproduce its debug source pathname; a different pathname can change the executable hash.
