import VerifyIr.Check

/-!
# A union payload is read only under its own tag (F-VL-10)

The Lean copy of `src/core/verify_union_tags.zig`: a forward must-analysis of what each block's entry knows of union tags,
and the rule that every `union_payload k` and `union_take k` of a reached block reads a value whose tag the facts confine
to `k`.

* A *key* is the canonical value (through copies and `borrow`) a `union_tag` reads, or a `list_get_field` register whose
  path ends at a union's tag. A fact says which cases a key's tag can be (a mask), or that two keys' tags are equal.
* A `union_make` of case `j` can only be `j`; a union of one case only its case.
* On the edges of a `branch` on `cmp eq|ne` of a tag and a constant, the tag is the constant on the side where the
  comparison holds and another case on the other; of two tags, the keys are equal on the side where the tags are.
* An edge keeps what its block's entry knew, less the facts about the values the block defines; a block's entry is what
  every reached incoming edge gives. A block where a key can be no case is never entered.
* A tag test counts only when its comparison is listed in the branch's block and each `union_tag` it reads is fresh: a
  must-fact of its own (`TagFacts.fresh`), made where a block lists the `union_tag` and ended where a block lists its value
  and not the read (`freshOut`); `record_get`, `record_set` and `phi` results are fresh the same way. A read of a value its
  own block lists has no entry fact.
* A read is also justified through a fresh `record_get` twin of the same record and field (shape R), a fresh `record_set`
  of the same field (shape S: the stored value's facts), or a fresh `phi` whose operands can only be the case read (shape
  P, through `phi`s of `phi`s). A read of a `list_get` value is shape M: counted, not refused.

`TagProof.lean` proves, for a small run semantics, that the facts hold on every run and so that an accepted read sees its
own tag (`payload_under_tag`).
-/

namespace VerifyIr

/-- Facts at a program point: a mask of cases per key, and pairs of keys with equal tags. -/
structure TagFacts where
  masks : List (Nat × Nat) := []
  pairs : List (Nat × Nat) := []
  /-- The `union_tag` reads that hold their value's current tag. -/
  fresh : List Nat := []
  deriving Repr, Inhabited

/-- The cases `0 .. n-1`, as the bits of a natural number (any width: the Zig verifier's `Bits`). -/
def allCases (n : Nat) : Nat := 2 ^ n - 1
/-- Case `k` of a union of `n` cases (nothing when `k` is no case). -/
def caseMask (n k : Nat) : Nat := if k < n then 2 ^ k else 0

def lookupMask (masks : List (Nat × Nat)) (key : Nat) : Option Nat := (masks.find? (·.1 == key)).map (·.2)

def setMask (masks : List (Nat × Nat)) (key mask : Nat) : List (Nat × Nat) :=
  if masks.any (·.1 == key) then masks.map fun (k, m) => if k == key then (k, mask) else (k, m) else masks ++ [(key, mask)]

def sameFacts (a b : TagFacts) : Bool :=
  a.masks.length == b.masks.length && a.pairs.length == b.pairs.length && a.fresh.length == b.fresh.length &&
  a.fresh.all (b.fresh.contains ·) &&
  a.masks.all (fun (k, m) => lookupMask b.masks k == some m) && a.pairs.all (b.pairs.contains ·)

namespace Fn
variable (c : Fn)

/-- Follow copies and overlays to the value they stand for. -/
def canonical (r : Option Nat) : Option Nat :=
  let rec go : Nat → Nat → Option Nat
    | 0, _ => none
    | n + 1, x => match c.f.insts[x]? with
      | some i => if i.op == .copy || i.op == .borrow then (match i.a with | some y => go n y | none => none) else some x
      | none => none
  match r with
  | none => none
  | some x => go (c.f.insts.size + 1) x

def instOp (r : Nat) : Op := ((c.f.insts[r]?).map (·.op)).getD .copy

/-- The number of cases of a union type. -/
def unionCases (t : Ty) : Option Nat :=
  match c.m.compound? (c.m.storageType t) with
  | some (.union cs) => some cs.length
  | _ => none

/-- The key a tag register reads, with the number of cases. -/
def tagKey (raw : Option Nat) : Option (Nat × Nat) := do
  let r ← c.canonical raw
  let i ← c.f.insts[r]?
  match i.op with
  | .unionTag =>
    let x ← c.canonical i.a
    let xi ← c.f.insts[x]?
    let n ← c.unionCases xi.ty
    pure (x, n)
  | .listGetField =>
    let list ← c.canonical i.a
    let li ← c.f.insts[list]?
    let element ← c.m.listElement (c.m.storageType li.ty)
    let (_, tagOf) ← c.m.pathTarget element (fieldPath i.data)
    if tagOf == Ty.void then none else
    let n ← c.unionCases tagOf
    pure (r, n)
  | _ => none

/-- The cases a key's tag can be. -/
def possible (masks : List (Nat × Nat)) (key n : Nat) : Nat :=
  let own := match c.f.insts[key]? with
    | some i => if i.op == .unionMake then caseMask n i.data &&& allCases n else allCases n
    | none => allCases n
  own &&& (lookupMask masks key).getD (allCases n)

end Fn

/-- One pass over the pairs: add the other key of every pair one of whose keys is in the class. -/
def growStep (pairs : List (Nat × Nat)) (cls : List Nat) : List Nat :=
  pairs.foldl (fun cls (a, b) =>
    if cls.contains a && !cls.contains b then cls ++ [b] else if cls.contains b && !cls.contains a then cls ++ [a] else cls) cls

def grow (pairs : List (Nat × Nat)) : Nat → List Nat → List Nat
  | 0, cls => cls
  | n + 1, cls => grow pairs n (growStep pairs cls)

/-- The keys equal to `key` by the pairs (enough passes for a chain through every pair). -/
def classOf (pairs : List (Nat × Nat)) (key : Nat) : List Nat := grow pairs (pairs.length + 1) [key]

namespace Fn
variable (c : Fn)

def narrow (masks : List (Nat × Nat)) (pairs : List (Nat × Nat)) (key n mask : Nat) : List (Nat × Nat) :=
  (classOf pairs key).foldl (fun ms k => setMask ms k (c.possible masks k n &&& mask)) masks

/-- Where an instruction is listed: nowhere, in one block, or in more than one. -/
inductive Home where
  | unlisted
  | one (b : Nat)
  | many
  deriving DecidableEq, Repr, Inhabited

/-- The home of each instruction. -/
def blockOf : Array Home := Id.run do
  let mut out := Array.replicate c.f.insts.size Home.unlisted
  for (blk, b) in c.f.blocks.toList.zipIdx do
    for entry in blk.insts do
      match entry with
      | some r =>
        if r < out.size then
          out := out.set! r (match out[r]! with
            | .unlisted => .one b
            | .one b' => if b' == b then .one b else .many
            | .many => .many)
      | none => pure ()
  return out

/-- Block `p` (may) list instruction `k`. -/
def listedIn (bo : Array Home) (p k : Nat) : Bool :=
  match bo[k]?.getD .unlisted with
  | .many => true
  | .one b => b == p
  | .unlisted => false

/-- An operation whose result is made of its operands as they are (a tag, a field, a record with one field replaced). -/
def projection (op : Op) : Bool := op == .unionTag || op == .recordGet || op == .recordSet

/-- Whether block `p` leaves every value a fresh read `u` reads as it was: the operand of a projection, each operand of a
`phi` (a `phi` is fresh while it is one of its operands as they are now). -/
def operandsKept (bo : Array Home) (p u : Nat) : Bool :=
  match c.f.insts[u]? with
  | some i =>
    if projection i.op then (match c.canonical i.a with
      | some x => !listedIn bo p x && (i.op != .recordSet || match c.canonical i.b with
        | some w => !listedIn bo p w
        | none => false)
      | none => false)
    else if i.op == .phi then (c.extraOf i.data).all fun e => match c.canonical e with
      | some x => !listedIn bo p x
      | none => false
    else false
  | none => false

/-- The fresh reads block `p` makes: the projections it lists, and the `phi`s it lists whose operands it leaves as they were. -/
def tagReads (bo : Array Home) (p : Nat) : List Nat :=
  ((c.f.blocks[p]?).map fun blk => blk.insts.toList.filterMap fun e => e.bind fun r =>
    if projection (c.instOp r) || (c.instOp r == .phi && c.operandsKept bo p r) then some r else none).getD []

/-- The fresh tag reads after block `p`: those of the entry whose value `p` does not make again, then the `union_tag` reads
`p` lists (each reads its value as `p` leaves it). -/
def freshOut (bo : Array Home) (p : Nat) (fresh : List Nat) : List Nat :=
  let kept := fresh.filter (c.operandsKept bo p ·)
  (c.tagReads bo p).foldl (fun out u => if out.contains u then out else out ++ [u]) kept

/-- The key of a tag the comparison in `p` reads, when it reads the key's current tag. -/
def freshKey (fresh : List Nat) (raw : Option Nat) : Option (Nat × Nat) :=
  match c.tagKey raw, c.canonical raw with
  | some (k, n), some r =>
    if c.instOp r == .listGetField then some (k, n) else
    if fresh.contains r then some (k, n) else none
  | _, _ => none

/-- Block `p` lists `raw`'s canonical value. -/
def testedHere (bo : Array Home) (p : Nat) (raw : Option Nat) : Bool :=
  match c.canonical raw with
  | some v => listedIn bo p v
  | none => false

/-- What the test that ends block `p` says on its edge to `s`: two keys' tags are equal, or one key's tag is in a mask. -/
inductive EdgeTest where
  | equal (lk ln rk rn : Nat)
  | within (k n mask : Nat)
  deriving Repr

/-- The test on the edge from `p` to `s`, if its block ends in a counted tag test. -/
def edgeTest (bo : Array Home) (p : Nat) (fresh : List Nat) (s : Nat) : Option EdgeTest :=
  match (c.f.blocks[p]?).bind (·.insts.back?) with
  | some (some lr) => match c.f.insts[lr]? with
    | some last =>
      let (thenB, elseB) := branchTargets last.data
      if last.op != .branch || thenB == elseB then none else
      if !c.testedHere bo p last.a then none else
      match c.canonical last.a >>= c.inst? with
      | none => none
      | some cnd =>
        if cnd.op != .cmp || cnd.data > 1 then none else
        let holds := (s == thenB) == (cnd.data == 0)
        let lkey := c.freshKey fresh cnd.a
        let rkey := c.freshKey fresh cnd.b
        match lkey, rkey with
        | some (lk, ln), some (rk, rn) =>
          if holds && ln == rn && lk != rk then some (.equal lk ln rk rn) else none
        | some (k, n), none | none, some (k, n) =>
          let otherRaw := if lkey.isSome then cnd.b else cnd.a
          match c.canonical otherRaw >>= c.inst? with
          | some ci =>
            if ci.op == .iconst then
              let onTrue := caseMask n ci.data &&& allCases n
              some (.within k n (if holds then onTrue else allCases n ^^^ onTrue))
            else none
          | none => none
        | none, none => none
    | none => none
  | _ => none

/-- The facts a block's entry knew that its execution does not redefine. -/
def killed (bo : Array Home) (p : Nat) (facts : TagFacts) : TagFacts :=
  ⟨facts.masks.filter fun (k, _) => !listedIn bo p k, facts.pairs.filter fun (a, b) => !listedIn bo p a && !listedIn bo p b,
   c.freshOut bo p facts.fresh⟩

/-- The facts after a test. -/
def applyTest (plain : TagFacts) : Option EdgeTest → TagFacts
  | none => plain
  | some (.equal lk ln rk rn) =>
    let pair := (min lk rk, max lk rk)
    let pairs' := if plain.pairs.contains pair then plain.pairs else plain.pairs ++ [pair]
    let both := c.possible plain.masks lk ln &&& c.possible plain.masks rk rn
    ⟨c.narrow plain.masks pairs' lk ln both, pairs', plain.fresh⟩
  | some (.within k n mask) => ⟨c.narrow plain.masks plain.pairs k n mask, plain.pairs, plain.fresh⟩

/-- The facts on the edge from `p` to `s`. -/
def tagEdge (bo : Array Home) (p : Nat) (facts : TagFacts) (s : Nat) : TagFacts :=
  let plain := c.killed bo p facts
  c.applyTest plain (c.edgeTest bo p plain.fresh s)

def meetFacts (a b : TagFacts) : TagFacts :=
  ⟨a.masks.filterMap (fun (k, m) => (lookupMask b.masks k).map fun m' => (k, m ||| m')), a.pairs.filter (b.pairs.contains ·),
   a.fresh.filter (b.fresh.contains ·)⟩

/-- The entry facts of every block, iterated to the greatest fixed point (none when they do not settle in 1000 passes). -/
def tagEntries (reachable : Array Bool) : Option (Array (Option TagFacts)) := Id.run do
  let n := c.f.blocks.size
  let bo := c.blockOf
  let mut entry : Array (Option TagFacts) := (Array.replicate n none).set! 0 (some {})
  for _ in [0:1000] do
    let mut changed := false
    for s in [0:n] do
      if s == 0 || !reachable[s]! then continue
      let mut met : Option TagFacts := none
      for p in (c.f.blocks[s]!).preds do
        if p ≥ n || !reachable[p]! then continue
        match entry[p]! with
        | none => continue
        | some facts =>
          let incoming := c.tagEdge bo p facts s
          met := some (match met with | some cur => meetFacts cur incoming | none => incoming)
      match met with
      | none => continue
      | some new =>
        match entry[s]! with
        | some old => if sameFacts old new then continue
        | none => pure ()
        entry := entry.set! s (some new)
        changed := true
    if !changed then return some entry
  return none

/-- Shape R: `v` is a `record_get` and fresh after block `b`, and another fresh `record_get` of the same record and field,
which `b` does not list, has its tag within `case` by the entry facts. -/
def twinJustified (bo : Array Home) (facts : TagFacts) (b v n case : Nat) : Bool :=
  match c.f.insts[v]? with
  | some vi => vi.op == .recordGet && (match c.canonical vi.a with
    | some base =>
      let out := c.freshOut bo b facts.fresh
      out.contains v && out.any fun u => u != v && (match c.f.insts[u]? with
        | some ui => ui.op == .recordGet && ui.data == vi.data && !listedIn bo b u && c.canonical ui.a == some base &&
          (c.possible facts.masks u n &&& case == c.possible facts.masks u n)
        | none => false)
    | none => false)
  | none => false

/-- The cases `x` can be at the end of block `b`, whose entry facts are `facts` and fresh reads after it `out`: for a fresh
`phi`, what any of its operands can be (`fuel` bounds the `phi`s followed); for any other value, its facts. -/
def possibleAt (bo : Array Home) (facts : TagFacts) (b : Nat) (out : List Nat) : Nat → Nat → Nat → Nat
  | 0, x, n => c.possible (if listedIn bo b x then [] else facts.masks) x n
  | k + 1, x, n => match c.f.insts[x]? with
    | some xi =>
      if xi.op == .phi && out.contains x then
        (c.extraOf xi.data).foldl (fun acc e => acc ||| match c.canonical e with
          | some y => possibleAt bo facts b out k y n
          | none => allCases n) 0
      else c.possible (if listedIn bo b x then [] else facts.masks) x n
    | none => c.possible (if listedIn bo b x then [] else facts.masks) x n

/-- Shape P: `v` is a `phi` and what it can be at the end of block `b`, through the fresh `phi`s it merges, is within
`case`. -/
def phiJustified (bo : Array Home) (facts : TagFacts) (b v n case : Nat) : Bool :=
  match c.f.insts[v]? with
  | some vi =>
    let cases := c.possibleAt bo facts b (c.freshOut bo b facts.fresh) c.f.insts.size v n
    vi.op == .phi && cases &&& case == cases
  | none => false

/-- Shape S: `v` is a `record_get` of a `record_set` of the same field, both fresh after block `b`, and the facts justify
the read of the value the `record_set` stored. -/
def storeJustified (bo : Array Home) (facts : TagFacts) (b v n case : Nat) : Bool :=
  match c.f.insts[v]? with
  | some vi => vi.op == .recordGet && (match c.canonical vi.a with
    | some x => match c.f.insts[x]? with
      | some xi =>
        let out := c.freshOut bo b facts.fresh
        xi.op == .recordSet && xi.data == vi.data && (c.canonical xi.a).isSome && out.contains v && out.contains x &&
          (match c.canonical xi.b with
          | some w =>
            let masks := if listedIn bo b w then [] else facts.masks
            c.possible masks w n &&& case == c.possible masks w n
          | none => false)
      | none => false
    | none => false)
  | none => false

/-- Whether the facts justify a read of `v` in block `b`. -/
def byFacts (bo : Array Home) (entry : Array (Option TagFacts)) (b v : Nat) (i : Inst) : Bool :=
  let facts := (entry[b]?.join).getD {}
  if facts.masks.any (·.2 == 0) then true else
  match (c.f.insts[v]?).bind fun vi => c.unionCases vi.ty with
  | none => false
  | some n =>
    let masks := if listedIn bo b v then [] else facts.masks
    c.possible masks v n &&& caseMask n i.data == c.possible masks v n || c.twinJustified bo facts b v n (caseMask n i.data) ||
      c.phiJustified bo facts b v n (caseMask n i.data) || c.storeJustified bo facts b v n (caseMask n i.data)

/-- The verdict of the rule on one read in block `b`: justified by the facts (`some true`), shape M (`none`: a `list_get`
value the facts do not justify), or refused (`some false`). -/
def readVerdict (bo : Array Home) (entry : Array (Option TagFacts)) (b : Nat) (i : Inst) : Option Bool :=
  match c.canonical i.a with
  | none => some false
  | some v =>
    if c.byFacts bo entry b v i then some true else
    if c.instOp v == .listGet then none else some false

/-- The first read the facts do not justify, in block order: its block and instruction (`none` for the instruction when
the facts did not settle). -/
def unionTags (reachable : Array Bool) : Option (Nat × Option Nat) :=
  match c.tagEntries reachable with
  | none => some (0, none)
  | some entry =>
    let bo := c.blockOf
    let reads := c.f.blocks.toList.zipIdx.flatMap fun (blk, b) =>
      if !reachable[b]! then [] else blk.insts.toList.filterMap fun e => e.map fun r => (b, r)
    reads.findSome? fun (b, r) => match c.f.insts[r]? with
      | some i =>
        if i.op != .unionPayload && i.op != .unionTake then none else
        if c.readVerdict bo entry b i == some false then some (b, some r) else none
      | none => none

/-- Which rule justifies a read the facts justify: 0 its own value's facts, 1 a `record_get` twin (shape R), 2 a fresh `phi`
(shape P). -/
def justifiedBy (bo : Array Home) (entry : Array (Option TagFacts)) (b : Nat) (i : Inst) : Nat :=
  match c.canonical i.a, (entry[b]?.join).getD {} with
  | some v, facts =>
    match (c.f.insts[v]?).bind fun vi => c.unionCases vi.ty with
    | some n =>
      let masks := if listedIn bo b v then [] else facts.masks
      if facts.masks.any (·.2 == 0) || c.possible masks v n &&& caseMask n i.data == c.possible masks v n then 0 else
      if c.twinJustified bo facts b v n (caseMask n i.data) then 1 else
      if c.phiJustified bo facts b v n (caseMask n i.data) then 2 else
      if c.storeJustified bo facts b v n (caseMask n i.data) then 3 else 0
    | none => 0
  | none, _ => 0

/-- Payload reads: justified by their own value's facts, by a `record_get` twin (R), by a fresh `phi` (P), and of shape M
(counted, not refused). -/
def payloadCounts (reachable : Array Bool) : Nat × Nat × Nat × Nat :=
  match c.tagEntries reachable with
  | none => (0, 0, 0, 0)
  | some entry =>
    let bo := c.blockOf
    c.f.blocks.toList.zipIdx.foldl (fun acc (blk, b) =>
      if !reachable[b]! then acc else
      blk.insts.foldl (fun (j, r, p, mm) e => match e.bind (c.f.insts[·]?) with
        | some i =>
          if i.op != .unionPayload && i.op != .unionTake then (j, r, p, mm) else
          match c.readVerdict bo entry b i with
          | some true => match c.justifiedBy bo entry b i with
            | 1 => (j, r + 1, p, mm)
            | 2 => (j, r, p + 1, mm)
            | 3 => (j, r + 1, p, mm)
            | _ => (j + 1, r, p, mm)
          | none => (j, r, p, mm + 1)
          | some false => (j, r, p, mm)
        | none => (j, r, p, mm)) acc) (0, 0, 0, 0)

end Fn

end VerifyIr
