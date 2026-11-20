import VerifyIr.Ssa

/-!
# Function values (trust point A17 of `proofs/ownership`)

A17 says: a value that reaches an indirect call was made by a `func_ref` of a function with the call's signature. This
file gives the small semantics that statement needs and the checker's typing rules it rests on.

* **Values.** `Val`: a function pointer `fn k` (function `k` of the module), an aggregate (record fields, list, array or
  box elements, dictionary entries as pairs), a tagged union value, or any other bits.
* **Well-typed values.** `Holds m fr t v`: at a function type, `v` is `fn k` for an internal function `k` whose
  signature is the type's; a record, collection or union value holds its parts at their types; at a type that holds no
  function type (`freeTy`, decided by a verified table) any value will do. Overlays (`borrowed`) are read through their
  storage type.
* **The steps.** `Reaches m g r v`: register `r` of function `g` can hold `v`. A `func_ref` makes `fn data`; a constant
  makes any value of its type, which holds no function type; a parameter receives what a call passed in that position,
  a call result what the callee returned; and every other operation's result is **built from parts of its operands**
  (`Built`, `Part`): the trusted description of what the operations do with the values they read (`AXIOMS.md`, V5 to
  V7), under which reading a union payload means reading the payload of the value's own tag (V6).

`reaches_holds`: in a module the checker accepts (every `verdict` is `ok`), every value a register can reach holds at the
register's type. `a17`: so the callee value of every `call_indirect` of a reached block is `fn k` for an internal
function `k` whose signature is the callee's type, whose result is the call's type and whose parameters are the types of
the call's arguments.
-/

namespace VerifyIr

/-! ## Function-free types -/

/-- Type `t` holds no function type, by the table `fr` of the compound types (a leaf holds none). -/
def freeTy (fr : Array Bool) (t : Ty) : Bool := !Ty.isCompound t || (fr[t - Ty.firstCompound]?.getD false)

namespace Module
variable (m : Module)

/-- What compound `i` needs of the table to hold no function type. -/
def freeStep (fr : Array Bool) (i : Nat) : Bool :=
  match m.compounds[i]? with
  | some (.fn _) => false
  | some (.record ps) | some (.union ps) => ps.all (freeTy fr)
  | some (.list e) | some (.listView e) | some (.box e) | some (.borrowed e) | some (.array e _ _) => freeTy fr e
  | some (.dict k v) => freeTy fr k && freeTy fr v
  | none => false

/-- The greatest such table, by iteration from "every compound is free" (untrusted: `freeOK` verifies it). -/
def freeTable : Array Bool := Id.run do
  let n := m.compounds.size
  let mut fr := Array.replicate n true
  for _ in [0:n + 1] do
    let mut changed := false
    for i in [0:n] do
      if fr[i]! && !(m.freeStep fr i) then
        fr := fr.set! i false
        changed := true
    if !changed then break
  return fr

/-- The table is a fixed point: each entry is what its compound's parts give. -/
def freeOK (fr : Array Bool) : Bool :=
  fr.size == m.compounds.size && (List.range fr.size).all fun i => fr[i]! == m.freeStep fr i

end Module

/-! ## Values and their types -/

/-- A run-time value, as far as function values go. -/
inductive Val where
  | fn (k : Nat)
  | agg (parts : List Val)
  | tagged (tag : Nat) (payload : Val)
  | other
  deriving Inhabited

/-- `e` is the element type of `t`'s storage: a list, list view, box or array of `e`. -/
def ElemOf (m : Module) (t e : Ty) : Prop :=
  m.compound? (m.storageType t) = some (.list e) ∨ m.compound? (m.storageType t) = some (.listView e) ∨
  m.compound? (m.storageType t) = some (.box e) ∨ ∃ n vec, m.compound? (m.storageType t) = some (.array e n vec)

/-- `v` is a well-typed value of type `t` as far as function values go. -/
inductive Holds (m : Module) (fr : Array Bool) : Ty → Val → Prop where
  | free {t : Ty} {v : Val} : freeTy fr t = true → Holds m fr t v
  | fn {t : Ty} {k : Nat} {s : Signature} {g : Function} : m.compound? (m.storageType t) = some (.fn s) →
      m.functions[k]? = some g → g.sig = s → s.linkage = .internal → Holds m fr t (.fn k)
  | record {t : Ty} {fs : List Ty} {ps : List Val} : m.compound? (m.storageType t) = some (.record fs) →
      ps.length = fs.length → (∀ i (h₁ : i < fs.length) (h₂ : i < ps.length), Holds m fr fs[i] ps[i]) →
      Holds m fr t (.agg ps)
  | elems {t e : Ty} {ps : List Val} : ElemOf m t e → (∀ p ∈ ps, Holds m fr e p) → Holds m fr t (.agg ps)
  | dict {t k v : Ty} {ps : List Val} : m.compound? (m.storageType t) = some (.dict k v) →
      (∀ a b, Val.agg [a, b] ∈ ps → Holds m fr k a) → (∀ a b, Val.agg [a, b] ∈ ps → Holds m fr v b) →
      Holds m fr t (.agg ps)
  | tagged {t : Ty} {cs : List Ty} {j : Nat} {c : Ty} {p : Val} : m.compound? (m.storageType t) = some (.union cs) →
      cs[j]? = some c → Holds m fr c p → Holds m fr t (.tagged j p)

/-- `v` at type `t` is a part of `v0` at type `t0`: the value itself, the same value read through another overlay of the
same storage, a field, an element, a dictionary key or value, or the payload of the union value's own tag. -/
inductive Part (m : Module) : Ty → Val → Ty → Val → Prop where
  | same {t t' : Ty} {v : Val} : m.storageType t = m.storageType t' → Part m t v t' v
  | field {t : Ty} {fs : List Ty} {ps : List Val} {i : Nat} (h₁ : i < fs.length) (h₂ : i < ps.length) :
      m.compound? (m.storageType t) = some (.record fs) → Part m t (.agg ps) fs[i] ps[i]
  | elem {t e : Ty} {ps : List Val} {p : Val} : ElemOf m t e → p ∈ ps → Part m t (.agg ps) e p
  | key {t k v : Ty} {ps : List Val} {a b : Val} : m.compound? (m.storageType t) = some (.dict k v) →
      Val.agg [a, b] ∈ ps → Part m t (.agg ps) k a
  | value {t k v : Ty} {ps : List Val} {a b : Val} : m.compound? (m.storageType t) = some (.dict k v) →
      Val.agg [a, b] ∈ ps → Part m t (.agg ps) v b
  | payload {t : Ty} {cs : List Ty} {j : Nat} {c : Ty} {p : Val} : m.compound? (m.storageType t) = some (.union cs) →
      cs[j]? = some c → Part m t (.tagged j p) c p
  | trans {t₀ t₁ t₂ : Ty} {v₀ v₁ v₂ : Val} : Part m t₀ v₀ t₁ v₁ → Part m t₁ v₁ t₂ v₂ → Part m t₀ v₀ t₂ v₂

/-- `v` at type `t` is built from parts of the operands `ins` (type and value of each). -/
inductive Built (m : Module) (fr : Array Bool) (ins : List (Ty × Val)) : Ty → Val → Prop where
  | free {t : Ty} {v : Val} : freeTy fr t = true → Built m fr ins t v
  | part {t₀ t : Ty} {v₀ v : Val} : (t₀, v₀) ∈ ins → Part m t₀ v₀ t v → Built m fr ins t v
  | record {t : Ty} {fs : List Ty} {ps : List Val} : m.compound? (m.storageType t) = some (.record fs) →
      ps.length = fs.length → (∀ i (h₁ : i < fs.length) (h₂ : i < ps.length), Built m fr ins fs[i] ps[i]) →
      Built m fr ins t (.agg ps)
  | elems {t e : Ty} {ps : List Val} : ElemOf m t e → (∀ p ∈ ps, Built m fr ins e p) → Built m fr ins t (.agg ps)
  | dict {t k v : Ty} {ps : List Val} : m.compound? (m.storageType t) = some (.dict k v) →
      (∀ a b, Val.agg [a, b] ∈ ps → Built m fr ins k a) → (∀ a b, Val.agg [a, b] ∈ ps → Built m fr ins v b) →
      Built m fr ins t (.agg ps)
  | tagged {t : Ty} {cs : List Ty} {j : Nat} {c : Ty} {p : Val} : m.compound? (m.storageType t) = some (.union cs) →
      cs[j]? = some c → Built m fr ins c p → Built m fr ins t (.tagged j p)

/-! ## The declarative typing check -/

namespace Fn
variable (c : Fn)

/-- The constants that make values from nothing: an integer, float or text constant, or an undefined value. -/
def madeFromNothing : Op → Bool
  | .iconst | .fconst | .strConst | .undef => true
  | _ => false

/-- The typing rules the function-value lemmas read, restated over the whole table and every listed instruction of a
reached block of the translation: each one's signature, and a constant made from nothing has a type that holds no
function type. -/
def typedCheck (fr : Array Bool) : Bool :=
  let r := c.translate.reach
  (c.f.insts.toList.all fun i => !i.op.isConstant ||
    (c.sigOk (c.shape i) && (!madeFromNothing i.op || freeTy fr i.ty))) &&
  ((List.range c.f.blocks.size).all fun d => !(r[d]?.getD false) ||
    (c.f.blocks[d]!).insts.all fun entry => match entry with
      | some x => match c.f.insts[x]? with
        | some i => i.op == .copy || c.sigOk (c.shape i)
        | none => false
      | none => false)

end Fn

/-- The checker's verdict on one function, with `fr` the module's function-free table (`Module.freeTable`): the mirrored
rules (header, then body), the SSA rule on the function's translation with the tree the body's rules computed
(`ssa-skeleton`), and the declarative typing check with the verified table (`typed`). The last two refuse nothing the
mirrored rules accept on the corpus; they are what the lemmas read. -/
def verdict (m : Module) (fr : Array Bool) (g : Function) : Check Unit := do
  m.checkHeader g
  let idom ← bodyIdom m g
  if !(Fn.mk m g).translate.ssaCheck idom then reject .ssa
  if !(m.freeOK fr && (Fn.mk m g).typedCheck fr) then reject .typed

end VerifyIr
