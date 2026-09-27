# Combined nbody gate: callable-name failure retained

Frozen `685e26311935cea0697726614a3897baff4f286f` joins the four nbody/plain-value
refinements. Its full gate is **not green**. The main gate completes 92/94 steps,
with one failed guest-driver step; its 2,272 executed unit/CLI tests pass.
QBE passes 438/438 tests, native build passes 29 steps, and formatting passes two.

Both uncached RC sweeps execute and pass 865 assertions across 148 programs,
with zero failed assertions, skips or cached verdicts, but each **drops one file**:
`tests/lang/rc_plain_replacements.my`. Test discovery exits 2 with `InternalError`
in `module_names.Names.reference`. The parser permits a declared function named
`replace`; the module resolver's lexical name qualification rejects that token.
The new permanent fixture exposed this distinction from standalone execution.
The complete failed logs and dropped-file JSON remain unchanged in the
[archive](../../experiments/d9-rc-nbody-gate-20260926/README.md).

The immutable Debug compiler has SHA-256
`ed3dc4a72024b855272981ada0c4ff46e36bc7a6d3e58fd784a9835dfb5326fd`.
The resolver fix is being validated separately; this failed checkpoint must not
be relabeled as passing after that fix. Supplemental golden replay continues on
the older immutable `19e16e1d` compiler. WP-4 performance acceptance remains open.
