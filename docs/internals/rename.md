# Renaming a declaration (internals)

Implementation detail moved out of the user guide, verbatim, under the same headings.

## What is renamed

Every token spelled the old name in a file of the project is resolved the way the checker resolves it: module-level
names through the module's own declarations, its imports, their aliases and re-exports (`export units.make`); locals and
parameters through the function's block scopes; fields and cases through the checked type of the value they belong to.
That covers calls and function values, named arguments (`Row(items=...)`, `f(count=3)`), field reads and writes, the
labels of a pattern (`case circle(radius=r)`), case names in `match` arms and constructions, type positions (parameters,
results, `fails`, type arguments, `FixedArray[T, N]`), qualified uses through an import or its alias, a parameter's
name in its function's `-> T from name` clause, and the holes of f-strings. A pattern field written as one name,
`case atom(text)`, binds the field to a local of the same name: renaming the field writes `case atom(body=text)`, and
renaming back writes the one name again.

`named`, `own` and `mut` are modifiers where one stands before a name (`named limit: int`, `mut total: int`, `own rest`,
`mut sum = 0`, an argument `mut sum`) and ordinary names elsewhere (`func count(named: int[])`). The parser says which, and
the rename reads it so: a modifier is no use of a parameter or local called the same, so a parameter called `named` is
renamed beside `named total: int`, with its keyword-argument labels, and the modifier is left as it is. A modifier of
a form the rename does not read (`match mut place:`, a destructuring `mut (a, b)`) still makes it refuse as `unresolved`.

Doc comments and `>>>` examples are text: the rename leaves them and lists them with the other mentions.

## A binding that hides a module-level name

A local, a parameter or a pattern binding may not take the name of a function, constant or type of its module, or of
a module its module imports (`E_SHADOWING`). A project with that refusal does not check, so the rename that repairs it
is proven over a copy (decision D-FR18-2): the uses of the binding are found by its block scope, written in a copy in
memory under an unused name of the same length, and the copy is checked; the rename then runs over the copy as it runs
over any checked project, with every use resolved by the checker's tables, and the tokens of the old name that are left
must resolve to the function or the module. The files are written when the copy reports the project's errors less the
`E_SHADOWING` refusals at the renamed bindings, and the renamed project checks as the copy does. A rename that would
show an error the refusal hid (the rest of the function was never checked), or make another one go, is refused as any
rename is. When the only difference is errors the refusal hid, the refusal says so in a sentence: the rename itself is
right, the function had an error no check could show, its code and its own message follow with its place, and the same
command writes the rename once that error is fixed (`E_BORROW_MIXED` from a payload returned unchanged, for instance, which
needs `copy(...)`). Warnings are not compared with the refused check, which prints none; the report counts the ones it now prints.

The refusal itself names the command, complete but for the new name, with paths as they are from where the check ran.
When one check refuses several bindings that hide the same name, it names `hiding:NAME`, which renames them all to one
name; if the new name is taken in one of their functions, nothing is written and the refusal says where.

```console
$ selka check server.selka
server.selka:14:9: error[E_SHADOWING]: binding `live` would hide the imported module `live`: a name is bound once where it is visible, so choose another name
      mut live = own poller
          ^
  note: server.selka:1:8: imported here
  note: server.selka:14:9: 20 bindings of this program hide `live`; rename them all with `selka rename server.selka hiding:live <new-name>`
$ selka rename server.selka hiding:live polled
renamed the 20 bindings hiding `live` to `polled`: 80 edits in 1 file; 1 entry checked as before apart from the refusals it repairs
removed 20 `E_SHADOWING` refusals of the renamed bindings:
  server.selka:14:9
  server.selka:21:9
  server.selka:28:9
  server.selka:35:9
  server.selka:42:9
  server.selka:49:9
  server.selka:56:9
  server.selka:63:9
  ... and 12 more
no other error before or after
left unchanged: `live` appears as a whole word in 1 string literal and 40 comments:
  server.selka:174:18 (string)
  server.selka:12:15 (comment)
  server.selka:12:55 (comment)
  server.selka:19:15 (comment)
  server.selka:19:55 (comment)
  server.selka:26:15 (comment)
  server.selka:26:55 (comment)
  server.selka:33:15 (comment)
  ... and 33 more
$ selka check server.selka
check: ok (2 modules, 1 cached)
```

A binding named by position is repaired the same way, and `--json` adds `repaired`: the places of the refusals removed,
the errors left unchanged and the warnings now printed. `selka fix` offers no repair here: the new name is the author's.

The other end of the clash is renamed the same way (F-79): a function, constant, type or constraint that a binding hides
may be the target, and its rename cures the refusal as renaming the binding does. The refusal's `declared here` note is
what says which declaration a binding hides; the bindings whose refusal names the target are renamed under a fresh name in
a copy in memory (the first phase above), and the files are written when that cured copy has the project's errors less
those refusals, and the renamed project checks exactly as the cured copy does, diagnostic for diagnostic. So the only
diagnostics that may appear without refusing the rename are the warnings of code the cured error had kept the checker from
reaching, and they appear in the cured copy too, where no rename of the target has happened; the report counts them as
a binding's repair does. A rename that would show an error, that makes another diagnostic come or go, or that gives the
function a name a local already has, is refused as any rename is.

```console
$ selka rename label.selka label::label label_of
renamed `label::label` to `label_of`: 2 edits in 1 file; 1 entry checked as before apart from the refusals it repairs
removed 1 `E_SHADOWING` refusal of a binding that hid the renamed name:
  label.selka:25:11
no other error before or after
1 warning the refused check did not print is printed now
```
