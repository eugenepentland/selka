# Declaration indexing component

This component indexes one already-parsed module. It does not lex, parse, check
signatures, or check bodies. The host supplies compact AST declaration facts,
ordered parsed imports/exports/public spans, source context, and indexed symbol
metadata for distinct direct dependency targets. The Selka algorithm owns
category order, local/domain names, duplicate/import conflicts, export
visibility, canonical facade identities, and import-use flags. All names stay
raw bytes; the seed's component-v1 feature profile and pins remain unchanged.

`model.my` defines the typed projection and result; `indexing.my` implements the
pure algorithm; `indexed.my` supplies immutable byte-name indexes and source
locations; `codec.my` validates bounded frames and serializes results;
`main.my` alone accesses files and streams. Pure tests are in `tests.my` and
`indexed_tests.my`. Indexed arrays retain insertion IDs, so binary search does
not change declaration order or which previous declaration a diagnostic cites.

## Native behavior preserved

Declaration categories are record, domain, variant, resource, alias,
constraint, function (0 through 6). Each category retains its own AST order;
kinds are type=0, function=1, constraint=2. Owned functions use `owner.name`.
Duplicate names precede import alias conflicts; imports' full module names do
not conflict with unowned declarations. Export directives run in source order:
a facade first resolves its imported target and checks privacy, then detects a
local duplicate. The first matching import alias OR full module name wins.
Re-export targets can be types, functions or constraints; a facade retains an
already-canonical defining identity, including one outside direct dependencies.

Public declarations are applied after export directives. A plain export of an
already-public declaration is `E_DUPLICATE_EXPORT`; repeated plain exports of
an ordinary declaration remain admitted. Owned functions finally inherit their
owner's export flag unless restricted. The existing native test-module private
visibility exception applies only when the requester is named `<target>_test`
and no module imports it. The host retains graph parse order and all later
interface/signature checking and body checking.

The result is either the exact symbol list and import-use flags, or the first
native problem, with code, static message, local site and optional related
module/span. A source problem is a successful binary response (exit 0).
Malformed/profile/process failures emit no response and exit 2. No hidden
native fallback or source reparsing occurs in the producer.

## Protocol and bounds

Invoke `declaration-index --exchange FILE`; `--request FILE` accepts the inner
payload for standalone qualification. Outer magic is `SLKDIX01`. The 64-byte
header has little-endian u32 protocol=1/schema=1/direction=0(request) or1(reply)/
payload-length at offsets8/12/16/20, opaque nonce8 at24 and SHA25632 at32.
Replies echo bytes24..64 unchanged. The host authenticates the package, seals
its executable, binds the full request digest, and validates returned facts.
The producer validates framing and treats correlation bytes as opaque.

Every scalar below is little-endian u32. A blob is length followed by raw bytes;
a span is start/end, half-open. The request is:

- `SLKDCL01`, module ID, is-imported boolean, module-name blob, path blob,
  trusted-intrinsics boolean, source blob;
- five counts: declarations, imports, exports, public spans, dependencies;
- declaration rows: category, name span, owner-present boolean, owner span,
  restricted boolean. Absent owner span must encode0/0;
- import rows: full-name blob, alias blob, span, target module ID;
- export rows: name blob, alias-present boolean, optional nonempty alias blob,
  directive span;
- public spans;
- dependency rows: module ID, module-name blob, source byte length, symbol count,
  then symbol rows.

A symbol row is name blob, kind, span, exported boolean, owner-present boolean,
optional nonempty owner blob, restricted boolean, origin-present boolean,
optional canonical module/symbol IDs. Dependency IDs must be distinct and must
be exactly targets of direct imports. Existing dependency names are unique.
Alias/full-name collisions retain first-import behavior. The graph facts
`is-imported` and source/trust/path are explicit, never inferred from ambient
state. Canonical origins may identify previously built transitive modules not
serialized in this request; the host checks those identities against its index.

Replies begin `SLKDCR01`, then status. Status0 has symbol count, import-use count,
symbol rows, then boolean use flags in original import order. Status1 has code
blob, message blob, site(module/span), related-present boolean, optional related
site. Empty success is exactly20 bytes. Diagnostic prose is the fixed ASCII
native catalog; name and source bytes never need UTF8 conversion.

Both complete framed messages are bounded by32MiB (inner payload32MiB minus64).
Source is at most1MiB, path16KiB; declarations plus facade keys at most65536;
imports and dependency units4096 each; exports/public spans65536 each;
aggregate dependency symbols65536. Aggregate input name bytes are at most1MiB:
module name, import/export names and aliases, dependency names and symbol names
and owners, plus generated local declaration/facade key names. Path/source have
separate bounds. Reply owners can repeat prefixes already counted in keys; the
host allows2MiB aggregate reply strings while binding each to admitted facts.
All local/dependency spans and flags are validated before indexing. Input
mutation and earlier output snapshots obey ordinary value semantics.

## Qualification

Use the coordinator-verified component-v1 seed and run through
`scripts/build-slot.sh build`, with private disk TMPDIR/worktree-local Zig
cache/shared global cache. Run `seed test tests.my --force --no-cache`, then
repeat with `--release --verify-facts` and `MYL_CORE_LEAKCHECK=1`. The native
adapter and workflow driver separately qualify framed malformed inputs,
exact symbols/problems/import flags, sealed deployment, graph workflows and
artifact edits. To test an operational producer edit, the private copy can
insert a dynamic `request.context.name` branch immediately after the public
`indexing.index` signature; this changes executable behavior for an unused
private marker without reserving a production module name.
