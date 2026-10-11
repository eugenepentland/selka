# Genuine guest runtime modes

The text, comprehension and iteration admission harnesses now run ordinary guest executables by default and add `--release --verify-facts` only with `--release`. Leak checks remain enabled in both modes. Previously the option changed receipt metadata only, while every runtime used release/fact flags.

The newly covered ordinary runtime path passed all original fixtures: text 117 operations, comprehension 294, iteration 228, with zero failures or skips. Each fixture still compares native, shadow and component checks and typed graphs before runtime. The earlier text-method evidence archive proves release/facts/leak execution with the identical host, producer and cases. No label-only duplicate is counted; its queued cancellation performed zero compiler operations. The exact UTF-8 wrapper was incidentally repeated with its previous release commands and contributes no additional default-path coverage.
