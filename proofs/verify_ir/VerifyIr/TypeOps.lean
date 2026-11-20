import VerifyIr.Types

/-!
# What a type is, in a module

The questions the verifier asks of a type (`ir.Module`'s `valid`, `storageType`, `managed`, `containsBorrow`, ...).
Each is total: where the Zig code would index the compound table out of range (it asks `kind` of a type it never
checked), the Lean answer is the one for "not a compound of that kind". The recursions that follow types use fuel of
the table's size plus two; a walk that remembers the types on its path never needs more (each step adds a new compound
to the path), and the walks that do not remember (`managed`) follow records, unions and arrays, which a valid table
cannot nest in themselves without a box or a list in between.
-/

namespace VerifyIr

namespace Module
variable (m : Module)

/-- The compound entry a type names, when it names one that exists. -/
def compound? (t : Ty) : Option Compound :=
  if Ty.isCompound t then m.compounds[t - Ty.firstCompound]? else none

/-- `t` is a type of the module: a leaf, or a compound the table holds. -/
def valid (t : Ty) : Bool := !Ty.isCompound t || decide (t - Ty.firstCompound < m.compounds.size)

/-- The kind of a compound type of the module. -/
def kind? (t : Ty) : Option Kind := (m.compound? t).map Compound.kind

/-- Fuel for walks over the type graph. -/
def fuel : Nat := m.compounds.size + 2

/-- The storage under any number of read-only overlays (`borrowed`). -/
def storageTypeF : Nat → Ty → Ty
  | 0, t => t
  | n + 1, t => match m.compound? t with
    | some (.borrowed inner) => storageTypeF n inner
    | _ => t

/-- At most one unwrap per table entry and one more, as `ir.Module.storageType` bounds its loop. -/
def storageType (t : Ty) : Ty := m.storageTypeF (m.compounds.size + 1) t

/-- A read-only overlay of storage. -/
def isBorrowed (t : Ty) : Bool := match m.compound? t with
  | some (.borrowed _) => true
  | _ => false

/-- A borrowed view: a text or bytes span, or a list view. -/
def isView (t : Ty) : Bool := Ty.isSpan t || m.kind? t == some .listView

/-- A managed leaf, collection, authority, resource or box pointer. -/
def isBlock (t : Ty) : Bool :=
  t == Ty.str || t == Ty.bytes || t == Ty.byteBuffer || t == Ty.capability || t == Ty.resource ||
  m.kind? t == some .list || m.kind? t == some .box || m.kind? t == some .dict

/-- A value that owns a managed block directly or within a field, a payload or an array element. -/
def managedF : Nat → Ty → Bool
  | 0, _ => false
  | n + 1, t =>
    if m.isBlock t then true else
    match m.compound? t with
    | some (.record fs) => fs.any (managedF n)
    | some (.union cs) => cs.any (managedF n)
    | some (.array e k _) => k != 0 && managedF n e
    | _ => false

def managed (t : Ty) : Bool := m.managedF m.fuel t

/-- Transient borrowed storage anywhere in the value: a span, an overlay, a list view, a collection of overlays, or a
record or union part that holds one. `seen` is the path of compound types being walked. -/
def containsBorrowF : Nat → List Ty → Ty → Bool
  | 0, _, _ => false
  | n + 1, seen, t =>
    if Ty.isSpan t || m.isBorrowed t then true else
    if seen.contains t then false else
    match m.compound? t with
    | some (.listView _) => true
    | some (.list e) => m.isBorrowed e
    | some (.dict _ v) => m.isBorrowed v
    | some (.record ps) | some (.union ps) => ps.any (containsBorrowF n (t :: seen))
    | _ => false

def containsBorrow (t : Ty) : Bool := m.containsBorrowF m.fuel [] t

/-- The lent element type of a collection of overlays (RB2). -/
def lentElement (t : Ty) : Option Ty := match m.compound? t with
  | some (.list e) => if m.isBorrowed e then some e else none
  | some (.dict _ v) => if m.isBorrowed v then some v else none
  | _ => none

/-- Key and value of a dictionary or of an overlay of one. -/
def dictShape (t : Ty) : Option (Ty × Ty) := match m.compound? (m.storageType t) with
  | some (.dict k v) => some (k, v)
  | _ => none

/-- The element of a list or a list view. -/
def listElement (t : Ty) : Option Ty := match m.compound? t with
  | some (.list e) | some (.listView e) => some e
  | _ => none

/-- The type a borrow projection reaches from `root`, through overlays. -/
def projectedType (root : Ty) : List Proj → Option Ty
  | [] => some root
  | st :: rest => match m.compound? (m.storageType root), st with
    | some (.record fs), .field k => match fs[k]? with
      | some f => projectedType f rest
      | none => none
    | some (.union cs), .payload k => match cs[k]? with
      | some c => if c == Ty.void then none else projectedType c rest
      | none => none
    | _, _ => none

/-- `source` is or holds storage of type `field`, through records, unions, boxes, lists, arrays and dictionaries. -/
def storageWithinF : Nat → List Ty → Ty → Ty → Bool
  | 0, _, _, _ => false
  | n + 1, seen, source, field =>
    let stored := m.storageType source
    if stored == field then true else
    if !Ty.isCompound stored || !m.valid stored then false else
    if seen.contains stored then false else
    let go := storageWithinF n (stored :: seen)
    match m.compound? stored with
    | some (.record ps) | some (.union ps) => ps.any (go · field)
    | some (.box c) | some (.list c) | some (.listView c) => go c field
    | some (.array e _ _) => go e field
    | some (.dict k v) => go k field || go v field
    | _ => false

/-- A source of type `stored` can lend borrowed-record field `field`: it holds storage of the field, or, for an option
field holding a lent projection, of one of the option's payloads (depth at most 8 below the first). -/
def lendableField : Nat → Ty → Ty → Bool
  | 0, _, _ => false
  | d + 1, stored, field =>
    if m.storageWithinF m.fuel [] stored field then true else
    match m.compound? field with
    | some (.union cs) => cs.any fun part => part != Ty.void && m.managed part && lendableField d stored part
    | _ => false

/-- A source can contain storage of the borrowed leaf's physical family. -/
def borrowCompatibleF : Nat → List Ty → Ty → Ty → Bool
  | 0, _, _, _ => false
  | n + 1, seen, source, leaf =>
    let stored := m.storageType source
    if !m.valid stored || !m.valid leaf then false else
    if m.isBorrowed leaf && stored == m.storageType leaf then true else
    let recordLend := m.isBorrowed leaf && (match m.compound? (m.storageType leaf) with
      | some (.record fs) => fs.any fun f => m.managed f && m.lendableField 10 stored f
      | _ => false)
    if recordLend then true else
    if leaf == Ty.strView && (stored == Ty.str || stored == Ty.strView) then true else
    if leaf == Ty.bytesView && (stored == Ty.bytes || stored == Ty.byteBuffer || stored == Ty.bytesView) then true else
    let viewMatch := match m.compound? leaf with
      | some (.listView e) => m.listElement stored == some e
      | _ => false
    if viewMatch then true else
    if !Ty.isCompound stored then false else
    if seen.contains stored then false else
    let go := borrowCompatibleF n (stored :: seen)
    match m.compound? stored with
    | some (.record ps) | some (.union ps) => ps.any (go · leaf)
    | some (.box c) | some (.list c) | some (.listView c) => go c leaf
    | some (.array e _ _) => go e leaf
    | some (.dict k v) => go k leaf || go v leaf
    | _ => false

def borrowCompatible (source leaf : Ty) : Bool := m.borrowCompatibleF m.fuel [] source leaf

/-- `a` is a prefix of `b`. -/
def isPrefix (a b : List Proj) : Bool := a.length ≤ b.length && b.take a.length == a

/-- A declared borrow contract is well formed (`ir.Module.validBorrow`): with no source, no path and no borrow in the
result; else the path reaches a view or an overlay of managed storage through a first field or a two-case union whose
other parts hold no borrow, every argument source can hold the leaf's storage, and every returned owner is a distinct
managed part of the result that can hold it. -/
def validBorrow (s : Signature) : Bool :=
  if s.sources.isEmpty then s.path.isEmpty && !m.containsBorrow s.ret else
  match m.projectedType s.ret s.path with
  | none => false
  | some leaf =>
    if !m.isView leaf && !m.isBorrowed leaf then false else
    let overlayOk := !m.isBorrowed leaf ||
      (let stored := m.storageType leaf
       stored != leaf && m.valid stored && m.managed stored && !m.containsBorrow stored)
    if !overlayOk then false else
    let rec spine : Nat → Ty → List Proj → Bool
      | _, _, [] => true
      | depth, cur, st :: rest => match m.compound? cur, st with
        | some (.record fs), .field k =>
          depth == 0 && k == 0 && (fs.drop 1).all (!m.containsBorrow ·) &&
            (match fs[0]? with | some f => spine (depth + 1) f rest | none => false)
        | some (.union cs), .payload k =>
          cs.length == 2 && (cs.zipIdx.all fun (c, i) => i == k || !m.containsBorrow c) &&
            (match cs[k]? with | some c => spine (depth + 1) c rest | none => false)
        | _, _ => false
    if !spine 0 s.ret s.path then false else
    s.sources.all fun src => match src with
      | .argument k => match s.params[k]? with
        | none => false
        | some p => (m.managed p || m.containsBorrow p) && m.borrowCompatible p leaf
      | .result path =>
        if path.isEmpty then false else
        if path.length > s.path.length && isPrefix s.path path then false else
        if path.length ≤ s.path.length && isPrefix path s.path then false else
        match m.projectedType s.ret path with
        | none => false
        | some owner => m.managed owner && !m.containsBorrow owner && m.borrowCompatible owner leaf

/-- Where a field path leads inside an element: the type read, and the union whose tag the last step reads (else
`void`). A step through an array selects an element, through a record a field, through a union its tag (step 0) or a
case's payload (step `k + 1`). -/
def pathTarget (start : Ty) (path : List Nat) : Option (Ty × Ty) :=
  let rec go : Ty → Ty → List Nat → Option (Ty × Ty)
    | cur, tagOf, [] => some (cur, tagOf)
    | cur, _, st :: rest => match m.compound? cur with
      | some (.array e n _) => if st < n then go e Ty.void rest else none
      | some (.record fs) => match fs[st]? with
        | some f => go f Ty.void rest
        | none => none
      | some (.union cs) =>
        if st == 0 then go Ty.u32 cur rest else
        match cs[st - 1]? with
        | some c => if c == Ty.void then none else go c Ty.void rest
        | none => none
      | _ => none
  go start Ty.void path

/-- `t` is or holds a function type, through records, unions, arrays, boxes, lists and dictionaries. -/
def holdsFnF : Nat → List Ty → Ty → Bool
  | 0, _, _ => false
  | n + 1, seen, t =>
    if seen.contains t then false else
    let go := holdsFnF n (t :: seen)
    match m.compound? t with
    | some (.fn _) => true
    | some (.record ps) | some (.union ps) => ps.any go
    | some (.array e _ _) | some (.box e) | some (.list e) | some (.listView e) | some (.borrowed e) => go e
    | some (.dict k v) => go k || go v
    | _ => false

def holdsFn (t : Ty) : Bool := m.holdsFnF m.fuel [] t

end Module

end VerifyIr
