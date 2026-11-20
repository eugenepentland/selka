import Parse

/-!
# Writing `ownership-certificate-v2`

Only the tests use this (the fixtures are generated from the examples of `CheckerTests.lean`
and the round trip `parse ∘ render` is tested).  The real exporter is the Zig compiler.
-/

namespace Own

def renderList {α : Type} (f : α → String) (l : List α) : String :=
  if l.isEmpty then "-" else ",".intercalate (l.map f)

def renderVal (v : ValId) : String := s!"%{v}"

def renderRoot : Root → String
  | .val n => s!"%{n}"
  | .caller i => s!"^{i}"
  | .slot n k => s!"%{n}.{k}"
  | .fwd n => s!"%{n}>"

def renderInst (cert : Certificate) (i : Inst) : String :=
  let dst := match i.dst with
    | some d => s!"%{d}"
    | none => "-"
  let st := match i.dst with
    | some d => cert.state d
    | none => St.none
  let ps := match i.dst with
    | some d => cert.parents d
    | none => []
  s!"inst {dst} {i.op} {i.cls.render} reads {renderList renderVal i.reads} " ++
    s!"consumes {renderList renderVal i.consumes} state {st.render} " ++
    s!"parents {renderList renderRoot ps}" ++
    (match i.slot with | some k => s!" slot {k}" | none => "") ++
    (match i.released with | some r => s!" released {r}" | none => "") ++
    (match i.taken with | some r => s!" taken {r}" | none => "") ++
    (if i.slots.isEmpty && st != .emptied then "" else s!" slots {renderList id i.slots}") ++
    (if i.cls == .call then s!" from {renderList renderVal i.fromVals}" else "") ++
    (match i.entry with | some n => s!" callee {n}" | none => "") ++
    (match i.lent with | some g => s!" lent %{g}" | none => "") ++
    (if i.noLoans then " noloans" else "") ++
    (if i.views.isEmpty then "" else s!" views {renderList renderVal i.views}") ++
    (match i.imm with | some n => s!" imm {n}" | none => "")

def renderTerm : Term → String
  | .jump b => s!"term jump b{b}"
  | .branch c t f => s!"term branch %{c} b{t} b{f}"
  | .ret none => "term ret -"
  | .ret (some v) => s!"term ret %{v}"
  | .unreachable => "term unreachable"

def renderBlock (cert : Certificate) (idx : Nat) (b : Block) : List String :=
  [s!"block b{idx} preds {renderList (fun p => s!"b{p}") b.preds}"] ++
  b.abandons.map (fun a => s!"abandon b{a.1} {renderList (fun v => s!"%{v}") a.2}") ++
  b.phis.map (fun φ =>
    s!"phi %{φ.dst} {(cert.state φ.dst).render} parents {renderList renderRoot (cert.parents φ.dst)} " ++
    s!"edges {renderList (fun e => s!"b{e.1}:%{e.2}") φ.edges}") ++
  b.insts.map (renderInst cert) ++ [renderTerm b.term]

def renderEntry (e : Entry) : List String :=
  let f := e.fn
  let unchecked := e.unchecked.getD "-"
  [s!"function {f.name} result {f.result.render} from {renderList (fun n => s!"{n}") f.from_} unchecked {unchecked}"] ++
  (f.params.zip f.paramVals).zipIdx.map (fun ((k, v), i) => s!"param {i} %{v} {k.render}") ++
  f.callees.map (fun c =>
    s!"callee {c.id} {c.name} {c.kind.render} {renderList ParamTok.render c.params} {c.result.render} " ++
    s!"{renderList (fun n => s!"{n}") c.from_}") ++
  f.pre.map (renderInst e.cert) ++
  (f.blocks.zipIdx.map (fun (b, i) => renderBlock e.cert i b)).flatten ++ ["end"]

/-- The (operation, class) pairs the entries use, sorted and without repeats. -/
def usedClasses (es : List Entry) : List (String × Class) :=
  let all := es.flatMap fun e => (e.fn.allInsts.map fun i => (i.op, i.cls))
  let uniq := all.foldl (fun acc p => if acc.contains p then acc else acc ++ [p]) []
  (uniq.toArray.qsort fun a b => a.1 < b.1).toList

/-- A whole file. -/
def renderFile (es : List Entry) : String :=
  let header := [formatVersion] ++ (usedClasses es).map fun p => s!"class {p.1} {p.2.render}"
  "\n".intercalate (header ++ (es.flatMap renderEntry)) ++ "\n"

end Own
