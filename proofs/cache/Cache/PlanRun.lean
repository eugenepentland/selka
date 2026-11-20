import Cache.Plan
import Cache.Blake3
import Std.Data.HashSet

/-!
# Running the planner on a recorded request

`parseRequest` reads an `SLKCP002` request (`src/cache_plan_protocol_v2.zig`, `request`), `plan` computes the
decisions and indexes the way `src/cache_plan_reference_v2.zig` does, and `replyPayload` writes them in the
component's reply layout (without the 64-byte envelope), so the output can be compared byte for byte with a
recorded reply of the Zig component.

`reused` is certified: `plan` computes the dirty set by breadth-first search over the reverse edges and returns
`certified := checkDirty ...`, the check whose soundness is `Cache.Plan.checkDirty_sound`.
-/

namespace Cache.Plan

/-- A parsed planner request. -/
structure Request where
  topology : ByteArray
  digests : Array ByteArray
  callees : Array (Array Nat)
  roots : Array (Array Nat)
  candidates : Array Bool
  changed : Array Nat
  /-- The retained index: its topology, its groups and its reverse rows. -/
  prior : Option (ByteArray × Array Nat × Array (Array Nat))

/-- The planner's work counts, as `Work` in `cache_plan_protocol_v2.zig`. -/
structure Work where
  indexNodes : Nat := 0
  indexEdges : Nat := 0
  affectedNodes : Nat := 0
  closureNodes : Nat := 0
  closureEdges : Nat := 0
  reusedTests : Nat := 0
  plannedTests : Nat := 0

/-- Everything the planner decides. -/
structure Outcome where
  reused : Array Bool
  batches : Array (Array Nat)
  groups : Array Nat
  reverse : Array (Array Nat)
  work : Work
  dirty : Array Bool
  dist : Array Nat
  /-- `checkDirty` accepted the dirty set. -/
  certified : Bool

/-! ## Reading the wire -/

abbrev Rd := StateT Nat (Except String)

def need (b : ByteArray) (k : Nat) : Rd Unit := do
  let p ← get
  if b.size < p + k then throw s!"truncated at byte {p}"

def u32 (b : ByteArray) : Rd Nat := do
  need b 4
  let p ← get
  set (p + 4)
  pure ((b.get! p).toNat ||| ((b.get! (p + 1)).toNat <<< 8) ||| ((b.get! (p + 2)).toNat <<< 16) |||
    ((b.get! (p + 3)).toNat <<< 24))

def bytes32 (b : ByteArray) : Rd ByteArray := do
  need b 32
  let p ← get
  set (p + 32)
  pure (b.extract p (p + 32))

def rdRow (b : ByteArray) : Rd (Array Nat) := do
  let n ← u32 b
  let p ← get
  if n > (b.size - p) / 4 then throw "row longer than the request"
  let mut r : Array Nat := Array.mkEmpty n
  for _ in [0:n] do
    r := r.push (← u32 b)
  pure r

/-- The transpose, preserving repeated edges in source order (`transpose` in the protocol). -/
def transpose (callees : Array (Array Nat)) : Array (Array Nat) := Id.run do
  let mut rows : Array (Array Nat) := Array.replicate callees.size #[]
  for source in [0:callees.size] do
    for target in callees[source]! do
      rows := rows.modify target (·.push source)
  rows

/-- Parse and validate a request as `validate` does: sizes, node ranges, the changed list without repeats. -/
def parseRequest (b : ByteArray) : Except String Request := do
  if b.size < 64 + 12 + 32 + 16 then throw "request shorter than its header"
  let magic := String.fromUTF8! (b.extract 0 8)
  if magic != "SLKCP002" then throw s!"magic {magic}"
  let body : Rd Request := do
    set 8
    let v1 ← u32 b
    let v2 ← u32 b
    let kind ← u32 b
    let len ← u32 b
    if v1 != 2 || v2 != 2 || kind != 0 || len != b.size - 64 then throw "envelope"
    set 64
    for _ in [0:3] do
      if (← u32 b) != 0 then throw "policy words"
    let topology ← bytes32 b
    let n ← u32 b
    let tests ← u32 b
    let nchanged ← u32 b
    let hasPrior ← u32 b
    if n > 100000 || tests > 100000 || nchanged > n || hasPrior > 1 then throw "limits"
    let mut digests : Array ByteArray := Array.mkEmpty n
    let mut callees : Array (Array Nat) := Array.mkEmpty n
    let mut edges := 0
    for _ in [0:n] do
      digests := digests.push (← bytes32 b)
      let r ← rdRow b
      if r.size > 1000000 - edges then throw "edge limit"
      edges := edges + r.size
      for t in r do
        if t >= n then throw "callee out of range"
      callees := callees.push r
    let mut roots : Array (Array Nat) := Array.mkEmpty tests
    let mut candidates : Array Bool := Array.mkEmpty tests
    let mut rootCount := 0
    for _ in [0:tests] do
      let flag ← u32 b
      if flag > 1 then throw "candidate flag"
      let r ← rdRow b
      if r.size > 1000000 - rootCount then throw "root limit"
      rootCount := rootCount + r.size
      for t in r do
        if t >= n then throw "root out of range"
      roots := roots.push r
      candidates := candidates.push (flag == 1)
    let mut changed : Array Nat := Array.mkEmpty nchanged
    let mut seen : Array Bool := Array.replicate n false
    for _ in [0:nchanged] do
      let c ← u32 b
      if c >= n || seen[c]! then throw "changed node out of range or repeated"
      seen := seen.set! c true
      changed := changed.push c
    let mut prior : Option (ByteArray × Array Nat × Array (Array Nat)) := none
    if hasPrior == 1 then
      let top ← bytes32 b
      let mut groups : Array Nat := Array.mkEmpty n
      for _ in [0:n] do
        groups := groups.push (← u32 b)
      let mut reverse : Array (Array Nat) := Array.mkEmpty n
      for _ in [0:n] do
        reverse := reverse.push (← rdRow b)
      prior := some (top, groups, reverse)
    if (← get) != b.size then throw "trailing bytes"
    pure { topology, digests, callees, roots, candidates, changed, prior }
  match body.run' 0 with
  | .ok r => pure r
  | .error e => throw e

/-! ## The algorithm -/

/-- Strongly connected groups by iterative Tarjan, each node mapped to the least index in its group. Also the
Tarjan part of the work counts (nodes entered, edges followed). -/
def groupsOf (callees : Array (Array Nat)) : Array Nat × Nat × Nat := Id.run do
  let n := callees.size
  let unv := 0xFFFFFFFF
  let mut visited : Array Nat := Array.replicate n unv
  let mut low : Array Nat := Array.replicate n 0
  let mut active : Array Bool := Array.replicate n false
  let mut grp : Array Nat := Array.replicate n 0
  let mut stack : Array Nat := #[]
  let mut fnode : Array Nat := #[]
  let mut fedge : Array Nat := #[]
  let mut next := 0
  let mut nodesW := 0
  let mut edgesW := 0
  for start in [0:n] do
    if visited[start]! != unv then continue
    visited := visited.set! start next
    low := low.set! start next
    next := next + 1
    active := active.set! start true
    stack := stack.push start
    fnode := fnode.push start
    fedge := fedge.push 0
    nodesW := nodesW + 1
    while fnode.size > 0 do
      let pos := fnode.size - 1
      let node := fnode[pos]!
      let edge := fedge[pos]!
      let row := callees[node]!
      if edge < row.size then
        fedge := fedge.set! pos (edge + 1)
        let target := row[edge]!
        edgesW := edgesW + 1
        if visited[target]! == unv then
          visited := visited.set! target next
          low := low.set! target next
          next := next + 1
          active := active.set! target true
          stack := stack.push target
          fnode := fnode.push target
          fedge := fedge.push 0
          nodesW := nodesW + 1
        else if active[target]! then
          low := low.set! node (min low[node]! visited[target]!)
      else
        fnode := fnode.pop
        fedge := fedge.pop
        if low[node]! == visited[node]! then
          let stop := stack.size
          let mut begin_ := stop
          let mut rep := node
          let mut going := true
          while going && begin_ > 0 do
            begin_ := begin_ - 1
            let member := stack[begin_]!
            rep := min rep member
            active := active.set! member false
            if member == node then going := false
          for j in [begin_:stop] do
            grp := grp.set! stack[j]! rep
          stack := stack.shrink begin_
        if fnode.size > 0 then
          let parent := fnode[fnode.size - 1]!
          low := low.set! parent (min low[parent]! low[node]!)
  return (grp, nodesW, edgesW)

/-- Whether node `l` sorts before `r`: by digest bytes, then by index (`before` in the protocol). -/
def before (digests : Array ByteArray) (l r : Nat) : Bool :=
  let a := digests[l]!
  let b := digests[r]!
  let rec go (i : Nat) (fuel : Nat) : Bool :=
    match fuel with
    | 0 => l < r
    | fuel + 1 =>
      if i ≥ a.size || i ≥ b.size then l < r
      else if a.get! i < b.get! i then true
      else if a.get! i > b.get! i then false
      else go (i + 1) fuel
  go 0 (a.size + 1)

/-- The planner. -/
def plan (q : Request) : Outcome := Id.run do
  let n := q.callees.size
  let reverse := transpose q.callees
  let (grp, gNodes, gEdges) := groupsOf q.callees
  let mut work : Work := { indexNodes := gNodes, indexEdges := gEdges }
  -- backward propagation from the changed nodes, remembering each node's distance
  let mut dirty : Array Bool := Array.replicate n false
  let mut dist : Array Nat := Array.replicate n 0
  let mut pending : Array Nat := #[]
  for node in q.changed do
    dirty := dirty.set! node true
    pending := pending.push node
  let mut next := 0
  while next < pending.size do
    let node := pending[next]!
    work := { work with affectedNodes := work.affectedNodes + 1 }
    for source in reverse[node]! do
      work := { work with indexEdges := work.indexEdges + 1 }
      if dirty[source]! then continue
      dirty := dirty.set! source true
      dist := dist.set! source (dist[node]! + 1)
      pending := pending.push source
    next := next + 1
  let mut changedFlags : Array Bool := Array.replicate n false
  for node in q.changed do
    changedFlags := changedFlags.set! node true
  let certified := checkDirty q.callees changedFlags dirty dist
  -- decisions and closures
  let mut seen : Array Nat := Array.replicate n 0
  let mut reusedOut : Array Bool := Array.mkEmpty q.roots.size
  let mut batches : Array (Array Nat) := Array.mkEmpty q.roots.size
  for i in [0:q.roots.size] do
    let reuse := reusedAt q.candidates q.roots dirty i
    reusedOut := reusedOut.push reuse
    if reuse then
      work := { work with reusedTests := work.reusedTests + 1 }
      batches := batches.push #[]
      continue
    work := { work with plannedTests := work.plannedTests + 1 }
    let epoch := i + 1
    let mut queue : Array Nat := #[]
    for root in q.roots[i]! do
      if seen[root]! == epoch then continue
      seen := seen.set! root epoch
      queue := queue.push root
    let mut reached : Array Nat := #[]
    let mut at_ := 0
    while at_ < queue.size do
      work := { work with closureNodes := work.closureNodes + 1 }
      for target in q.callees[queue[at_]!]! do
        work := { work with closureEdges := work.closureEdges + 1 }
        if seen[target]! == epoch then continue
        seen := seen.set! target epoch
        queue := queue.push target
        reached := reached.push target
      at_ := at_ + 1
    batches := batches.push (reached.qsort (before q.digests))
  return { reused := reusedOut, batches, groups := grp, reverse, work, dirty, dist, certified }

/-! ## Writing the reply -/

def putU32 (out : ByteArray) (v : Nat) : ByteArray :=
  out.push v.toUInt8 |>.push (v >>> 8).toUInt8 |>.push (v >>> 16).toUInt8 |>.push (v >>> 24).toUInt8

def putU64 (out : ByteArray) (v : Nat) : ByteArray :=
  putU32 (putU32 out (v % 4294967296)) (v / 4294967296)

def putRow (out : ByteArray) (row : Array Nat) : ByteArray :=
  row.foldl putU32 (putU32 out row.size)

/-- The reply payload of the component protocol: work counts, the groups, the reverse rows, and for each test its
reuse flag and batch. -/
def replyPayload (o : Outcome) : ByteArray := Id.run do
  let w := o.work
  let mut out := ByteArray.empty
  for v in [w.indexNodes, w.indexEdges, w.affectedNodes, w.closureNodes, w.closureEdges, w.reusedTests,
      w.plannedTests] do
    out := putU64 out v
  out := putU32 out o.groups.size
  out := putU32 out o.batches.size
  for g in o.groups do
    out := putU32 out g
  for row in o.reverse do
    out := putRow out row
  for i in [0:o.batches.size] do
    out := putU32 out (if o.reused[i]! then 1 else 0)
    out := putRow out o.batches[i]!
  return out

/-! ## Reading a reply (to compare with the Zig component's) -/

/-- A reply payload as the component writes it. -/
structure Reply where
  work : Work
  groups : Array Nat
  reverse : Array (Array Nat)
  reused : Array Bool
  batches : Array (Array Nat)

def u64 (b : ByteArray) : Rd Nat := do
  let lo ← u32 b
  let hi ← u32 b
  pure (lo + hi * 4294967296)

/-- Parse a full reply, envelope included (`SLKCP002`, kind 1). -/
def parseReply (b : ByteArray) : Except String Reply := do
  if b.size < 128 then throw "reply shorter than its header"
  if String.fromUTF8! (b.extract 0 8) != "SLKCP002" then throw "reply magic"
  let body : Rd Reply := do
    set 8
    let v1 ← u32 b
    let v2 ← u32 b
    let kind ← u32 b
    let len ← u32 b
    if v1 != 2 || v2 != 2 || kind != 1 || len != b.size - 64 then throw "reply envelope"
    set 64
    let w0 ← u64 b
    let w1 ← u64 b
    let w2 ← u64 b
    let w3 ← u64 b
    let w4 ← u64 b
    let w5 ← u64 b
    let w6 ← u64 b
    let n ← u32 b
    let tests ← u32 b
    let mut groups : Array Nat := Array.mkEmpty n
    for _ in [0:n] do
      groups := groups.push (← u32 b)
    let mut reverse : Array (Array Nat) := Array.mkEmpty n
    for _ in [0:n] do
      reverse := reverse.push (← rdRow b)
    let mut reused : Array Bool := Array.mkEmpty tests
    let mut batches : Array (Array Nat) := Array.mkEmpty tests
    for _ in [0:tests] do
      reused := reused.push ((← u32 b) == 1)
      batches := batches.push (← rdRow b)
    if (← get) != b.size then throw "trailing bytes in the reply"
    pure { work := { indexNodes := w0, indexEdges := w1, affectedNodes := w2, closureNodes := w3, closureEdges := w4,
                     reusedTests := w5, plannedTests := w6 }, groups, reverse, reused, batches }
  match body.run' 0 with
  | .ok r => pure r
  | .error e => throw e

/-- What differs between Lean's plan and a recorded reply: the decision and the indexes exactly, and the work counts
that every planner computes the same way (affected nodes and the two test counts; the index and closure counts depend
on the algorithm, Kosaraju in the component and Tarjan in the reference). -/
def differences (o : Outcome) (z : Reply) : List String :=
  (if o.reused != z.reused then ["reused"] else []) ++
  (if o.batches != z.batches then ["batches"] else []) ++
  (if o.groups != z.groups then ["groups"] else []) ++
  (if o.reverse != z.reverse then ["reverse"] else []) ++
  (if o.work.affectedNodes != z.work.affectedNodes then ["work.affected_nodes"] else []) ++
  (if o.work.reusedTests != z.work.reusedTests then ["work.reused_tests"] else []) ++
  (if o.work.plannedTests != z.work.plannedTests then ["work.planned_tests"] else [])

/-! ## A necessary condition of the host's `changed` list -/

/-- `Cache.Admit.Complete` says a node the host did not list as changed has a matching node in the old graph. The
request carries body digests and callee indices but not identities, so only a consequence can be checked: a node not
listed as changed must have a body digest and a number of distinct callees that some node of the old graph has. The
nodes that fail it are returned. -/
def uncoveredUnchanged (old new : Request) : Array Nat := Id.run do
  let key (q : Request) (x : Nat) : String :=
    Blake3.hex q.digests[x]! ++ s!":{(q.callees[x]!.toList.eraseDups).length}"
  let mut seen : Std.HashSet String := {}
  for x in [0:old.callees.size] do
    seen := seen.insert (key old x)
  let mut listed : Array Bool := Array.replicate new.callees.size false
  for c in new.changed do
    listed := listed.set! c true
  let mut bad : Array Nat := #[]
  for x in [0:new.callees.size] do
    if !listed[x]! && !seen.contains (key new x) then
      bad := bad.push x
  return bad

/-! ## The version-one protocol (`cache_plan_protocol.zig`): closures of root sets, no decisions -/

/-- A version-one request is a graph and root sets: the batches only. It is the version-two request with no candidate, no
changed node and no retained index. -/
def parseRequestV1 (b : ByteArray) : Except String Request := do
  if b.size < 64 + 20 then throw "request shorter than its header"
  if String.fromUTF8! (b.extract 0 8) != "SLKCP001" then throw "magic"
  let body : Rd Request := do
    set 8
    let v1 ← u32 b
    let v2 ← u32 b
    let kind ← u32 b
    let len ← u32 b
    if v1 != 1 || v2 != 1 || kind != 0 || len != b.size - 64 then throw "envelope"
    set 64
    for _ in [0:3] do
      if (← u32 b) != 0 then throw "policy words"
    let n ← u32 b
    let tests ← u32 b
    if n > 100000 || tests > 100000 then throw "limits"
    let mut digests : Array ByteArray := Array.mkEmpty n
    let mut callees : Array (Array Nat) := Array.mkEmpty n
    for _ in [0:n] do
      digests := digests.push (← bytes32 b)
      let r ← rdRow b
      for t in r do
        if t >= n then throw "callee out of range"
      callees := callees.push r
    let mut roots : Array (Array Nat) := Array.mkEmpty tests
    for _ in [0:tests] do
      let r ← rdRow b
      for t in r do
        if t >= n then throw "root out of range"
      roots := roots.push r
    if (← get) != b.size then throw "trailing bytes"
    pure { topology := ByteArray.empty, digests, callees, roots, candidates := Array.replicate tests false,
           changed := #[], prior := none }
  match body.run' 0 with
  | .ok r => pure r
  | .error e => throw e

/-- A version-one reply: for each root set, the sorted non-root nodes reachable from it. -/
def parseReplyV1 (b : ByteArray) : Except String (Array (Array Nat)) := do
  if b.size < 68 then throw "reply shorter than its header"
  if String.fromUTF8! (b.extract 0 8) != "SLKCP001" then throw "reply magic"
  let body : Rd (Array (Array Nat)) := do
    set 8
    let v1 ← u32 b
    let v2 ← u32 b
    let kind ← u32 b
    let len ← u32 b
    if v1 != 1 || v2 != 1 || kind != 1 || len != b.size - 64 then throw "reply envelope"
    set 64
    let count ← u32 b
    let mut rows : Array (Array Nat) := Array.mkEmpty count
    for _ in [0:count] do
      rows := rows.push (← rdRow b)
    if (← get) != b.size then throw "trailing bytes in the reply"
    pure rows
  match body.run' 0 with
  | .ok r => pure r
  | .error e => throw e

end Cache.Plan
