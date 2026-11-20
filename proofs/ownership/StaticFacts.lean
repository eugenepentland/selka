import SoundRet

/-!
# The static facts a passed check gives

The checker's table of defining instructions is the model's (values are defined once), and the
entry checks give the facts about the parameters.
-/

namespace Own

section DefOf

/-- The checker's step building the table of defining instructions. -/
def defStep (m : Std.HashMap ValId Inst) (i : Inst) : Std.HashMap ValId Inst :=
  match i.dst with
  | some d => m.insert d i
  | none => m

theorem defFold (l : List Inst) (m : Std.HashMap ValId Inst) (x : ValId) :
    (l.foldl defStep m)[x]? =
      match l.filter (fun i => i.dst == some x) with
      | [] => m[x]?
      | js => js.getLast? := by
  induction l generalizing m with
  | nil => simp
  | cons i is ih =>
    simp only [List.foldl_cons]
    rw [ih]
    cases hd : i.dst with
    | none =>
      have : (i.dst == some x) = false := by simp [hd]
      simp [defStep, hd, this, List.filter_cons]
    | some d =>
      by_cases hdx : d = x
      · subst hdx
        have h1 : (i.dst == some d) = true := by simp [hd]
        simp only [List.filter_cons, h1, ↓reduceIte, defStep, hd]
        cases hf : is.filter (fun i => i.dst == some d) with
        | nil => simp [Std.HashMap.getElem?_insert]
        | cons j js => simp
      · have h1 : (i.dst == some x) = false := by simpa [hd] using hdx
        simp only [List.filter_cons, h1, defStep, hd]
        have : (m.insert d i)[x]? = m[x]? := by
          rw [Std.HashMap.getElem?_insert]
          have : (d == x) = false := by simpa using hdx
          simp [this]
        simp [this, hdx]

theorem filter_dst_le_one (l : List Inst) (hnd : (l.filterMap (·.dst)).Nodup) (x : ValId) :
    (l.filter (fun i => i.dst == some x)).length ≤ 1 := by
  induction l with
  | nil => simp
  | cons i is ih =>
    cases hd : i.dst with
    | none =>
      have : (i.dst == some x) = false := by simp [hd]
      simp only [List.filterMap_cons, hd] at hnd
      simp [List.filter_cons, this, ih hnd]
    | some d =>
      simp only [List.filterMap_cons, hd, List.nodup_cons] at hnd
      by_cases hdx : d = x
      · subst hdx
        have h1 : (i.dst == some d) = true := by simp [hd]
        have hempty : is.filter (fun j => j.dst == some d) = [] := by
          cases hf : is.filter (fun j => j.dst == some d) with
          | nil => rfl
          | cons j js =>
            exfalso
            have hj : j ∈ is.filter (fun j => j.dst == some d) := by rw [hf]; simp
            obtain ⟨hjm, hjd⟩ := List.mem_filter.1 hj
            apply hnd.1
            exact List.mem_filterMap.2 ⟨j, hjm, by simpa using hjd⟩
        simp [List.filter_cons, h1, hempty]
      · have h1 : (i.dst == some x) = false := by simpa [hd] using hdx
        simp [List.filter_cons, h1, ih hnd.2]

theorem mkCC_defEq (f : Function) (c : Certificate)
    (hnd : (f.allInsts.filterMap (·.dst)).Nodup) (x : ValId) :
    (mkCC f c).defOf[x]? = f.defOf? x := by
  unfold mkCC Function.defOf?
  show (f.allInsts.foldl defStep {})[x]? = _
  rw [defFold]
  have hle := filter_dst_le_one f.allInsts hnd x
  cases hf : f.allInsts.filter (fun i => i.dst == some x) with
  | nil =>
    have : f.allInsts.find? (fun i => i.dst == some x) = none := by
      rw [List.find?_eq_none]
      intro i hi hd
      have : i ∈ f.allInsts.filter (fun i => i.dst == some x) := List.mem_filter.2 ⟨hi, hd⟩
      rw [hf] at this; cases this
    simp [this]
  | cons j js =>
    rw [hf] at hle
    have hjs : js = [] := by
      cases js with
      | nil => rfl
      | cons _ _ => simp at hle
    subst hjs
    have hj : j ∈ f.allInsts.filter (fun i => i.dst == some x) := by rw [hf]; simp
    obtain ⟨hjm, hjd⟩ := List.mem_filter.1 hj
    have : f.allInsts.find? (fun i => i.dst == some x) = some j := by
      have hex : ∃ i, f.allInsts.find? (fun i => i.dst == some x) = some i :=
        (List.find?_isSome.2 ⟨j, hjm, hjd⟩ : _) |> fun h => by
          cases hh : f.allInsts.find? (fun i => i.dst == some x) with
          | none => rw [hh] at h; simp at h
          | some i => exact ⟨i, rfl⟩
      obtain ⟨i, hi⟩ := hex
      have hi' := List.find?_some hi
      have him := List.mem_of_find?_eq_some hi
      have : i ∈ f.allInsts.filter (fun i => i.dst == some x) := List.mem_filter.2 ⟨him, hi'⟩
      rw [hf] at this
      simp at this
      rw [hi, this]
    simp [this]

end DefOf

end Own
