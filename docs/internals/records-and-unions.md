# Records, unions and enums: how it works

Implementation detail moved out of the user guide, [records-and-unions.md](../records-and-unions.md). Each heading is the guide's heading.

## Identity and recursive records

Recursive value fields that would be infinitely large are stored in immutable boxes; writing a nested path copies its boxes.

## Type names the language already uses

Before `E_BUILTIN_TYPE_NAME` a declaration under a builtin name was accepted and then could be neither built nor read in its own module, because the builtin won the lookup: the Zig `Unit` that three ports declared is the usual case. `selka fix` renames the type to the module's own name and the builtin's (`ShapeUnit` for a `Unit` in `kicad/shape.selka`, with a digit if that is taken) and rewrites every qualified reference to it in the modules that import it (`shape.Unit` and `sh.Unit` for `import kicad.shape as sh`). A bare `Unit` inside the declaring module already meant the builtin, so it is left as written, unless the module builds or reads the type itself (`Unit(number=1)`, `Unit.case`): that cannot be the builtin, so the module means its own type by the name and the repair renames each `Unit` in it.

## Constant defaults

A literal or constant default is a static value, as `""` and `[]` are: reading it allocates nothing, and a record that stores it holds the same static data a literal written at the construction would.

## Linear records

A linear record is an ordinary record to the compiler's back end: the rules are checked before code is generated, and nothing is closed at run time on your behalf.

## Sealed records

The checks are the front end's: the back end sees an ordinary record.

## Named variant case fields

The case's payload stays a single value, so named fields do not change how a union is laid out, compared, copied, or passed across a module boundary.

## Binding a field under its own name

The message names the case's fields and both forms: for `array(items: int[])`, `case array(elems)` is answered with "`case array(items):` binds it under its own name, `case array(items=elems):` renames it", and `selka fix` writes the label; for a bare `_` (`case Failed(_)`) the second form is said to discard (`case Failed(message=_):`). The message of an enum of another module names each field the pattern left unlabelled (at most four, then "and N more"), as `selka fix` labels them all. Only the fields of the case an arm names are meant: a field of a nested pattern keeps its label, since the bare `case Some(item(value, note))` is refused (`E_NAMED_PATTERN`), so the hint is not raised there and `selka fix` never writes that form.

## Recursive payloads

The compiler puts the recursive field or case in an immutable managed box.

## Writing array elements

The compiler writes the element in place, so `a[i] = v` costs one bounds check and one store however long the array is. `points[1].y += 1` keeps its operator, as `point.y += 1` does, and a field of a record holding an array, `window.samples[i] = v`, is written where the field lives rather than by copying the array and the record. One unsigned bounds comparison rejects both negative indexes and indexes past the end; no implicit adjustment from the end remains.

## Iterating a fixed array

The loop's guarantee costs one copy of the array when the loop begins, and only when the body writes the array: a loop over a local array its body never writes reads the elements where they are.
