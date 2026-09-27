# Native argv ownership evidence

The comparison uses frozen Debug compiler `685e2631` at
`d9-rc-integration/.tmp-rc/install-nbody/bin/mylang`, SHA256
`ed3dc4a72024b855272981ada0c4ff46e36bc7a6d3e58fd784a9835dfb5326fd`,
and the isolated argv fix built from that source in `d9-rc-argv-astra` at
`.tmp-argv/install/bin/mylang`, SHA256
`18a74046f8788f498af28c0f640c25b145fa8d28b50f2a4bece4b5debf8ef11e`.
Only the production argv constructor and entry adapter differ in generated
runtime behavior. The tests and documentation accompany that change.

`validate.py` and `lox.py` are the exact scripts used from the argv worktree.
They retain their original scratch paths so the raw command records remain
unambiguous. Recreate `.tmp-argv/driver/entry.my` from `inputs/entry.my` and an empty
`empty.txt` beside it before replay. The Lox runner reads the unchanged copied
port in `d9-rc-plain-replace-astra/.tmp-lox/port`; its input and source hashes are
preserved here, and the original corpus port remains in the performance tree.
Neither accepted GC binaries nor their immutable state were modified.

`minimal-before.json.gz` isolates argv from filesystem and output capabilities.
`validation.json.gz` contains before/after native entry controls and GC stress
controls; `lox.json.gz` contains the matched empty/usage/N4/N5 Lox runs. These
records preserve stdout/stderr, exit status, full counts, commands, source
compiler hashes, native binary hashes, and actual backend checks. LLVM commands
explicitly select `--backend=llvm --llvm-opt=3 --lto`.

The Lox N=4/N=5 inputs are diagnostics, not replacements for the required corpus.
No performance acceptance is inferred from this correctness fix.
