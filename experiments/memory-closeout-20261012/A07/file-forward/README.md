# Builtin file results through borrowing helpers

The direct Result[TextFile, str] / Result[BinaryFile, str] carrier shares the
bounded one-provider origin rule. This does not change ordinary borrowed file
parameters to consuming parameters. Fresh file acquisition and forwarding helpers
preserve the named provider until the receiving with scope closes; local-provider
escape still refuses. Other file/capability aggregate storage remains unsupported.

The focused test `zero RC builtin file` passed in unoptimized and verified release
execution with leak and LLVM RC checks, including an @ensures wrapper, normal and
early error returns, and a local-provider escape refusal. Development evidence used
the worker tree with a separate pending list-slot source-admission patch; no slot
writeback paths occur in this regression. Integrated qualification must rerun it.
