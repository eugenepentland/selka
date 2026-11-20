# Proofs in Selka (concept note, 2026-10-22)

Status: **concept only, not scheduled.** The user raised it on 22 October as an idea for after self-hosting
(roadmap stream H). Nothing here is planned or implemented. This note records the shape of the idea so a later plan
can start from it.

The question: could Selka let a program carry proofs? Two examples:
- "the compiler has no use-after-free";
- "no part of the website reads this data without an authenticated user".

## Why Selka is well placed

The hard part of proving things about ordinary programs is aliasing (two names for one piece of mutable memory) and
hidden effects. Selka already removed most of both:
- checked ownership with no stored references, so `mut` borrows are exclusive and plain borrows are read-only;
- no closures, no methods and no dynamic dispatch, so the call graph is exact;
- no ambient authority: files, network, clock, entropy and environment arrive as capability parameters on `main`;
- contracts already exist (`docs/contracts.md`): `@requires`, `@ensures` with `old(...)`, and `@invariant`, checked at
  run time in every build;
- a Core IR verifier, and the `--verify-facts` mode that checks Core's facts at run time.

Verifiers for C or Java spend most of their effort on aliasing. Prusti and Verus lean on Rust's borrow checker for the
same reason, and Selka's value semantics give a similar head start.

## Three tiers

### Tier 1: properties the checker already proves (use-after-free, data races)

For Selka code, the ownership checker *is* the proof: any program it accepts has no use-after-free. A self-hosted
compiler gets that guarantee for its own Selka source automatically.

What a proof would still trust:
- the checker's soundness, and Core's lowering;
- the C runtime (about 11k lines), LLVM, `zig cc` and the OS;
- any `extern func` C code.

Ways to shrink that trusted base:
- **A soundness proof of the ownership rules.** A formal model of them, proved sound, as RustBelt did for Rust; the
  rules are close to Hylo's mutable value semantics, which has formal treatments. Research-scale, but bounded.
- **Validating each build instead of the compiler.** Check every compiled program's Core IR for the ownership
  invariants, in the style of proof-carrying code. The Core verifier is a start: on 22 October it caught a real
  release-build bug (the `lists.extend` view call) that release builds had hidden. The subsection below explains why
  this beats proving the compiler.

Limit: a stale pool handle is caught by a run-time generation check, not ruled out statically. Proving that no stale
handle is ever used is a separate, harder property.

#### Prove the compiler once, or check each build? (clarified 22 October)

"Check each build" means a check **at compile time, not at run time**. The compiler checks the IR it produced before
emitting code. A finished program carries no extra checks and runs no slower; the cost is a fraction of build time.

Three separate properties hide in "the compiler is safe":
1. **The compiler's own code has no use-after-free.** That is free once the compiler is written in Selka, because the
   checker guarantees it for any Selka program.
2. **The rules are sound:** if the checker accepts a program, that program is safe. This needs a proof of the
   ownership rules, done once.
3. **The compiler preserves that** when it lowers the program to Core IR and LLVM.

For the third, there are two routes.
- **A verified compiler.** Prove the whole compiler correct, so no build ever needs checking. CompCert (a subset of C)
  and CakeML (ML) did this. It is the strongest guarantee and the most expensive:
  - CompCert took about six person-years for a small, fixed language, and Selka's compiler is 288k lines;
  - every compiler change needs its proof updated, so the compiler either freezes or every change becomes slow;
  - LLVM is not verified, so the proof would stop at the LLVM IR Selka hands it.
- **Translation validation.** Don't prove the compiler always right; check each output with a small, stable
  validator, for example that every value is used only while its owner is alive and never after it is dropped.
  - A validator is a few thousand lines, so it can be proven itself.
  - The compiler stays free to change, because a bug that produces unsafe code fails the build instead of shipping.
  - CompCert itself validates some of its passes, register allocation for one, instead of proving them.

Why the third property matters: the `add_wire` bug found on 22 October was not a checker mistake. The source program
was correct and the checker rightly accepted it, but the lowering emitted a call with the wrong argument shape, which
was undefined behaviour in release builds. A soundness proof of the rules would not have caught it; the Core IR
verifier did, in debug builds.

The sensible combination is a one-time soundness proof of the rules plus a validator run on every build. Proving all
288k lines is out of proportion.

### Tier 2: properties expressed as types ("no data access without auth")

No prover is needed. This extends the capability pattern Selka already uses for `Filesystem` and `Network` to
capabilities a program defines itself:

```text
auth module:   public type AuthedUser          (only this module can construct one)
               public func login(...) -> AuthedUser fails AuthError
data module:   public func read_record(user: AuthedUser, id: RecordId) -> Record
               (every function that touches protected data takes the capability)
```

Every path to `read_record` must then hold an `AuthedUser`, and only `login` makes one, so "accessed without auth" is
a compile error, not a missed test.

**A capability is just an unforgeable record** (clarified 22 October). "Capability" names a pattern, not a special
kind of value: a value whose possession *is* the permission. Selka's `Filesystem` is exactly that, a value only the
runtime can create, passed explicitly.
- **What a plain record lacks is unforgeability.** Today any module that imports `auth` could write
  `AuthedUser(id=5)` and skip `login`, because a `public record`'s constructor is open to importers. Holding one would
  then prove nothing.
- **The fix is privacy, not a new kind of type.** Keep the constructor and the fields private to the defining module.
  Then the only way to get an `AuthedUser` is to call `login`, so any function that takes one provably runs after a
  login.
- **Generic construction must respect privacy.** Anything that builds records generically must not forge one: a JSON
  decoder, a derived codec, a test helper. The old schema work already treated opaque types as untouchable by codecs,
  so the rule has a precedent.
- **No hidden channels.** Selka has no globals and no closures, so a token cannot sneak around through hidden state.
  Every function that needs it takes it as a parameter, which is also what makes the audit query below possible.

What Selka would need:
- **Opaque public types.** Today a `public record` can be constructed by any importer, and a private type cannot
  appear in a public signature (`docs/modules.md`). The addition is a public type whose constructor and fields stay
  module-private. It is small and additive.
- **Move-only capabilities, optionally.** Resources are already move-only (`own`/`mut`), so a capability can be made
  impossible to copy or stash.
- **Information flow, optionally.** A `Secret[T]` wrapper that only a capability can open, so protected data cannot
  reach an unauthenticated response.
- **An audit query.** With an exact call graph, a tool could list every path from each entry point (an HTTP handler,
  say) to a protected function, and the capabilities that guard it. It is cheap to build and useful in security
  review.

### Tier 3: general functional properties ("the router never returns an invalid path")

A `mylang prove` that discharges contracts statically with an SMT solver, as Dafny, Prusti and Verus do, opt-in per
function. Value semantics keep the proof obligations simple, with no heap aliasing in them.

The payoff beyond correctness: a proven `@requires(i < len(xs))` makes the matching bounds check redundant. That is
the one route to checked code that runs as fast as unchecked code without ever writing unchecked code. Roadmap item
D4 (22 October) measured the stakes: bounds and overflow checks are about half of the K2 kernel's SIMD instructions.

Costs:
- a large tool;
- loop invariants and other annotations to write. Agents are reasonably good at these when the prover reports what
  failed.

It must stay opt-in, never required, so it does not work against the agent-speed goal.

## Caveats

- A proof is only as good as its specification and its trusted base. "Auth everywhere" proves the type discipline,
  not that `login` checks passwords correctly.
- Proof tooling must not slow the edit loop (roadmap R-5): run it on request or in the gate, never on every check.

## Where it could fit

| Tier | Earliest sensible start | Size |
| --- | --- | --- |
| 2: capability types and the audit query | after the language freeze (roadmap G2), as an additive feature | small |
| 3: `mylang prove` over contracts | after self-hosting stage 1 or later; the compiler would be its largest test subject | large |
| 1: soundness proof of the ownership rules | any time; research work, independent of the roadmap | research-scale |

## Open questions

- Should opaque types be a new declaration form or a visibility modifier on fields?
- Is a proven contract allowed to remove its run-time check by default, or only on request?
- Which solver, and how are its versions pinned (no Python in the toolchain, a pinned Zig)?
- How do proofs interact with the caches (a proof as a cached, content-keyed artifact)?
