# Evaluation dependency reports

`eval-project --evaluation-report` emits a deterministic JSON receipt after successful
restricted evaluation. Without the flag, the command keeps its scalar stdout format.

```sh
zig build
zig-out/bin/selka eval-project examples/modules/main.selka --evaluation-report
```

The eval-report-v1 document contains a request, its SHA-256 digest, and a result.
The result has type `i64` and a decimal string, preserving the complete signed 64-bit
range for JSON consumers that use floating-point numbers.

## Request identity

The eval-request-v1 request records:

- The entry logical module and effect-free/parameter-free evaluation policy version.
- SHA-256 of the running compiler executable, the pinned Zig version, host architecture,
  operating system, ABI, and optimization mode.
- Instruction, frame, and VM-allocation budgets.
- Every loaded source's logical module, relative path, exact byte count, content hash,
  and ordered imports with resolved module names and aliases.

Sources appear once in deterministic dependency-first order; imports retain declaration
order. Digests describe the retained source bytes actually used by this compilation,
including comments and uncalled declarations. Unrelated files are excluded. This
conservative identity treats source-only edits and alias changes as different requests,
even if the computed value remains equal. Relative module paths permit relocating an
otherwise identical project without changing its request.

The request digest hashes its compact JSON encoding in the declared field order,
without whitespace or a trailing newline. It excludes the result and outer report
fields. This is a versioned encoding contract, not arbitrary JSON normalization.
Compiler executable bytes make implementation/build changes invalidate the request;
the same source tree rebuilt into different executable bytes can therefore produce
a different identity. Host metadata describes this evaluator build, not a separately
selected cross-compilation target.

## Failure and ownership

The CLI completes checking and evaluation before rendering a report. Source errors,
authority rejection, runtime traps, and exhausted budgets emit no partial JSON result.
The report option is exclusive to eval-project and cannot be repeated. Hashing the
running executable uses the host's executable handle API; failure is a host error,
with no fallback identity based on a filename or unchecked version string.

The embedding renderer accepts an already completed project, a successful value,
budgets, and caller-supplied implementation identity. The caller is responsible for
having performed the corresponding evaluation. It rejects incomplete graphs and
invalid budgets, owns temporary serialization storage, and returns caller-owned JSON.
The CLI supplies the identity of its actual running executable.

This records dependency inputs and a request identity; it does not look up or write a
cache, measure saved compilation work, accept external data manifests, generate
schemas/bindings, or explain an incremental rebuild. Those remain separate pending
steps in F.

## Acceptance

The actual-CLI report driver recomputes request, compiler, and source hashes using
Python's independent JSON/SHA-256 implementations. It checks repeatability, exact
maximum-i64 output, imports/aliases, budgets, relocation, unrelated-file exclusion,
source-only edits, alias edits, and suppression of reports on source/runtime/memory
failures. Unit tests cover shared dependency membership, minimum-i64 output, changed
compiler identity, invalid inputs, and every allocation failure through rendering and
parsing with cleanup. Both Debug and ReleaseFast run the driver in zig build test.

## Request identity before execution

`eval-project --evaluation-request` loads, checks, and lowers the project, validates
bytecode within the evaluation allocation budget, and checks the same entry authority
and transitive effect restrictions. It then emits eval-request-document-v1 with
`evaluation: "not-executed"`, the request, and its digest. There is no result field.
The request encoding and digest are identical to those in a successful evaluation
receipt for the same sources, compiler executable, and budgets.

This mode does not run the entry or establish that execution will terminate, fit its
budgets, or avoid guest traps. A recursive entry or division by zero can produce an
eligible request. Type errors, forbidden authority/effects, and insufficient bytecode
validation allocation space still reject without partial JSON. Step/frame limits
are recorded but not consumed by guest execution. Report and request flags are
mutually exclusive, and duplicate/wrong-command flags reject as usage errors.

The embedding `evaluation.preflight` returns null for eligibility or a validation
budget diagnostic, with semantic and host errors retaining their existing channels.
It shares the evaluator's preparation path, stopping before the VM runner. Request
rendering and successful report rendering share their encoding implementation.

Tests establish request/report digest equality, absence of a fabricated result,
request generation for trapping/nonterminating programs even at one instruction and
one frame, unchanged authority rejection, allocation-failure cleanup, and option
exclusivity in both orders. This supplies the lookup input for future cache reuse;
there is still no persistent cache or incremental compilation in this command.

The separate [evaluation cache driver](evaluation-cache.md) now uses request-only
lookup to reuse successful results. Compiler commands themselves remain cache-free.
