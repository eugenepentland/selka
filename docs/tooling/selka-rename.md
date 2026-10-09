# Moving from mylang to Selka

Selka is the language's chosen name. The compiler and current examples now use
the new spelling throughout.

| Before | Now |
| --- | --- |
| `mylang` executable | `selka` |
| `main.my` source | `main.selka` |
| `mylang.json` project configuration | `selka.json` |
| `.mylang-cache/` project cache | `.selka-cache/` |
| `~/.cache/mylang/` shared cache | `~/.cache/selka/` |
| `MYLANG_*` environment variables | `SELKA_*` |
| `MYL_CORE_*` runtime instrumentation | `SELKA_CORE_*` |
| `.myi` generated module interfaces | `.selkai` |
| `mylang` documentation fences | `selka` |
| `# doc: not-mylang` prose marker | `# doc: not-selka` |

For an existing project, rename its source files and configuration, then update
source paths in scripts, test-case provider maps, generated-input manifests, and
editor settings. Imports use module names, so `import pricing` remains the same
after `pricing.my` becomes `pricing.selka`. A sibling `pricing.cases.json` or
`pricing.api` keeps its name. Regenerate interface files and lock/build receipts
with the new compiler.

Update environment settings such as `SELKA_ZIG`, `SELKA_JOBS`,
`SELKA_MEMORY_LIMIT`, and `SELKA_OPTIONS`. Fresh builds use the new cache
directories; old cache data is not needed and is not deleted automatically.
The executable and project discovery use the Selka names; this is a coordinated
rename, with no second installed executable or old configuration fallback.

```bash
selka check main.selka
selka build main.selka -o app
selka test tests/
```

Dated experiment archives, audit reports, and benchmark results retain their recorded names,
paths, commands, and hashes. They describe the compiler that produced them. The old `# doc: not-mylang`
prose exclusion remains recognized so those reports need no edits.
The recorded stage-0 pin also keeps its original artifact identity; rebuild and
re-pin it before using the renamed self-hosting sources. The checkout directory
itself can have any name.
