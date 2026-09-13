# Module header discovery

The first part of track M loads a bounded dependency graph. It does not yet compile
multi-file programs. `check`, `run`, formatting, and quality commands still accept
the existing single-file grammar; they do not ignore imports.

```sh
zig build run -- list-modules examples/modules/main.my
```

Each file begins with a matching logical module name and optional imports.
Explicit `export Name;` directives may appear anywhere among the following
top-level declarations:

```mylang
# doc: skip fragment: header excerpt whose imported modules are not shown
module main;
import shared.units;
import shared.types as types;
```

The CLI takes an `identifier.my` entry file. Its containing directory is the
project root; `shared.units` maps to `shared/units.my` below that directory.
Module segments and aliases use ordinary ASCII identifiers (language keywords
are reserved). Whitespace/comments may separate header tokens. An omitted alias
uses the last module segment. Repeated aliases and repeated imports, even with
different aliases, are errors. File declarations must match their requested name.
Slashes, absolute paths, empty segments, and traversal are not logical names.
Filesystem symlinks follow host behavior; this is not a filesystem sandbox.

The embedding `project.Project` accepts a provider for relative paths. The provider
returns bytes owned by the supplied allocator and honors a read limit; the loader
also checks the returned length. The project owns copied source buffers and spans
until deinitialization. It loads each logical module once, uses iterative DFS,
rejects cycles, and emits dependency-first order using source import order to
break ties. A diamond's shared dependency is read once. Related diagnostics retain
their own file and source location. Failed or unfinished loads cannot render a
successful graph, and a Project is loaded only once.

Default limits are 256 modules, 4,096 import edges, 4 MiB per source, and 16 MiB
combined source bytes. Embedders may override these limits. They bound logical
inputs, not all host allocations. Allocator exhaustion propagates as OutOfMemory;
project destruction releases partial construction. CLI source/header/read failures
exit 1 with no partial stdout graph; usage and host failures exit 2.

The report identifies itself as `module graph v1; header discovery only;
bodies/exports/types not checked`, followed by normalized paths, whole-file SHA-256
digests, and direct imports. These are content fingerprints, not a persistent
cache or proof of semantic equivalence. The entire source is lexed; the loader parses the leading imports and scans
top-level declaration boundaries for exports, checking duplicate export names.
Nested bodies are skipped. Body syntax, misplaced imports, export targets,
references, and type validity are not checked by this command. The separate [interface command](module-interfaces.md)
parses bodies and checks export targets and signature visibility.

Acceptance includes actual multi-file CLI execution, shared dependency loading,
source ordering and deterministic reports, body-sensitive digests, missing sources,
malformed headers, duplicate imports/aliases, direct and indirect cycles with
cross-file diagnostics, module/import/source limits, unsafe path rejection, a
600-module chain, and exhaustive allocation failures on both successful discovery
and diagnostic rendering.

Module parsing, export lists, and declaration visibility now have an
[interface index](module-interfaces.md). [Cross-file execution](module-execution.md)
now integrates its identities with semantic resolution and private access in bodies. Dependency
direction policy is separate from type validity. Module-aware formatter, reference
roots, duplicate identities, native support, and incremental invalidation remain
part of their respective roadmap requirements.
