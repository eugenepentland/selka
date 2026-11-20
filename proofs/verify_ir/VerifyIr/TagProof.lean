import VerifyIr.TagFlow

/-!
# A justified payload read sees its own tag (F-VL-10)

A small run semantics of one function, as far as tags go, and the theorem that the union-tag rule is sound for it.

* **Values.** `RVal`: an integer, a union value of some case, or anything else. A register holds a value once the
  instruction that defines it has run (`Env`); a constant (`iconst`) reads as its integer.
* **A step.** `BlockStep`: running block `p` changes only the registers `p` lists, and each one it defines holds what
  its operation makes (`Defines`: a `union_make` its case, a `union_tag` the tag of the value it reads, a `cmp eq|ne` the
  truth of the comparison of the integers it reads, an `iconst` its integer) at a type its value fits (`Typed`: a union
  value's case is below the union's case count, a `list_get_field` of a tag path reads a case of that union: the run time's
  type safety, as `proofs/facts` takes it for its machine). `Takes`: a jump goes to its target, a branch to the side its
  condition's integer (1 or 0) names.
* **A run.** `Exec s ρ`: a run of the function reaches the entry of block `s` with registers `ρ`, from the entry with only
  parameters set.

The checker's facts are verified, not trusted: `tagOKWith E` checks the entries `E` the analysis computed (the homes it
reads are the listing, `homesOK`; the entry block's facts are empty; every edge out of a block with facts implies its
target's entry; every read of such a block is justified or of shape M), so nothing below reads the fixpoint iteration.
The semantics names the instructions a block lists by the listing itself (`Lists`), not by the checker's homes.

* `exec_inv`: on every run, at the entry of each block it reaches, the registers fit their types and hold their
  `union_make` cases (`Inv`), satisfy the block's facts (`Sat`), and every fresh tag read holds its value's current tag
  (`FreshHold`).
* `payload_under_tag`: a run that runs block `b` and reads there, by a `union_payload k` or `union_take k`, a value that is
  not a `list_get` (shape M) and holds case `j`, has `j = k`. `payload_of_verdict` (`SsaProof.lean`) states it of every
  function the checker accepts.

What the semantics takes as given (`AXIOMS.md`, V9): a copy or overlay is the value it forwards (`canonical`); an
instruction reads the values of its own block's end, which is SSA within a block; the integers a `cmp` compares are the
naturals the registers hold; and the run time's type safety (`Typed`).
-/

namespace VerifyIr

/-- A run-time value, as far as tags go. -/
inductive RVal where
  | int (n : Nat)
  | union (j : Nat)
  | record (fields : List RVal)
  | other
  deriving Repr

/-- The registers of a run: a value once the instruction ran. -/
abbrev Env := Nat → Option RVal

/-- Whether facts `a` follow from facts `b`: every mask of `a` holds the mask `b` states for its key, every pair and every
fresh tag read of `a` is in `b`. -/
def implies (a b : TagFacts) : Bool :=
  a.masks.all (fun (k, m) => match lookupMask b.masks k with | some m' => m' &&& m == m' | none => false) &&
  a.pairs.all (b.pairs.contains ·) && a.fresh.all (b.fresh.contains ·)

namespace Fn
variable (c : Fn)

/-- The value a register reads: a constant as its integer. -/
def value (ρ : Env) (r : Nat) : Option RVal :=
  match c.f.insts[r]? with
  | some i => if i.op == .iconst then some (.int i.data) else ρ r
  | none => ρ r

/-- The tag a key's register holds: a union value's case, or the integer a tag read holds. -/
def keyTag (ρ : Env) (k : Nat) : Option Nat :=
  match ρ k with
  | some (.union j) => some j
  | some (.int t) => some t
  | _ => none

/-- What running instruction `r` leaves in it, given the registers `ρ0` of the block's entry and `ρ` of its end. -/
def Defines (ρ0 ρ : Env) (r : Nat) (v : RVal) : Prop :=
  match c.f.insts[r]? with
  | none => False
  | some i =>
    (i.op = .unionMake → v = .union i.data) ∧
    (i.op = .iconst → v = .int i.data) ∧
    (i.op = .unionTag → ∃ x j, c.canonical i.a = some x ∧ ρ x = some (.union j) ∧ v = .int j) ∧
    (i.op = .cmp → i.data ≤ 1 → ∃ x y a b, c.canonical i.a = some x ∧ c.canonical i.b = some y ∧
      c.value ρ x = some (.int a) ∧ c.value ρ y = some (.int b) ∧
      v = .int (if decide (a = b) = decide (i.data = 0) then 1 else 0)) ∧
    (i.op = .recordGet → ∃ x fs, c.canonical i.a = some x ∧ ρ x = some (.record fs) ∧ fs[i.data]? = some v) ∧
    (i.op = .recordSet → ∃ x w fs wv, c.canonical i.a = some x ∧ c.canonical i.b = some w ∧ ρ x = some (.record fs) ∧
      c.value ρ w = some wv ∧ v = .record (fs.set i.data wv)) ∧
    (i.op = .phi → ∃ e x, e ∈ c.extraOf i.data ∧ c.canonical e = some x ∧ c.value ρ0 x = some v)

/-- The value fits the register's type (the run time's type safety). -/
def Typed (r : Nat) (v : RVal) : Prop :=
  (∀ i n, c.f.insts[r]? = some i → c.unionCases i.ty = some n → ∃ j, j < n ∧ v = .union j) ∧
  (∀ k n, c.instOp r = .listGetField → c.tagKey (some r) = some (k, n) → ∃ t, t < n ∧ v = .int t)

/-- Block `p` lists instruction `r`. -/
def Lists (p r : Nat) : Prop := ∃ blk, c.f.blocks[p]? = some blk ∧ some r ∈ blk.insts

/-- Running block `p` takes registers `ρ` to `ρ'`. -/
def BlockStep (p : Nat) (ρ ρ' : Env) : Prop :=
  (∀ r, ¬ c.Lists p r → ρ' r = ρ r) ∧
  (∀ r v, c.Lists p r → ρ' r = some v → c.Defines ρ ρ' r v ∧ c.Typed r v)

/-- Block `p`, with registers `ρ` at its end, goes on to block `s`. -/
def Takes (p : Nat) (ρ : Env) (s : Nat) : Prop :=
  ∃ blk lr last, c.f.blocks[p]? = some blk ∧ blk.insts.back? = some (some lr) ∧ c.f.insts[lr]? = some last ∧
    ((last.op = .jump ∧ s = last.data % 2 ^ 32) ∨
     (last.op = .branch ∧ ∃ cr, c.canonical last.a = some cr ∧
       ((c.value ρ cr = some (.int 1) ∧ s = (branchTargets last.data).1) ∨
        (c.value ρ cr = some (.int 0) ∧ s = (branchTargets last.data).2))))

/-- A run reaches the entry of block `s` with registers `ρ`. -/
inductive Exec : Nat → Env → Prop where
  | start {ρ : Env} : (∀ r v, ρ r = some v → c.instOp r = .param ∧ c.Typed r v) → Exec 0 ρ
  | step {p s : Nat} {ρ ρ' : Env} : Exec p ρ → c.BlockStep p ρ ρ' → c.Takes p ρ' s → Exec s ρ'

/-- The facts hold of the registers: each masked key holds a tag in its mask, each pair two equal tags. -/
def Sat (ρ : Env) (F : TagFacts) : Prop :=
  (∀ k m, (k, m) ∈ F.masks → ∃ t, keyTag ρ k = some t ∧ m.testBit t = true) ∧
  (∀ a b, (a, b) ∈ F.pairs → ∃ t, keyTag ρ a = some t ∧ keyTag ρ b = some t)

/-- The reads of block `b` are each justified by the entries `E` or of shape M. -/
def readsOK (E : Array (Option TagFacts)) (b : Nat) : Bool :=
  ((c.f.blocks[b]?).map fun blk => blk.insts.all fun e => match e.bind (c.f.insts[·]?) with
    | some i => (i.op != .unionPayload && i.op != .unionTake) || c.readVerdict c.blockOf E b i != some false
    | none => true).getD true

/-- The homes `bo` are exact: each block's listed instructions have it as their one home, and each home names a block that
lists the instruction (so `listedIn` is the listing). -/
def homesOK (bo : Array Home) : Bool :=
  bo.size == c.f.insts.size &&
  (List.range c.f.blocks.size).all (fun p => match c.f.blocks[p]? with
    | some blk => blk.insts.all fun e => match e with
      | some r => bo[r]? == some (Home.one p)
      | none => true
    | none => true) &&
  (List.range bo.size).all (fun r => match bo[r]? with
    | some (.one p) => match c.f.blocks[p]? with
      | some blk => blk.insts.contains (some r)
      | none => false
    | some .many => false
    | _ => true)

/-- The verified tag facts, for entries `E`: the homes are exact, the entry block's facts are empty, every edge out of a
block with facts implies its target's entry, and the reads of every block with facts are justified or of shape M. -/
def tagOKWith (E : Array (Option TagFacts)) : Bool :=
  let n := c.f.blocks.size
  c.homesOK c.blockOf && E.size == n &&
  (n == 0 || (match E[0]! with | some F => F.masks.isEmpty && F.pairs.isEmpty && F.fresh.isEmpty | none => false)) &&
  (List.range n).all fun p => match E[p]! with
    | none => true
    | some F => c.readsOK E p && (c.succList p).all fun s => decide (s ≥ n) || match E[s]! with
      | some A => implies A (c.tagEdge c.blockOf p F s)
      | none => false

/-- The verified tag facts of the analysis's entries. -/
def tagOK (reachable : Array Bool) : Bool :=
  match c.tagEntries reachable with
  | none => false
  | some E => c.tagOKWith E

end Fn

/-! ## The proof -/

theorem lookupMask_mem {masks : List (Nat × Nat)} {k m : Nat} (h : lookupMask masks k = some m) : (k, m) ∈ masks := by
  unfold lookupMask at h
  cases hf : masks.find? (·.1 == k) with
  | none => simp [hf] at h
  | some p =>
    simp [hf] at h
    have hm := List.mem_of_find?_eq_some hf
    have hk := List.find?_some hf
    obtain ⟨a, b⟩ := p
    simp at hk h
    subst hk; subst h; exact hm

theorem mem_setMask {ms : List (Nat × Nat)} {key mask k m : Nat} (h : (k, m) ∈ setMask ms key mask) :
    (k, m) ∈ ms ∨ (k = key ∧ m = mask) := by
  unfold setMask at h
  split at h
  · simp only [List.mem_map] at h
    obtain ⟨⟨k', m'⟩, hm, he⟩ := h
    by_cases hk : k' = key
    · subst hk; simp at he; right; exact ⟨he.1.symm, he.2.symm⟩
    · simp [hk] at he; obtain ⟨rfl, rfl⟩ := he; left; exact hm
  · simp only [List.mem_append, List.mem_singleton] at h
    rcases h with h | h
    · left; exact h
    · right; simp at h; exact h

theorem testBit_and_eq {a b t : Nat} (h : a &&& b = a) (ha : a.testBit t = true) : b.testBit t = true := by
  have := congrArg (fun x => x.testBit t) h
  simp [Nat.testBit_and, ha] at this
  exact this

theorem testBit_caseMask {n d t : Nat} (h : (caseMask n d).testBit t = true) : t = d := by
  unfold caseMask at h
  split at h
  · rw [Nat.testBit_two_pow] at h; simp at h; exact h.symm
  · simp at h

theorem testBit_caseMask_self {n d : Nat} (h : d < n) : (caseMask n d).testBit d = true := by
  simp [caseMask, h]

theorem testBit_allCases {n t : Nat} (h : t < n) : (allCases n).testBit t = true := by
  unfold allCases
  rw [Nat.testBit_two_pow_sub_one]
  simp [h]

/-- Facts that follow from satisfied facts are satisfied. -/
theorem sat_of_implies {ρ : Env} {a b : TagFacts} (h : implies a b = true) (hs : Fn.Sat ρ b) : Fn.Sat ρ a := by
  unfold implies at h
  simp only [Bool.and_eq_true, List.all_eq_true] at h
  obtain ⟨⟨hm, hp⟩, _⟩ := h
  refine ⟨fun k m hk => ?_, fun x y hxy => ?_⟩
  · have := hm (k, m) hk
    simp only at this
    split at this
    · rename_i m' hl
      obtain ⟨t, ht, hb⟩ := hs.1 k m' (lookupMask_mem hl)
      exact ⟨t, ht, testBit_and_eq (by simpa using this) hb⟩
    · simp at this
  · have := hp (x, y) hxy
    exact hs.2 x y (by simpa using this)


theorem sat_killed {c : Fn} {bo : Array Fn.Home} {p : Nat} {ρ ρ' : Env} {F : TagFacts} (hs : Fn.Sat ρ F)
    (hu : ∀ r, Fn.listedIn bo p r = false → ρ' r = ρ r) : Fn.Sat ρ' (c.killed bo p F) := by
  have kt : ∀ r, Fn.listedIn bo p r = false → Fn.keyTag ρ' r = Fn.keyTag ρ r := fun r h => by simp [Fn.keyTag, hu r h]
  refine ⟨fun k m hk => ?_, fun a b hab => ?_⟩
  · simp only [Fn.killed, List.mem_filter, Bool.not_eq_true'] at hk
    rw [kt k hk.2]; exact hs.1 k m hk.1
  · simp only [Fn.killed, List.mem_filter, Bool.and_eq_true, Bool.not_eq_true'] at hab
    rw [kt a hab.2.1, kt b hab.2.2]; exact hs.2 a b hab.1

/-- The masks hold of the registers. -/
def MasksHold (ρ : Env) (ms : List (Nat × Nat)) : Prop := ∀ k m, (k, m) ∈ ms → ∃ t, Fn.keyTag ρ k = some t ∧ m.testBit t = true

/-- The pairs hold of the registers. -/
def PairsHold (ρ : Env) (ps : List (Nat × Nat)) : Prop := ∀ a b, (a, b) ∈ ps → ∃ t, Fn.keyTag ρ a = some t ∧ Fn.keyTag ρ b = some t

theorem growStep_tag {ρ : Env} {pairs : List (Nat × Nat)} {t : Nat} (hp : PairsHold ρ pairs) :
    ∀ cls : List Nat, (∀ k ∈ cls, Fn.keyTag ρ k = some t) → ∀ k ∈ growStep pairs cls, Fn.keyTag ρ k = some t := by
  intro cls hc
  unfold growStep
  suffices ∀ (l : List (Nat × Nat)), (∀ x ∈ l, x ∈ pairs) → ∀ cls : List Nat, (∀ k ∈ cls, Fn.keyTag ρ k = some t) →
      ∀ k ∈ l.foldl (fun cls (ab : Nat × Nat) => if cls.contains ab.1 && !cls.contains ab.2 then cls ++ [ab.2]
        else if cls.contains ab.2 && !cls.contains ab.1 then cls ++ [ab.1] else cls) cls, Fn.keyTag ρ k = some t from
    this pairs (fun _ h => h) cls hc
  intro l
  induction l with
  | nil => intro _ cls hc; simpa using hc
  | cons ab rest ih =>
    intro hl cls hc
    simp only [List.foldl_cons]
    apply ih (fun x hx => hl x (List.mem_cons_of_mem _ hx))
    obtain ⟨a, b⟩ := ab
    obtain ⟨t', ha, hb⟩ := hp a b (hl _ List.mem_cons_self)
    simp only
    split
    · rename_i h
      simp only [Bool.and_eq_true, List.contains_iff_mem] at h
      have : t' = t := by rw [hc a h.1] at ha; exact (Option.some.inj ha).symm
      subst this
      intro k hk; simp only [List.mem_append, List.mem_singleton] at hk
      rcases hk with hk | rfl
      · exact hc k hk
      · exact hb
    · split
      · rename_i _ h
        simp only [Bool.and_eq_true, List.contains_iff_mem] at h
        have : t' = t := by rw [hc b h.1] at hb; exact (Option.some.inj hb).symm
        subst this
        intro k hk; simp only [List.mem_append, List.mem_singleton] at hk
        rcases hk with hk | rfl
        · exact hc k hk
        · exact ha
      · exact hc

theorem classOf_tag {ρ : Env} {pairs : List (Nat × Nat)} {key t : Nat} (hp : PairsHold ρ pairs)
    (hk : Fn.keyTag ρ key = some t) : ∀ k ∈ classOf pairs key, Fn.keyTag ρ k = some t := by
  unfold classOf
  suffices ∀ n cls, (∀ k ∈ cls, Fn.keyTag ρ k = some t) → ∀ k ∈ grow pairs n cls, Fn.keyTag ρ k = some t from
    this _ [key] (by simpa using hk)
  intro n
  induction n with
  | zero => intro cls hc; simpa [grow] using hc
  | succ n ih => intro cls hc; simp only [grow]; exact ih _ (growStep_tag hp cls hc)

/-- A `union_make` register holds a value of its own case. -/
def MakesHold (c : Fn) (ρ : Env) : Prop := ∀ r i v, c.f.insts[r]? = some i → i.op = Op.unionMake → ρ r = some v → v = .union i.data

theorem possible_tag {c : Fn} {ρ : Env} {masks : List (Nat × Nat)} {key n t : Nat} (hm : MasksHold ρ masks)
    (hmk : MakesHold c ρ) (hk : Fn.keyTag ρ key = some t) (hn : t < n) :
    (c.possible masks key n).testBit t = true := by
  have hall := testBit_allCases hn
  unfold Fn.possible
  simp only [Nat.testBit_and, Bool.and_eq_true]
  refine ⟨?_, ?_⟩
  · split
    · rename_i i hi
      split
      · rename_i hop
        have hop : i.op = Op.unionMake := by simpa using hop
        have : t = i.data := by
          unfold Fn.keyTag at hk
          split at hk
          · rename_i j hj; have := hmk key i _ hi hop hj; simp at this; simp at hk; omega
          · rename_i j hj; have := hmk key i _ hi hop hj; simp at this
          · simp at hk
        subst this
        simp [Nat.testBit_and, testBit_caseMask_self (by omega : i.data < n), hall]
      · exact hall
    · exact hall
  · cases hl : lookupMask masks key with
    | none => simpa using hall
    | some m =>
      obtain ⟨t', ht', hb⟩ := hm key m (lookupMask_mem hl)
      rw [hk] at ht'; cases ht'; simpa using hb

theorem narrow_holds {c : Fn} {ρ : Env} {masks pairs : List (Nat × Nat)} {key n t mask : Nat} (hm : MasksHold ρ masks)
    (hp : PairsHold ρ pairs) (hmk : MakesHold c ρ) (hk : Fn.keyTag ρ key = some t) (hn : t < n)
    (hb : mask.testBit t = true) : MasksHold ρ (c.narrow masks pairs key n mask) := by
  unfold Fn.narrow
  have hc := classOf_tag hp hk
  suffices ∀ (l : List Nat), (∀ k ∈ l, Fn.keyTag ρ k = some t) → ∀ ms, MasksHold ρ ms →
      MasksHold ρ (l.foldl (fun ms k => setMask ms k (c.possible masks k n &&& mask)) ms) from this _ hc masks hm
  intro l
  induction l with
  | nil => intro _ ms h; simpa using h
  | cons k rest ih =>
    intro hl ms hms
    simp only [List.foldl_cons]
    apply ih (fun x hx => hl x (List.mem_cons_of_mem _ hx))
    intro k' m' hmem
    rcases mem_setMask hmem with h | ⟨rfl, rfl⟩
    · exact hms k' m' h
    · refine ⟨t, hl _ List.mem_cons_self, ?_⟩
      simp [Nat.testBit_and, possible_tag hm hmk (hl _ List.mem_cons_self) hn, hb]

/-- What an edge test says holds of the registers. -/
def EdgeHolds (ρ : Env) : Option Fn.EdgeTest → Prop
  | none => True
  | some (.equal lk ln rk rn) => ∃ t, Fn.keyTag ρ lk = some t ∧ Fn.keyTag ρ rk = some t ∧ t < ln ∧ rn = ln
  | some (.within k n mask) => ∃ t, Fn.keyTag ρ k = some t ∧ t < n ∧ mask.testBit t = true

theorem sat_applyTest {c : Fn} {ρ : Env} {plain : TagFacts} {e : Option Fn.EdgeTest} (hs : Fn.Sat ρ plain)
    (hmk : MakesHold c ρ) (he : EdgeHolds ρ e) : Fn.Sat ρ (c.applyTest plain e) := by
  match e, he with
  | none, _ => simpa [Fn.applyTest] using hs
  | some (.within k n mask), ⟨t, hk, hn, hb⟩ =>
    exact ⟨narrow_holds hs.1 hs.2 hmk hk hn hb, hs.2⟩
  | some (.equal lk ln rk rn), ⟨t, hl, hr, hn, hrn⟩ =>
    subst hrn
    have hp' : PairsHold ρ (if plain.pairs.contains (min lk rk, max lk rk) then plain.pairs
        else plain.pairs ++ [(min lk rk, max lk rk)]) := by
      intro a b hab
      split at hab
      · exact hs.2 a b hab
      · simp only [List.mem_append, List.mem_singleton, Prod.mk.injEq] at hab
        rcases hab with hab | ⟨rfl, rfl⟩
        · exact hs.2 a b hab
        · refine ⟨t, ?_, ?_⟩
          · rcases Nat.le_total lk rk with h | h
            · rw [Nat.min_eq_left h]; exact hl
            · rw [Nat.min_eq_right h]; exact hr
          · rcases Nat.le_total lk rk with h | h
            · rw [Nat.max_eq_right h]; exact hr
            · rw [Nat.max_eq_left h]; exact hl
    refine ⟨narrow_holds hs.1 hp' hmk hl hn ?_, hp'⟩
    simp [Nat.testBit_and, possible_tag hs.1 hmk hl hn, possible_tag hs.1 hmk hr hn]


theorem canonical_go_spec {c : Fn} : ∀ (n x r : Nat), Fn.canonical.go c n x = some r →
    ∃ i, c.f.insts[r]? = some i ∧ i.op ≠ .copy ∧ i.op ≠ .borrow := by
  intro n
  induction n with
  | zero => intro x r h; simp [Fn.canonical.go] at h
  | succ n ih =>
    intro x r h
    simp only [Fn.canonical.go] at h
    split at h
    · rename_i i hi
      split at h
      · split at h
        · exact ih _ _ h
        · simp at h
      · rename_i hop
        simp at h; subst h
        simp only [Bool.or_eq_true, beq_iff_eq, not_or] at hop
        exact ⟨i, hi, hop.1, hop.2⟩
    · simp at h

theorem canonical_spec {c : Fn} {raw : Option Nat} {r : Nat} (h : c.canonical raw = some r) :
    ∃ i, c.f.insts[r]? = some i ∧ i.op ≠ .copy ∧ i.op ≠ .borrow := by
  unfold Fn.canonical at h
  split at h
  · simp at h
  · exact canonical_go_spec _ _ _ h

theorem canonical_self {c : Fn} {r : Nat} {i : Inst} (hi : c.f.insts[r]? = some i) (h1 : i.op ≠ .copy)
    (h2 : i.op ≠ .borrow) : c.canonical (some r) = some r := by
  show Fn.canonical.go c (c.f.insts.size + 1) r = some r
  simp [Fn.canonical.go, hi, h1, h2]

theorem value_of_not_const {c : Fn} {ρ : Env} {r : Nat} {i : Inst} (hi : c.f.insts[r]? = some i)
    (hop : i.op ≠ .iconst) : c.value ρ r = ρ r := by
  simp [Fn.value, hi, hop]


/-- Every set register's value fits its type. -/
def TypedHold (c : Fn) (ρ : Env) : Prop := ∀ r v, ρ r = some v → c.Typed r v

/-- The checker's homes are the listing: `listedIn` holds exactly of the instructions a block lists. -/
def HomesExact (c : Fn) : Prop := ∀ p r, Fn.listedIn c.blockOf p r = true ↔ c.Lists p r

theorem homes_exact {c : Fn} (h : c.homesOK c.blockOf = true) : HomesExact c := by
  unfold Fn.homesOK at h
  simp only [Bool.and_eq_true, beq_iff_eq, List.all_eq_true, List.mem_range] at h
  obtain ⟨⟨hsz, hfw⟩, hbw⟩ := h
  intro p r
  constructor
  · intro hl
    unfold Fn.listedIn at hl
    cases hb : c.blockOf[r]? with
    | none => rw [hb] at hl; simp at hl
    | some home =>
      rw [hb] at hl
      have hr : r < c.blockOf.size := by
        rcases Nat.lt_or_ge r c.blockOf.size with h | h
        · exact h
        · simp [h] at hb
      have := hbw r hr
      rw [hb] at this
      cases home with
      | unlisted => simp at hl
      | many => simp at this
      | one b =>
        simp at hl; subst hl
        simp only at this
        split at this
        · rename_i blk hblk; exact ⟨blk, hblk, by simpa using this⟩
        · simp at this
  · rintro ⟨blk, hblk, hmem⟩
    have hp : p < c.f.blocks.size := by
      rcases Nat.lt_or_ge p c.f.blocks.size with h | h
      · exact h
      · simp [h] at hblk
    have := hfw p hp
    rw [hblk] at this
    simp only [Array.all_eq_true] at this
    obtain ⟨idx, hidx, hget⟩ := Array.mem_iff_getElem.1 hmem
    have h2 := this idx hidx
    rw [hget] at h2
    simp only [beq_iff_eq] at h2
    unfold Fn.listedIn
    rw [h2]
    simp

theorem step_same {c : Fn} {p : Nat} {ρ ρ' : Env} (hH : HomesExact c) (hstep : c.BlockStep p ρ ρ') {r : Nat}
    (hl : Fn.listedIn c.blockOf p r = false) : ρ' r = ρ r :=
  hstep.1 r fun h => by rw [(hH p r).2 h] at hl; exact Bool.noConfusion hl

theorem step_def {c : Fn} {p : Nat} {ρ ρ' : Env} (hH : HomesExact c) (hstep : c.BlockStep p ρ ρ') {r : Nat} {v : RVal}
    (hl : Fn.listedIn c.blockOf p r = true) (hv : ρ' r = some v) : c.Defines ρ ρ' r v ∧ c.Typed r v :=
  hstep.2 r v ((hH p r).1 hl) hv

theorem mem_tagReads {c : Fn} {bo : Array Fn.Home} {p u : Nat} (h : u ∈ c.tagReads bo p) :
    c.Lists p u ∧ (c.instOp u = .phi → c.operandsKept bo p u = true) := by
  unfold Fn.tagReads at h
  cases hb : c.f.blocks[p]? with
  | none => rw [hb] at h; simp at h
  | some blk =>
    rw [hb] at h
    simp only [Option.map_some, Option.getD_some, List.mem_filterMap] at h
    obtain ⟨e, he, hu⟩ := h
    cases e with
    | none => simp at hu
    | some r =>
      simp only [Option.bind_some] at hu
      split at hu
      · rename_i hc
        cases hu
        refine ⟨⟨blk, hb, Array.mem_toList_iff.1 he⟩, fun hphi => ?_⟩
        simp only [Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq, hphi] at hc
        rcases hc with hc | hc
        · simp [Fn.projection] at hc
        · exact hc.2
      · simp at hu

theorem mem_dedupAppend {u : Nat} : ∀ (L out : List Nat),
    u ∈ L.foldl (fun out x => if out.contains x then out else out ++ [x]) out → u ∈ out ∨ u ∈ L := by
  intro L
  induction L with
  | nil => intro out h; left; simpa using h
  | cons x rest ih =>
    intro out h
    simp only [List.foldl_cons] at h
    rcases ih _ h with h' | h'
    · split at h'
      · left; exact h'
      · simp only [List.mem_append, List.mem_singleton] at h'
        rcases h' with h' | rfl
        · left; exact h'
        · right; exact List.mem_cons_self
    · right; exact List.mem_cons_of_mem _ h'

theorem mem_freshOut {c : Fn} {bo : Array Fn.Home} {p u : Nat} {l : List Nat} (h : u ∈ c.freshOut bo p l) :
    (u ∈ l ∧ c.operandsKept bo p u = true) ∨ u ∈ c.tagReads bo p := by
  unfold Fn.freshOut at h
  rcases mem_dedupAppend _ _ h with h' | h'
  · left
    simp only [List.mem_filter] at h'
    exact h'
  · right; exact h'

theorem kept_projection {c : Fn} {bo : Array Fn.Home} {p u x : Nat} {i : Inst} (hk : c.operandsKept bo p u = true)
    (hi : c.f.insts[u]? = some i) (hop : Fn.projection i.op = true) (hx : c.canonical i.a = some x) :
    Fn.listedIn bo p x = false := by
  unfold Fn.operandsKept at hk
  simp only [hi, hop, ite_true, hx, Bool.and_eq_true] at hk
  simpa using hk.1

theorem kept_store {c : Fn} {bo : Array Fn.Home} {p u x w : Nat} {i : Inst} (hk : c.operandsKept bo p u = true)
    (hi : c.f.insts[u]? = some i) (hop : i.op = .recordSet) (hx : c.canonical i.a = some x)
    (hw : c.canonical i.b = some w) : Fn.listedIn bo p w = false := by
  unfold Fn.operandsKept at hk
  rw [hi] at hk
  simp [hop, hx, hw, Fn.projection] at hk
  exact hk.2

theorem kept_phi {c : Fn} {bo : Array Fn.Home} {p u x : Nat} {i : Inst} {e : Option Nat}
    (hk : c.operandsKept bo p u = true) (hi : c.f.insts[u]? = some i) (hop : i.op = .phi)
    (he : e ∈ c.extraOf i.data) (hx : c.canonical e = some x) : Fn.listedIn bo p x = false := by
  unfold Fn.operandsKept at hk
  rw [hi] at hk
  simp only [hop, show Fn.projection Op.phi = false from rfl, Bool.false_eq_true, ite_false, beq_self_eq_true, ite_true,
    List.all_eq_true] at hk
  have := hk e he
  rw [hx] at this
  simpa using this

/-- A projection's operand is the operand `a` the kept check reads. -/
theorem kept_of_mem {c : Fn} {bo : Array Fn.Home} {p u : Nat} {l : List Nat} (h : u ∈ c.freshOut bo p l)
    (hl : Fn.listedIn bo p u = false) (hH : ∀ r, c.Lists p r → Fn.listedIn bo p r = true) :
    u ∈ l ∧ c.operandsKept bo p u = true := by
  rcases mem_freshOut h with h' | h'
  · exact h'
  · rw [hH u (mem_tagReads h').1] at hl; exact Bool.noConfusion hl

theorem value_union {c : Fn} {ρ : Env} {x j : Nat} (h : c.value ρ x = some (.union j)) : ρ x = some (.union j) := by
  unfold Fn.value at h
  split at h
  · split at h
    · simp at h
    · exact h
  · exact h

theorem value_same {c : Fn} {ρ ρ' : Env} {x : Nat} (h : ρ' x = ρ x) : c.value ρ' x = c.value ρ x := by
  unfold Fn.value
  split <;> simp [h]

/-- A fresh read `u` holds its operand's current part: a `union_tag` the case, a `record_get` the field, a `phi` the value of
one of its operands. -/
def ProjHolds (c : Fn) (ρ : Env) (u : Nat) : Prop :=
  (∀ i x v, c.f.insts[u]? = some i → c.canonical i.a = some x →
    ρ u = some v → (i.op = .unionTag → ∃ t, v = .int t ∧ ρ x = some (.union t)) ∧
      (i.op = .recordGet → ∃ fs, ρ x = some (.record fs) ∧ fs[i.data]? = some v) ∧
      (i.op = .recordSet → ∀ w, c.canonical i.b = some w →
        ∃ fs wv, ρ x = some (.record fs) ∧ c.value ρ w = some wv ∧ v = .record (fs.set i.data wv))) ∧
  (∀ i v, c.f.insts[u]? = some i → i.op = .phi → ρ u = some v →
    ∃ e x, e ∈ c.extraOf i.data ∧ c.canonical e = some x ∧ c.value ρ x = some v)

/-- Each projection of `l` holds its operand's current part. -/
def FreshHold (c : Fn) (ρ : Env) (l : List Nat) : Prop := ∀ u, u ∈ l → ProjHolds c ρ u

/-- The fresh reads after a block hold their operands' parts at its end. -/
theorem fresh_killed {c : Fn} {p : Nat} {ρ ρ' : Env} (hH : HomesExact c) (hstep : c.BlockStep p ρ ρ') {l : List Nat}
    (hF : FreshHold c ρ l) : FreshHold c ρ' (c.freshOut c.blockOf p l) := by
  have hL : ∀ r, c.Lists p r → Fn.listedIn c.blockOf p r = true := fun r h => (hH p r).2 h
  intro u hu
  refine ⟨fun i x v hi hx hv => ?_, fun i v hi hop hv => ?_⟩
  · cases hproj : Fn.projection i.op
    · refine ⟨fun hop => ?_, fun hop => ?_, fun hop => ?_⟩ <;> simp [Fn.projection, hop] at hproj
    · cases hl : Fn.listedIn c.blockOf p u
      · obtain ⟨hul, hk⟩ := kept_of_mem hu hl hL
        rw [step_same hH hstep hl] at hv
        rw [step_same hH hstep (kept_projection hk hi hproj hx)]
        obtain ⟨h1, h2, h3⟩ := (hF u hul).1 i x v hi hx hv
        refine ⟨h1, h2, fun hop w hw => ?_⟩
        obtain ⟨fs, wv, hfs, hwv, hve⟩ := h3 hop w hw
        refine ⟨fs, wv, hfs, ?_, hve⟩
        rw [value_same (step_same hH hstep (kept_store hk hi hop hx hw))]
        exact hwv
      · have hd := (step_def hH hstep hl hv).1
        unfold Fn.Defines at hd; rw [hi] at hd
        refine ⟨fun hop => ?_, fun hop => ?_, fun hop w hw => ?_⟩
        · obtain ⟨x', j, hx', hj, hve⟩ := hd.2.2.1 hop
          rw [hx] at hx'; cases hx'
          exact ⟨j, hve, hj⟩
        · obtain ⟨x', fs, hx', hfs, hve⟩ := hd.2.2.2.2.1 hop
          rw [hx] at hx'; cases hx'
          exact ⟨fs, hfs, hve⟩
        · obtain ⟨x', w', fs, wv, hx', hw', hfs, hwv, hve⟩ := hd.2.2.2.2.2.1 hop
          rw [hx] at hx'; cases hx'
          rw [hw] at hw'; cases hw'
          exact ⟨fs, wv, hfs, hwv, hve⟩
  · have hkept : c.operandsKept c.blockOf p u = true := by
      rcases mem_freshOut hu with h' | h'
      · exact h'.2
      · exact (mem_tagReads h').2 (by simp [Fn.instOp, hi, hop])
    cases hl : Fn.listedIn c.blockOf p u
    · obtain ⟨hul, _⟩ := kept_of_mem hu hl hL
      rw [step_same hH hstep hl] at hv
      obtain ⟨e, x, he, hx, hxv⟩ := (hF u hul).2 i v hi hop hv
      refine ⟨e, x, he, hx, ?_⟩
      rw [value_same (step_same hH hstep (kept_phi hkept hi hop he hx))]
      exact hxv
    · have hd := (step_def hH hstep hl hv).1
      unfold Fn.Defines at hd; rw [hi] at hd
      obtain ⟨e, x, he, hx, hxv⟩ := hd.2.2.2.2.2.2 hop
      refine ⟨e, x, he, hx, ?_⟩
      rw [value_same (step_same hH hstep (kept_phi hkept hi hop he hx))]
      exact hxv

theorem fresh_of_implies {c : Fn} {ρ : Env} {a b : TagFacts} (h : implies a b = true) (hb : FreshHold c ρ b.fresh) :
    FreshHold c ρ a.fresh := by
  unfold implies at h
  simp only [Bool.and_eq_true, List.all_eq_true] at h
  intro u hu
  exact hb u (by simpa using h.2 u hu)

theorem applyTest_fresh {c : Fn} {plain : TagFacts} {e : Option Fn.EdgeTest} : (c.applyTest plain e).fresh = plain.fresh := by
  match e with
  | none => rfl
  | some (.within _ _ _) => rfl
  | some (.equal _ _ _ _) => rfl

theorem freshKey_holds {c : Fn} {ρ' : Env} (hT : TypedHold c ρ') {fresh : List Nat} (hF : FreshHold c ρ' fresh)
    {raw : Option Nat} {k n r a : Nat} (hf : c.freshKey fresh raw = some (k, n))
    (hr : c.canonical raw = some r) (hv : c.value ρ' r = some (.int a)) :
    Fn.keyTag ρ' k = some a ∧ a < n := by
  obtain ⟨i, hi, hc1, hc2⟩ := canonical_spec hr
  have hself := canonical_self hi hc1 hc2
  unfold Fn.freshKey at hf
  have htk : c.tagKey raw = c.tagKey (some r) := by unfold Fn.tagKey; rw [hr, hself]
  rw [hr] at hf
  cases hkey : c.tagKey raw with
  | none => rw [hkey] at hf; simp at hf
  | some kn =>
    rw [hkey] at hf
    obtain ⟨k', n'⟩ := kn
    simp only at hf
    have hk2 := hkey
    unfold Fn.tagKey at hk2
    rw [hr] at hk2
    simp only [Option.bind_eq_bind, Option.bind_some, hi] at hk2
    split at hk2
    · -- a union_tag read
      rename_i hop
      have hop' : i.op ≠ .listGetField := by rw [hop]; decide
      have hinst : c.instOp r = i.op := by simp [Fn.instOp, hi]
      rw [hinst] at hf
      simp only [hop, reduceCtorEq, ite_false, beq_iff_eq] at hf
      split at hf
      · rename_i hfr
        simp at hf; obtain ⟨rfl, rfl⟩ := hf
        cases hx : c.canonical i.a with
        | none => rw [hx] at hk2; simp at hk2
        | some x =>
          rw [hx] at hk2
          simp only [Option.bind_some] at hk2
          cases hxi : c.f.insts[x]? with
          | none => rw [hxi] at hk2; simp at hk2
          | some xi =>
            rw [hxi] at hk2
            simp only [Option.bind_some] at hk2
            cases hn : c.unionCases xi.ty with
            | none => rw [hn] at hk2; simp at hk2
            | some n0 =>
              rw [hn] at hk2
              simp at hk2; obtain ⟨rfl, rfl⟩ := hk2
              have hvr : ρ' r = some (.int a) := by rw [← value_of_not_const (ρ := ρ') hi (by rw [hop]; decide)]; exact hv
              have hxv : ρ' x = some (.union a) := by
                obtain ⟨t, ht, hx2⟩ := ((hF r (by simpa using hfr)).1 i x _ hi hx hvr).1 hop
                cases ht; exact hx2
              obtain ⟨j, hj, hje⟩ := (hT x _ hxv).1 xi n0 hxi hn
              cases hje
              exact ⟨by simp [Fn.keyTag, hxv], hj⟩
      · simp at hf
    · -- a list_get_field read
      rename_i hop
      have hinst : c.instOp r = .listGetField := by simp [Fn.instOp, hi, hop]
      rw [hinst] at hf
      simp at hf; obtain ⟨rfl, rfl⟩ := hf
      simp only [Option.bind_eq_some_iff] at hk2
      obtain ⟨_, _, _, _, _, _, ⟨_, tagOf⟩, _, hk4⟩ := hk2
      split at hk4
      · simp at hk4
      · simp only [Option.bind_eq_some_iff, pure, Option.some.injEq, Prod.mk.injEq] at hk4
        obtain ⟨n0, hn0, rfl, rfl⟩ := hk4
        have hvr : ρ' r = some (.int a) := by rw [← value_of_not_const (ρ := ρ') hi (by rw [hop]; decide)]; exact hv
        obtain ⟨t, ht, hte⟩ := (hT r _ hvr).2 r n0 hinst (by rw [← htk]; exact hkey)
        cases hte
        exact ⟨by simp [Fn.keyTag, hvr], ht⟩
    · simp at hk2


theorem holds_iff {v : RVal} {s T E a b d : Nat} (hne : T ≠ E)
    (hs : (v = .int 1 ∧ s = T) ∨ (v = .int 0 ∧ s = E)) (hv : v = .int (if decide (a = b) = decide (d = 0) then 1 else 0)) :
    (((s == T) == (d == 0)) = true ↔ a = b) := by
  subst hv
  rcases hs with ⟨h1, rfl⟩ | ⟨h1, rfl⟩
  · simp only [RVal.int.injEq] at h1
    split at h1
    · rename_i h; simp only [beq_self_eq_true]; by_cases hd : d = 0 <;> simp_all
    · omega
  · simp only [RVal.int.injEq] at h1
    split at h1
    · omega
    · rename_i h
      have : (s == T) = false := by simpa using fun h' => hne h'.symm
      rw [this]; by_cases hd : d = 0 <;> simp_all

theorem mask_bit {H : Bool} {t n d : Nat} (hn : t < n) (hH : H = true ↔ t = d) :
    (if H = true then caseMask n d &&& allCases n else allCases n ^^^ (caseMask n d &&& allCases n)).testBit t = true := by
  have hall := testBit_allCases hn
  split
  · rename_i h; have := hH.1 h; subst this
    simp [Nat.testBit_and, testBit_caseMask_self hn, hall]
  · rename_i h
    have hne : t ≠ d := fun e => h (hH.2 e)
    have hcm : (caseMask n d).testBit t = false := by
      cases hb : (caseMask n d).testBit t
      · rfl
      · exact absurd (testBit_caseMask hb) hne
    simp [Nat.testBit_xor, Nat.testBit_and, hcm, hall]

theorem value_const {c : Fn} {ρ : Env} {y : Nat} {ci : Inst} (hi : c.f.insts[y]? = some ci) (hop : ci.op = .iconst) :
    c.value ρ y = some (.int ci.data) := by
  simp [Fn.value, hi, hop]

theorem edgeTest_holds {c : Fn} {p s : Nat} {ρ ρ' : Env} (hH : HomesExact c) (hstep : c.BlockStep p ρ ρ')
    (hT : TypedHold c ρ') {fresh : List Nat} (hF : FreshHold c ρ' fresh) (htk : c.Takes p ρ' s) :
    EdgeHolds ρ' (c.edgeTest c.blockOf p fresh s) := by
  cases h : c.edgeTest c.blockOf p fresh s with
  | none => trivial
  | some e =>
  unfold Fn.edgeTest at h
  split at h
  · rename_i lr hlr
    split at h
    · rename_i last hlast
      simp only at h
      split at h
      · simp at h
      · rename_i hbr
        split at h
        · simp at h
        · rename_i hth
          simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq, not_or, Decidable.not_not] at hbr
          obtain ⟨blk, hblk, hback⟩ : ∃ blk, c.f.blocks[p]? = some blk ∧ blk.insts.back? = some (some lr) := by
            cases hb : c.f.blocks[p]? with
            | none => rw [hb] at hlr; simp at hlr
            | some blk => rw [hb] at hlr; exact ⟨blk, rfl, hlr⟩
          -- the run's branch: its condition's integer names the side
          obtain ⟨blk', lr', last', hblk', hback', hlast', hgo⟩ := htk
          rw [hblk] at hblk'; cases hblk'
          rw [hback] at hback'; cases hback'
          rw [hlast] at hlast'; cases hlast'
          have hside : ∃ cr, c.canonical last.a = some cr ∧
              ((c.value ρ' cr = some (.int 1) ∧ s = (branchTargets last.data).1) ∨
               (c.value ρ' cr = some (.int 0) ∧ s = (branchTargets last.data).2)) := by
            rcases hgo with ⟨hj, _⟩ | ⟨_, hb⟩
            · rw [hbr.1] at hj; cases hj
            · exact hb
          obtain ⟨cr, hcr, hsd⟩ := hside
          unfold Fn.testedHere at hth
          rw [hcr] at hth
          simp only [Bool.not_eq_true', Bool.not_eq_false] at hth
          rw [hcr, show (some cr >>= c.inst?) = c.inst? cr from rfl] at h
          cases hci : c.inst? cr with
          | none => rw [hci] at h; simp at h
          | some cnd =>
          rw [hci] at h
          simp only at h
          split at h
          · simp at h
          · rename_i hcmp
            simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, decide_eq_true_eq, not_or, Decidable.not_not, Nat.not_lt] at hcmp
            have hcri : c.f.insts[cr]? = some cnd := hci
            -- the comparison's operands and its value
            obtain ⟨v, hv1, hv2⟩ : ∃ v, ρ' cr = some v ∧ ((v = .int 1 ∧ s = (branchTargets last.data).1) ∨
                (v = .int 0 ∧ s = (branchTargets last.data).2)) := by
              rw [value_of_not_const hcri (by rw [hcmp.1]; decide)] at hsd
              rcases hsd with ⟨h1, h2⟩ | ⟨h1, h2⟩
              · exact ⟨_, h1, Or.inl ⟨rfl, h2⟩⟩
              · exact ⟨_, h1, Or.inr ⟨rfl, h2⟩⟩
            have hd := (hstep.2 cr v ((hH p cr).1 hth) hv1).1
            unfold Fn.Defines at hd
            rw [hcri] at hd
            obtain ⟨x, y, a, b, hx, hy, hxa, hyb, hve⟩ := hd.2.2.2.1 hcmp.1 hcmp.2
            have hiff := holds_iff hbr.2 hv2 hve
            generalize ((s == (branchTargets last.data).fst) == (cnd.data == 0)) = H at h hiff
            cases hl : c.freshKey fresh cnd.a with
            | some lkn =>
              obtain ⟨lk, ln⟩ := lkn
              obtain ⟨hlk, hla⟩ := freshKey_holds hT hF hl hx hxa
              cases hr : c.freshKey fresh cnd.b with
              | some rkn =>
                obtain ⟨rk, rn⟩ := rkn
                obtain ⟨hrk, _⟩ := freshKey_holds hT hF hr hy hyb
                rw [hl, hr] at h
                simp only at h
                split at h
                · rename_i hc
                  simp only [Bool.and_eq_true, beq_iff_eq, bne_iff_ne, ne_eq] at hc
                  simp at h; subst h
                  have hab := hiff.1 hc.1.1
                  subst hab
                  exact ⟨a, hlk, hrk, hla, hc.1.2.symm⟩
                · simp at h
              | none =>
                rw [hl, hr] at h
                simp only [Option.isSome_some, ite_true] at h
                rw [hy, show (some y >>= c.inst?) = c.inst? y from rfl] at h
                cases hyi : c.inst? y with
                | none => rw [hyi] at h; simp at h
                | some ci =>
                  rw [hyi] at h
                  simp only at h
                  split at h
                  · rename_i hk
                    simp only [beq_iff_eq] at hk
                    simp at h; subst h
                    rw [value_const (ρ := ρ') hyi hk] at hyb; cases hyb
                    exact ⟨a, hlk, hla, mask_bit hla hiff⟩
                  · simp at h
            | none =>
              cases hr : c.freshKey fresh cnd.b with
              | some rkn =>
                obtain ⟨rk, rn⟩ := rkn
                obtain ⟨hrk, hrb⟩ := freshKey_holds hT hF hr hy hyb
                rw [hl, hr] at h
                simp only [Option.isSome_none, Bool.false_eq_true, ite_false] at h
                rw [hx, show (some x >>= c.inst?) = c.inst? x from rfl] at h
                cases hxi : c.inst? x with
                | none => rw [hxi] at h; simp at h
                | some ci =>
                  rw [hxi] at h
                  simp only at h
                  split at h
                  · rename_i hk
                    simp only [beq_iff_eq] at hk
                    simp at h; subst h
                    rw [value_const (ρ := ρ') hxi hk] at hxa; cases hxa
                    exact ⟨b, hrk, hrb, mask_bit hrb (by rw [hiff]; exact eq_comm)⟩
                  · simp at h
              | none => rw [hl, hr] at h; simp at h
    · simp at h
  · simp at h


/-- What a run's registers keep true at every block boundary: types and `union_make` cases. -/
def Inv (c : Fn) (ρ : Env) : Prop := TypedHold c ρ ∧ MakesHold c ρ

theorem takes_succ {c : Fn} {p s : Nat} {ρ : Env} (h : c.Takes p ρ s) : s ∈ c.succList p ∧ p < c.f.blocks.size := by
  obtain ⟨blk, lr, last, hblk, hback, hlast, hgo⟩ := h
  have hp : p < c.f.blocks.size := by
    rcases Nat.lt_or_ge p c.f.blocks.size with h | h
    · exact h
    · simp [h] at hblk
  refine ⟨?_, hp⟩
  unfold Fn.succList Fn.successors
  rw [hblk]
  simp only [hback, hlast]
  rcases hgo with ⟨hj, rfl⟩ | ⟨hb, _, _, hside⟩
  · simp [hj]
  · have : last.op ≠ .jump := by rw [hb]; decide
    rcases hside with ⟨_, rfl⟩ | ⟨_, rfl⟩ <;> simp [hb]

theorem step_inv {c : Fn} {p : Nat} {ρ ρ' : Env} (hH : HomesExact c) (hI : Inv c ρ) (hstep : c.BlockStep p ρ ρ') :
    Inv c ρ' := by
  obtain ⟨hT, hM⟩ := hI
  refine ⟨fun r v hv => ?_, fun r i v hi hop hv => ?_⟩
  · cases hl : Fn.listedIn c.blockOf p r
    · rw [step_same hH hstep hl] at hv; exact hT r v hv
    · exact (step_def hH hstep hl hv).2
  · cases hl : Fn.listedIn c.blockOf p r
    · rw [step_same hH hstep hl] at hv; exact hM r i v hi hop hv
    · have hd := (step_def hH hstep hl hv).1
      unfold Fn.Defines at hd; rw [hi] at hd
      exact hd.1 hop

theorem tagOKWith_spec {c : Fn} {E : Array (Option TagFacts)} (h : c.tagOKWith E = true) :
    HomesExact c ∧ E.size = c.f.blocks.size ∧
    (0 < c.f.blocks.size → ∃ F, E[0]! = some F ∧ F.masks = [] ∧ F.pairs = [] ∧ F.fresh = []) ∧
    (∀ p < c.f.blocks.size, ∀ F, E[p]! = some F → c.readsOK E p = true ∧
      ∀ s ∈ c.succList p, s ≥ c.f.blocks.size ∨ ∃ A, E[s]! = some A ∧ implies A (c.tagEdge c.blockOf p F s) = true) := by
  unfold Fn.tagOKWith at h
  simp only [Bool.and_eq_true, beq_iff_eq, Bool.or_eq_true, List.all_eq_true, List.mem_range] at h
  obtain ⟨⟨⟨hh, hs⟩, h0⟩, hp⟩ := h
  refine ⟨homes_exact hh, hs, fun hn => ?_, fun p hp' F hF => ?_⟩
  · rcases h0 with h0 | h0
    · omega
    · split at h0
      · rename_i F hF
        simp only [Bool.and_eq_true, List.isEmpty_iff] at h0
        exact ⟨F, hF, h0.1.1, h0.1.2, h0.2⟩
      · simp at h0
  · have := hp p hp'
    rw [hF] at this
    simp only [Bool.and_eq_true, List.all_eq_true, Bool.or_eq_true, decide_eq_true_eq] at this
    refine ⟨this.1, fun s hs' => ?_⟩
    rcases this.2 s hs' with h | h
    · left; exact h
    · right
      split at h
      · rename_i A hA; exact ⟨A, hA, h⟩
      · simp at h

/-- What every run keeps at the entry of each block it reaches: the invariants, and the checker's facts for the block,
fresh tag reads included. -/
theorem exec_inv {c : Fn} {E : Array (Option TagFacts)} (hE : c.tagOKWith E = true) {s : Nat} {ρ : Env}
    (hx : c.Exec s ρ) : Inv c ρ ∧
      (s < c.f.blocks.size → ∃ A, E[s]! = some A ∧ Fn.Sat ρ A ∧ FreshHold c ρ A.fresh) := by
  obtain ⟨hH, _, h0, hall⟩ := tagOKWith_spec hE
  induction hx with
  | start hρ =>
    refine ⟨⟨fun r v hv => (hρ r v hv).2, fun r i v hi hop hv => ?_⟩, ?_⟩
    · have := (hρ r v hv).1; simp [Fn.instOp, hi, hop] at this
    · intro hn
      obtain ⟨F, hF, hm, hp, hf⟩ := h0 hn
      exact ⟨F, hF, ⟨by simp [hm], by simp [hp]⟩, by intro u hu; simp [hf] at hu⟩
  | step hprev hstep htk ih =>
    rename_i p s' ρ0 ρ1
    obtain ⟨hI, hS⟩ := ih
    obtain ⟨hsucc, hp⟩ := takes_succ htk
    have hI' := step_inv hH hI hstep
    refine ⟨hI', fun hs => ?_⟩
    obtain ⟨F, hF, hsat, hfr⟩ := hS hp
    rcases (hall p hp F hF).2 s' hsucc with h | ⟨A, hA, himp⟩
    · omega
    · have hK := sat_killed (c := c) hsat (fun r h => step_same hH hstep h)
      have hKf := fresh_killed hH hstep hfr
      refine ⟨A, hA, sat_of_implies himp ?_, fresh_of_implies himp ?_⟩
      · exact sat_applyTest hK hI'.2 (edgeTest_holds hH hstep hI'.1 hKf htk)
      · unfold Fn.tagEdge
        simp only
        rw [applyTest_fresh]
        exact hKf

theorem testBit_foldl_or {j : Nat} {f : Option Nat → Nat} : ∀ (l : List (Option Nat)) (init : Nat),
    (init.testBit j = true ∨ ∃ e ∈ l, (f e).testBit j = true) →
    (l.foldl (fun acc e => acc ||| f e) init).testBit j = true := by
  intro l
  induction l with
  | nil => intro init h; simpa using h
  | cons e rest ih =>
    intro init h
    simp only [List.foldl_cons]
    apply ih
    rcases h with h | ⟨e', he', hb⟩
    · left; simp [Nat.testBit_or, h]
    · simp only [List.mem_cons] at he'
      rcases he' with rfl | he'
      · left; simp [Nat.testBit_or, hb]
      · right; exact ⟨e', he', hb⟩

/-- What a value can be at a block's end, through the fresh `phi`s it merges, holds its case on every run. -/
theorem possibleAt_bit {c : Fn} {b : Nat} {ρ ρ' : Env} {F : TagFacts} {out : List Nat} (hH : HomesExact c)
    (hstep : c.BlockStep b ρ ρ') (hsat : MasksHold ρ F.masks) (hM : MakesHold c ρ) (hM' : MakesHold c ρ')
    (hFo : FreshHold c ρ' out) {n j : Nat} (hj : j < n) :
    ∀ fuel x, ρ' x = some (.union j) → (c.possibleAt c.blockOf F b out fuel x n).testBit j = true := by
  have base : ∀ x, ρ' x = some (.union j) →
      (c.possible (if Fn.listedIn c.blockOf b x = true then [] else F.masks) x n).testBit j = true := by
    intro x hx
    cases hl : Fn.listedIn c.blockOf b x
    · have hρx : ρ x = some (.union j) := by rw [← step_same hH hstep hl]; exact hx
      simpa using possible_tag hsat hM (by simp [Fn.keyTag, hρx]) hj
    · simpa using possible_tag (by intro _ _ h; simp at h) hM' (by simp [Fn.keyTag, hx]) hj
  intro fuel
  induction fuel with
  | zero => intro x hx; exact base x hx
  | succ k ih =>
    intro x hx
    unfold Fn.possibleAt
    split
    · rename_i xi hxi
      split
      · rename_i hcond
        simp only [Bool.and_eq_true, beq_iff_eq] at hcond
        obtain ⟨e, y, he, hy, hyv⟩ := (hFo x (by simpa using hcond.2)).2 xi _ hxi hcond.1 hx
        apply testBit_foldl_or
        right
        refine ⟨e, he, ?_⟩
        rw [hy]
        exact ih y (value_union hyv)
      · exact base x hx
    · exact base x hx

/-- **F-VL-10.** When the checker's tag facts are verified, every run that runs block `b` (from registers `ρ` to `ρ'`) and
reads there, by a `union_payload k` or `union_take k`, a value that is not a `list_get` (shape M) holding a union value of
case `j`, has `j = k`. -/
theorem payload_under_tag {c : Fn} {E : Array (Option TagFacts)} (hE : c.tagOKWith E = true) {b : Nat} {ρ ρ' : Env}
    (hx : c.Exec b ρ) (hstep : c.BlockStep b ρ ρ') {blk : Block} (hblk : c.f.blocks[b]? = some blk) {r : Nat}
    (he : some r ∈ blk.insts) {i : Inst} (hi : c.f.insts[r]? = some i) (hop : i.op = .unionPayload ∨ i.op = .unionTake)
    {v : Nat} (hv : c.canonical i.a = some v) (hm : c.instOp v ≠ .listGet) {j : Nat} (hval : ρ' v = some (.union j)) :
    j = i.data := by
  have hb : b < c.f.blocks.size := by
    rcases Nat.lt_or_ge b c.f.blocks.size with h | h
    · exact h
    · simp [h] at hblk
  obtain ⟨hH, hsz, _, hall⟩ := tagOKWith_spec hE
  obtain ⟨hI, hS⟩ := exec_inv hE hx
  obtain ⟨F, hF, hsat, hfr⟩ := hS hb
  have hI' := step_inv hH hI hstep
  -- the checker's verdict on this read is not a refusal
  have hread := (hall b hb F hF).1
  unfold Fn.readsOK at hread
  rw [hblk] at hread
  simp only [Option.map_some, Option.getD_some, Array.all_eq_true] at hread
  obtain ⟨idx, hidx, hget⟩ := Array.mem_iff_getElem.1 he
  have := hread idx hidx
  rw [hget] at this
  simp only [Option.bind_some, hi, Bool.or_eq_true, Bool.and_eq_true, bne_iff_ne, ne_eq] at this
  have hverd : c.readVerdict c.blockOf E b i ≠ some false := by
    rcases this with ⟨h1, h2⟩ | h
    · rcases hop with h | h
      · exact absurd h h1
      · exact absurd h h2
    · simpa using h
  have hby : c.byFacts c.blockOf E b v i = true := by
    unfold Fn.readVerdict at hverd
    rw [hv] at hverd
    simp only at hverd
    split at hverd
    · assumption
    · split at hverd
      · rename_i hl; simp at hl; exact absurd hl hm
      · simp at hverd
  have hEb : (E[b]?.join).getD {} = F := by
    have h1 : E[b]'(by omega) = some F := by rw [← getElem!_pos E b (by omega)]; exact hF
    have : E[b]? = some (some F) := by rw [Array.getElem?_eq_getElem (by omega), h1]
    simp [this]
  have hnz : F.masks.any (·.2 == 0) = false := by
    cases h : F.masks.any (·.2 == 0)
    · rfl
    · exfalso
      simp only [List.any_eq_true, beq_iff_eq] at h
      obtain ⟨⟨k, m⟩, hk, hm0⟩ := h
      simp only at hm0; subst hm0
      obtain ⟨t, _, hbit⟩ := hsat.1 k 0 hk
      simp at hbit
  obtain ⟨vi, hvi, _, _⟩ := canonical_spec hv
  unfold Fn.byFacts at hby
  rw [hEb] at hby
  simp only [hnz, Bool.false_eq_true, ite_false, hvi, Option.bind_some] at hby
  cases hn : c.unionCases vi.ty with
  | none => rw [hn] at hby; simp at hby
  | some n =>
    rw [hn] at hby
    obtain ⟨j', hj', hjj⟩ := (hI'.1 v _ hval).1 vi n hvi hn
    cases hjj
    simp only [Bool.or_eq_true, beq_iff_eq] at hby
    rcases hby with ((hby | htw) | hph) | hst
    · cases hl : Fn.listedIn c.blockOf b v
      · rw [hl] at hby
        simp only [Bool.false_eq_true, ite_false] at hby
        have hρv : ρ v = some (.union j) := by rw [← step_same hH hstep hl]; exact hval
        exact testBit_caseMask (testBit_and_eq hby
          (possible_tag hsat.1 hI.2 (by simp [Fn.keyTag, hρv]) hj'))
      · rw [hl] at hby
        simp only [ite_true] at hby
        exact testBit_caseMask (testBit_and_eq hby
          (possible_tag (by intro _ _ h; simp at h) hI'.2 (by simp [Fn.keyTag, hval]) hj'))
    · -- shape R: another fresh `record_get` of the same record and field holds the same value
      unfold Fn.twinJustified at htw
      rw [hvi] at htw
      simp only [Bool.and_eq_true, beq_iff_eq] at htw
      obtain ⟨hrg, htw⟩ := htw
      split at htw
      · rename_i base hbase
        simp only [Bool.and_eq_true, List.any_eq_true] at htw
        obtain ⟨hvout, u, huout, hu⟩ := htw
        split at hu
        · rename_i ui hui
          simp only [Bool.and_eq_true, bne_iff_ne, ne_eq, beq_iff_eq, Bool.not_eq_true'] at hu
          obtain ⟨_, ⟨⟨⟨hurg, hud⟩, hlu⟩, hub⟩, hcond⟩ := hu
          have hFo := fresh_killed hH hstep hfr
          obtain ⟨fs, hfs, hvj⟩ := ((hFo v (by simpa using hvout)).1 vi base _ hvi hbase hval).2.1 hrg
          have hbit : (c.possible F.masks u n).testBit j = true := by
            cases hw : ρ u with
            | none =>
              have hlk : lookupMask F.masks u = none := by
                cases hlk : lookupMask F.masks u with
                | none => rfl
                | some m =>
                  obtain ⟨t, ht, _⟩ := hsat.1 u m (lookupMask_mem hlk)
                  simp [Fn.keyTag, hw] at ht
              have hnm : ui.op ≠ .unionMake := by rw [hurg]; decide
              simp [Fn.possible, hui, hnm, hlk, testBit_allCases hj']
            | some w =>
              have hρ'u : ρ' u = some w := by rw [step_same hH hstep hlu]; exact hw
              obtain ⟨fs', hfs', hw'⟩ := ((hFo u huout).1 ui base w hui hub hρ'u).2.1 hurg
              rw [hfs] at hfs'; cases hfs'
              rw [hud, hvj] at hw'; cases hw'
              exact possible_tag hsat.1 hI.2 (by simp [Fn.keyTag, hw]) hj'
          exact testBit_caseMask (testBit_and_eq hcond hbit)
        · simp at hu
      · simp at htw
    · -- shape P: a fresh `phi` holds one of its operands as they are now
      unfold Fn.phiJustified at hph
      rw [hvi] at hph
      simp only [Bool.and_eq_true, beq_iff_eq] at hph
      exact testBit_caseMask (testBit_and_eq hph.2
        (possibleAt_bit hH hstep hsat.1 hI.2 hI'.2 (fresh_killed hH hstep hfr) hj' _ _ hval))
    · -- shape S: a `record_get` of a fresh `record_set` of the same field reads the stored value
      unfold Fn.storeJustified at hst
      rw [hvi] at hst
      simp only [Bool.and_eq_true, beq_iff_eq] at hst
      obtain ⟨hrg, hst⟩ := hst
      split at hst
      · rename_i x hx
        split at hst
        · rename_i xi hxi
          simp only [Bool.and_eq_true, beq_iff_eq, Option.isSome_iff_exists] at hst
          obtain ⟨⟨⟨⟨⟨hset, hdata⟩, ⟨x0, hx0⟩⟩, hvout⟩, hxout⟩, hw⟩ := hst
          split at hw
          · rename_i w hwc
            have hFo := fresh_killed hH hstep hfr
            obtain ⟨fs, hfs, hvj⟩ := ((hFo v (by simpa using hvout)).1 vi x _ hvi hx hval).2.1 hrg
            obtain ⟨fs0, wv, _, hwv, hrec⟩ := ((hFo x (by simpa using hxout)).1 xi x0 _ hxi hx0 hfs).2.2 hset w hwc
            cases hrec
            rw [← hdata] at hvj
            have hwvj : wv = .union j := by
              simp [List.getElem?_set] at hvj
              exact hvj.2
            subst hwvj
            have hρ'w := value_union hwv
            cases hl : Fn.listedIn c.blockOf b w
            · simp only [hl, Bool.false_eq_true, ite_false, beq_iff_eq] at hw
              have hρw : ρ w = some (.union j) := by rw [← step_same hH hstep hl]; exact hρ'w
              exact testBit_caseMask (testBit_and_eq hw (possible_tag hsat.1 hI.2 (by simp [Fn.keyTag, hρw]) hj'))
            · simp only [hl, ite_true, beq_iff_eq] at hw
              exact testBit_caseMask (testBit_and_eq hw
                (possible_tag (by intro _ _ h; simp at h) hI'.2 (by simp [Fn.keyTag, hρ'w]) hj'))
          · simp at hw
        · simp at hst
      · simp at hst

end VerifyIr
