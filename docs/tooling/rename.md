# Renaming a declaration

`selka rename` renames one declaration and every use the compiler resolves to it, across a project. It asks the checker,
so it tells a field from a same-spelled local. String literals, comments and data files are never edited; the command
lists where the old name is still written in them.

## selka rename

```console
$ selka rename --dry-run shapes shapes::Point.x left
would rename the field `Point.x` to `left`: 6 edits in 2 files; 2 entries checked as before
  shapes/shapes.selka:3:5: `x` -> `left`
  shapes/shapes.selka:14:34: `x` -> `left`
  shapes/shapes.selka:21:18: `x` -> `left`
  shapes/main.selka:4:23: `x` -> `left`
  shapes/main.selka:5:7: `x` -> `left`
  shapes/main.selka:5:13: `x` -> `left`
left unchanged: `x` appears as a whole word in 1 string literal and 1 comment:
  shapes/main.selka:12:29 (string)
  shapes/main.selka:11:7 (comment)
```

The command line is `selka rename [--dry-run] [--json] <entry.selka|directory> <target> <new-name>`. The project is what
[`selka fix`](fix.md#selka-fix) visits: one program and its imports, or every `.selka` file under a directory.

The target uses the spellings the other tools print:

| Kind | Spelling | Example |
| --- | --- | --- |
| function, constant, record, enum, union, domain, alias, constraint | `module::name` | `shapes::area` |
| a function a type owns | `module::Type.name` | `units::Distance.make` |
| record field | `module::Type.field` | `shapes::Point.x` |
| enum case, union variant | `module::Type.Case` | `shapes::Shape.circle` |
| a case's named field | `module::Type.Case.field` | `shapes::Shape.circle.radius` |
| parameter, local (and any of the above) | `FILE:LINE:COLUMN` of its declaration or of a use | `main.selka:9:11` |
| every binding that hides a module-level name or an import alias | `hiding:NAME` | `hiding:live` |

`module` is the dotted name `selka index-project` prints; `module.name` works too. The new name is one plain, unreserved
name.

## What is renamed

Every token spelled the old name is resolved as the checker resolves it: calls, named arguments, field reads and writes,
pattern labels, case names, type positions, qualified uses, a parameter's name in `-> T from name`, and f-string holes.
Doc comments and `>>>` examples are text: they are left and listed.

- A pattern field written as one name, `case atom(text)`, binds a local of the same name. Renaming the field writes
  `case atom(body=text)`; renaming back writes the one name again.
- `named`, `own` and `mut` are modifiers before a name and ordinary names elsewhere. A form the rename does not read
  (`match mut place:`, `mut (a, b)`) makes it refuse as `unresolved`.

## A binding that hides a module-level name

A local, parameter or pattern binding may not take the name of a function, constant or type of its module, or of an
imported module (`E_SHADOWING`). Such a project does not check, so the rename is proven over a copy in memory and writes
the files only when the copy shows the project's errors less the refusals it repairs. If that would reveal an error the
refusal hid, the rename is refused and says so; fix that error and run the command again.

The refusal names the command, complete but for the new name. When it refuses several bindings that hide one name, it
names `hiding:NAME`, which renames them all. If the new name is taken in one of their functions, nothing is written and
the refusal says where.

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

A binding named by position is repaired the same way, and `--json` adds `repaired`. `selka fix` offers no repair: the new
name is yours. A function, constant, type or constraint that a binding hides may be the target too.

## All or nothing

The edits are checked over a copy in memory. The files are written only when every check keeps its verdict: the same
diagnostics by code, severity and position. Otherwise nothing is written, the command exits 1 and says why:

| Reason | When |
| --- | --- |
| `taken` | the declaring module, or the same type, already has a name, field or case spelled the new name |
| `shadowing` | a local would hide a module-level name, or two visible locals would share the name (`E_SHADOWING`) |
| `reserved` | the new name is a reserved word |
| `unresolved` | a token spelled the old name could not be resolved, for instance in a body that does not check |
| `outside` | the declaration is in the standard library or outside the project, or a use of it is |
| `extern` | the declaration is an `extern func`, whose name is its C function's |
| `verdict` | the renamed project checks differently; the differing diagnostics are named |

## What it cannot follow

A program that does not load with a plain check, or imports a package through [`packages.json`](packages.md), is not
followed: its uses are listed as `not followed`. For a declaration in a package that a `packages.json` under
the project names, a note says that locks pin the old bytes and programs outside the project were not renamed. The C
side of anything is not seen.

## For agents

`--dry-run` checks everything and writes nothing. `--json` prints one `rename-v1` document: `status` (`renamed`,
`dry-run` or `refused`), the target, `files` with each edit as a byte range and its replacement text (as `diagnostic-v1`
`fix.edits`), `mentions`, `unfollowed` uses and `notes`; a refusal carries `reason`, `message` and `places`. Exit 0 is a
rename done or computed, 1 a refusal, 2 a usage or host failure.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/rename.md).
