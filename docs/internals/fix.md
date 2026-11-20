# Fixes and migrations: how it works

What the [fixes guide](../tooling/fix.md) leaves out: the full table of fixes with every condition on each edit, how a
directory run is organised, and the maintainer-side migration tooling. Each section keeps the heading of the guide's
section it belongs to.

## Structured fixes in diagnostics

| Code | Edit |
| --- | --- |
| `E_MUTATION_MARKER` | insert `mut ` before an argument bound to a `mut` parameter; delete a call-site `mut` the callee does not declare |
| `E_TASK_CAPABILITY` | delete a capability argument of `g.submit` or a trailing argument of `parallel.map`, with the parameter it fills, when the task function never reads it: the parameter is plain and its name (a `_` name, `E_UNUSED_CAPABILITY`) occurs once in its file, and the function is private and named only by its declaration and this call; any other refused argument has no edit, and the message is the migration: return the values and read or write in the caller (W28) |
| `E_UNUSED_CAPABILITY` (an unused `out` or `err` Stream parameter of the entry `main`) | delete the parameter with the comma that separates it: `main(args: str[], out: Stream)` becomes `main(args: str[])`, a sole parameter leaves `main()`, and a list written over several lines keeps its lines; offered when the parameter is plain, only whitespace and the one comma lie between it and its neighbour (a comment there gets no edit), and `main` is named nowhere else in the file but in a comment line (a call would keep its argument). Both Streams unused take two rounds. Every other capability parameter, `main(host: Host)` included, gets the rename to a `_` name instead (FR31, FR35) |
| `E_METHOD_REMOVED` | rewrite a retired method call as its function, `text.split(":")` as `strings.split(text, ":")`; a set's `add` of anything but a literal becomes `sets.include(mut values, value)`, which borrows the value, since `sets.add` takes it `own` (F-2) |
| `E_LIST_MEMBERSHIP_REMOVED` | rewrite `value in values` as `lists.contains(values, value)` (`not in` as `not lists.contains(...)`), adding `import lists` when the file lacks it; the operands change places, so the edit is offered when both are pure reads (a local, a field of one, a literal), or one is and the other names no `mut` or `own` argument (F-25); two calls, or a call that passes a place `mut`, get no edit |
| `E_UNKNOWN_SYMBOL` (`strings.contains(text, part)`, `has` and `includes`, and `bytes`, `sets`, `dicts`), `E_GENERIC_INFERENCE` (`lists.contains(data, x)` of text, bytes, a set or a dictionary) | rewrite the call as the operator `in` with its operands swapped, `part in text` (`part not in text` after a `not`, in parentheses where an operator beside it would capture it); offered when both operands are a name, a field of one or a literal, and the call has no keyword argument, comment or line break; any other call gets the sentence with its placeholders and no edit (MSG-B) |
| `E_UNKNOWN_SYMBOL` (`lists.has(values, value)`, `lists.includes`) | replace the guessed name with `contains`, the function of the same module with the same arguments and meaning, when the call is written `lists.has(`; `strings.index`, `strings.rindex` and `lists.index` name `strings.text_index`, `strings.text_rindex` and `lists.index_of` in the sentence only, since those trap when the part is absent and the author may have meant `-1` or `None`, and `strings.len`, `is_empty`, `compare`, `empty` and `lists.find` name a builtin, an operator, a literal or a different function (MSG-F) |
| `E_UNKNOWN_SYMBOL` (`import sort`, then the builtin `sort(mut values)`: "`sort` here names the imported module") | delete the import line, which holds only that import and an optional comment; offered when the call is written as the builtin is (`sort(mut ...`) and the file has no other `sort.` qualifier, so the builtin is what the author called and nothing else uses the module; a call written another way, or a file that uses the module, keeps the message and has no edit (MSG-B) |
| `E_UNKNOWN_SYMBOL` (`argparse.MissingValue(name="db")`, a case of an enum written without its enum) | write the call with its enum, `argparse.Error.MissingValue(name="db")`; offered when exactly one enum has a case of that name (for `argparse.Name(` the exported enums of the module, for `Name(` those of the file and of each module it imports) and the call is written as `Name(`; a case that two enums have is not named, and has no edit |
| `E_INTERNAL_NAME` (`acquire_resource` on a Network) | replace the whole acquisition with the `network` operation that sends the same request, when the result type is the library's own and the request is one written octet: `acquire_resource[network.Connected](net, FixedArray[u8, 1]([0u8]))` becomes `network.connect(net)`, `network.Listening` with `1u8` `network.listen(net)` and `network.Polling` with `2u8` `network.open_poller(net)`. A request held in a name, one carrying an address (the narrowing of the Network would have replaced it, where `network.connect_to` refuses another address) and a result the program declares get no edit; the message names the operations (FR5a) |
| `E_UNKNOWN_FUNCTION` (`return Unit()`) | delete the value of `return Unit()`, `return Unit` or `return unit` in a function whose successful result is `Unit`, leaving a bare `return`, when the file declares no `Unit` or `unit` (F-41) |
| `E_SINGLE_OWNER_OVERLAP` (R2 receiver evaluation) | where proven safe, bind one unconditional direct `mut` call that returns a scalar to a fresh local before a simple receiver update, then substitute that local |
| `E_MODULE_HEADER` | remove a redundant source header; module names come from paths |
| `E_FRONTEND_SYNTAX` | replace parsed legacy `def`, type spellings, parameter modifiers, conditionals, or postfix propagation with canonical syntax |
| `E_BINDING_DECLARATION` | introduce `mut` where an implicit local is confined to its block |
| `E_FRONTEND_VARIANT` | migrate a local union declaration and its known payload fields to named enum syntax |
| `E_NAMED_FIELDS`, `E_NAMED_PATTERN` | add labels from the resolved record or enum field declaration, preserving operand order |
| `E_NUMERIC_PARSE` | replace text calls to numeric casts with `parse_int` or `parse_float`; where a declaration or binding claims that name there is no edit (the `str` method form `s.parse_int()` it once wrote was removed, W13), and the message names the rename that exposes the builtin |
| `E_FIXED_ARRAY_LITERAL` | wrap a known fixed-length literal in an explicit `FixedArray[T, N]` constructor |
| `E_NONE_UNIT` | replace an old Unit value `None` with `()` where its expected type is known |
| `E_REMOVED_SPELLING` | rename `push`→`append`, `List`→`list`, `filesystem_cap` and the other `*_cap` names→their capability types, `f64_sqrt`/`floor`/`ceil`/`trunc`/`abs`→the float builtin, unless the file declares or binds the new name; `&value` in an argument→`mut value`; a declaration's `mutates(a, b)` clause→`mut` on `a` and `b`; the removed method `receiver.contains(value)` becomes `value in receiver` for a set, a dictionary, text or bytes receiver (`value not in receiver` after a `not`, in parentheses where an operator beside it would capture it) and `lists.contains(receiver, value)` with its `import lists` for a list; offered when the receiver is a name or fields of one and the argument names no `mut` or `own` place, since the operands change places, and worded for the receiver's type (FR19) |
| `E_EXPLICIT_DISCARD_REQUIRED` | insert `_ = ` before a standalone value that is not a result |
| `E_PATTERN_PAYLOAD` (a bare `else:` or `else None:` over a Result) | write `else Err(_):`: the bare `else` already stands for the failure case, and `Err(_)` names it and drops its payload, which nothing could read; no edit when the error type itself needs handling (F-60) |
| `E_SYNTAX` (a call or a name written as a statement and followed by `else Err(e):`, `else Err(_):` or `else None:`) | write `if CALL is Err(e):` (`is None`): put `if ` in front of the statement and `is` in place of `else`, the pattern and the block unchanged; no edit for a bare `else:`, which names no case (F-76) |
| `E_SYNTAX` (a module constant written without its type, `const X = 1`) | insert the type after the name, `const X: int = 1`: `int` for an integer literal without a width suffix that fits an `int`, `float` for a decimal float, `str` for a text and `bool` for `True` and `False`, a minus sign allowed on a number; offered when that one literal is the whole value, so `1u8`, `2 * 8`, a name or a `bytes` literal get the message `write `const X: TYPE = ...`` and no edit (SP1-F-3, W3-F-4) |
| `E_UNKNOWN_FUNCTION`, `E_UNKNOWN_SYMBOL` (`x in range(a, b)`) | rewrite the membership test as the comparison it means, `x in range(lo, hi)` as `lo <= x < hi` (`range(hi)` as `0 <= x < hi`) and `x not in range(lo, hi)` as `(x < lo or hi <= x)`; `range` is a loop source, not a collection, so the refusal keeps its code and its place at `range` and only its message names the comparison. Offered when the needle and every bound is a name or a number (a minus sign allowed) and there is no step; a call, an operator or a step gets the message with the bounds as written and no edit, and a module that declares its own `range` is not refused (SP3-F-11) |
| `E_PATTERN_PAYLOAD`, `E_NAMED_PATTERN` (a `case` that names a payload case and no pattern, `case Ok:`) | write the discard after the case name, `case Ok(_):`, or `case circle(..):` for a case with named fields: the arm read nothing of the payload, which the discard drops; no edit when the payload needs handling (FR14) |
| `E_KEYWORD_ONLY` | insert `name=` before each positional operand that reaches a keyword-only parameter |
| `E_BYTE_ESCAPE` (a Unicode escape written with braces, `"\u{fffd}"`) | write the same digits as `\u` and four, `"\ufffd"`, when the braces hold one to four hexadecimal digits of a scalar value (not a surrogate), padding with zeros; braces holding more digits (`"\u{1f600}"`), a `\U{...}` and any other bad escape have no edit, and the message gives the spelling (`\u` and four digits, `\U` and eight) |
| `E_INDENTATION` (an indented line after a line that ends in a binary operator), `E_TOKEN` (a backslash that ends a line) | put the statement's one expression in parentheses and remove the backslashes: `total = a +` and an indented `b` become `total = (a +` and `b)`; offered when the statement is an assignment (`=` or an augmented one), a `return`, or an `if`, `elif` or `while` whose colon ends its last line, and the expression holds no comma or colon outside brackets, ends in an operand, and is followed by no deeper line it does not own; a backslash inside brackets is only deleted; any other statement keeps the advice and has no edit (R3-CONTINUE) |
| `W_BYTE_SET` | rewrite an or-chain of three or more byte equalities on one plain value as `value in b"..."` (see [lint](../tooling/lint.md#idiom-rewrites)) |
| `W_RANGE_CHAIN` | rewrite `x >= a and x <= b` (any pair of bounds on one plain value) as one chain, `a <= x <= b` |
| `W_LITERAL_MATCH` | rewrite an `if`/`elif` chain of three or more `x == literal` tests as a literal `match`, `else` becoming `case _:` and a chain without one gaining `case _:` with `pass` |
| `W_PATTERN_SHORTHAND` | drop the label of a pattern field written `name=name` in the case an arm names; a field of a nested pattern (`case Some(item(value=value))`) keeps its label, since the checker refuses the bare form there (FR49) |
| `W_UNUSED_BINDING` (a name a `match` pattern binds and the arm never reads: a `case`, an `is`, a `while ... is`, a bind-or-else's `else Err(e):`, nested or not) | ignore it, which the warning's text says: `_` in the place of the name for a single payload (`Some(x)`, `Err(e)`, a `result`'s `ok(v)`) or for a labelled field (`radius=r` becomes `radius=_`), and `name=_` for a bare field of an enum case (`case number(n, lit)` becomes `case number(n, lit=_)`; a bare `_` there is `E_FRONTEND_VARIANT`), the form `W_PATTERN_SHORTHAND` leaves alone. A name the arm writes (`match mut`), a type that must be handled, an arm of a `case a(x) \| b(x):` list, a case name that an enum and a `result` both declare, a `const x = value else:` and every binding that is no pattern's keep the plain message and no repair (FR45) |
| `W_OPTION_TRY` | rewrite an Option `match` on a call result whose `None` arm only returns `None`, ending a block of a function that returns an Option, as `const x = try call()` |
| `W_ELSE_IS_TRY` | rewrite a bind-or-else over a call whose `else` block only passes the failure on (`fail e`, or `return None` in a function that returns an Option) as `const x = try call()`; over a borrowed place it has no edit, since `try` would take the payload (FR20) |
| `W_MATCH_ELSE` | rewrite a two-arm `match` over an Option or a Result whose failure arm leaves as `const x = value else:` (`else Err(e):`, `else Err(_):`, or `_ = value else:` for `Some(_)`) over that arm's block, followed by the success arm's statements; offered when nothing after the `match` in its block declares a name those statements declare, and for `match own x` as `const x = own x else:`; a nest settles one level per round (FR20) |
| `W_MATCH_IS` | rewrite a two-arm `match` over an Option or a Result one of whose arms does nothing (`pass`, `_ = 0`) as `if value is Some(x):` (`is None`, `is Ok(x)`, `is Err(e)`) over the other arm's statements; and one whose success arm leaves while the failure arm binds nothing as that `if` followed by the failure arm's statements, under the scope condition of `W_MATCH_ELSE` (FR20) |
| `E_METHOD_REMOVED` (W13) | rewrite a method W13 removed as its function home with the receiver's and every operand's own text, `text.encode()` as `strings.encode(text)` and `", ".join(parts)` as `strings.join(parts, ", ")`, adding the module's import; the rows are text's, bytes', a byte buffer's (every `bytes` read: `buf.find(x)` is `bytes.find(buf, x)`), a set's `clear`, `pop`, `remove` and `update`, a list's `exchange` (`xs.exchange(i, own v)` is `lists.exchange(mut xs, i, own v)`, any index type, element or replacement, W13-S3), and the text parses (`s.parse_int()` is `parse_int(s)`). A join whose separator is an escaped literal (`"\n".join(lines)`) is certain (W13-S5). No edit, with the reason in the message, for a join whose two operands are both evaluated work (they change places), a bounded `find` or `rfind` whose `int?` answer is not compared with a literal (F57's table writes `is None` where it is), a prelude home the unit declares or imports (F48), and a module home whose import would hide a name the file binds (W13-S2, W13-S5). In a generic body the same decisions are made before any instance exists |
| `E_REMOVED_SPELLING` (W13) | rewrite a second spelling W13 removed as the one that stays: the bare `unwrap_or(x, d)` as `x.unwrap_or(d)` (a first operand that is not a name, field, call, index or literal in parentheses), `math.min`, `math.max` and `math.sqrt` as the prelude's `min`, `max` and `sqrt` (a type argument dropped; an operand that is a plain integer literal takes it as a suffix, `math.min[u8](x, 3)` as `min(x, 3u8)`, and one with an untyped literal inside an expression keeps the refusal without an edit, W13-S5), `math.round`, `floor`, `ceil` and `trunc` as the prelude's (a result of zero keeps its sign there, so `round(-0.4)` is `-0.0` where `math.round(-0.4)` was `0.0`; the two compare equal and print differently, and the message says so), `strings.to_int` and `to_float` as `parse_int` and `parse_float`, and a bare file function `exists(fs, path)` as `fs.exists(path)`; no edit for `math.abs` (it fails where `abs` does not), a prelude name the unit claims, or a capability operand that cannot be a receiver (W13-S2, W13-S5); the library's channels `run_process`, `process_control` and `stop_control` outside the library are `E_INTERNAL_NAME`, with no edit |
| `W_CAPABILITY_OWN` | remove an `own` marker, or an `own` parameter mode, on a capability or on a value that owns nothing else and held one: capabilities are shareable handles, so the marker transfers nothing (see [io](../io.md#records-that-hold-capabilities)) |
| `W_CAPABILITY_MUT` | remove `mut` from a capability parameter that its function never assigns and never passes on as `mut`: a capability is a shareable handle, so the marker hands nothing back. The call sites then carry `E_MUTATION_MARKER` ("does not write"), whose own fix deletes their `mut`, and a caller that passed the parameter on warns in the next round, so a chain settles one level per two rounds (see [io](../io.md#records-that-hold-capabilities)) |
| `E_BUILTIN_TYPE_NAME` | rename a type declared under a builtin type's name (`Unit`, `int`) to the module's own name and the builtin's, and every qualified reference to it (`alias.Unit`) in the modules that import it; a bare `Unit` inside the declaring module is renamed too when the module builds or reads the type (`Unit(number=1)`, `Unit.case`), which the builtin cannot do, and is otherwise left, since it already meant the builtin; no edit when a module's references cannot all be found |
| `E_INCOMPLETE_CONSTRUCTION` (a field default that builds a record without a required field) | delete the default, ` = Inner()`: the field becomes required, which is what every construction that checked already did |
| `E_INCOMPLETE_MATCH` | where a standard enum gained a case by splitting an older one (`http.Error`'s `HeaderTooLarge`, `BodyTooLarge` and `UnsupportedVersion`), insert after the older case's arm a copy of it under the new case's name, which is what the program did before the split; any other missing case has no edit |
| `E_OWN_PARAMETER` | insert `own ` before the name of a plain parameter whose type is move-only, or before the name or type of such a position in a function type; a parameter whose type names a type parameter has no edit |
| `E_OWN_MARKER` | insert `own ` for a proved final transfer, including a `const` initializer whose binding later moves; use `copy(...)` when the binding or its record is used again; where the binding is only read again by a later argument of the same call or constructor, which gives a number or a `bool` (`len(x)` of a text, bytes, list, dictionary or set, a comparison or arithmetic over it) or is a literal, write the argument that gives it last and mark it `own` (`Source(mem=plain, total=len(plain))` becomes `Source(total=len(plain), mem=own plain)`; the arguments evaluate left to right as written), provided every argument from the moved one on is written `name=value` with only commas and blanks between them and the function checks with the call so written (FR41); replace `mut` at a taking call position; remove `own` on a bare return or fail, fresh value, scalar or borrowing call position; replace `own x` with `copy(x)` where `x` is an option narrowed to `Some` that a plain or `mut` parameter, a loop variable or a `match` binding only lends (NARROW-OWN). In a generic body refused at its declaration the same repairs are offered, and an `own` removed or a `copy(...)` too, when every refused kind of type argument asks for the same edit and, for an edit at a value of a type parameter's type, every instance the check accepts has only scalar type arguments (where `own` is ignored); otherwise the refusal carries no edit (FR88) |
| `E_SINGLE_OWNER_MOVED` (a read after `own` in a later argument of the same call) | the same rewrite: the read written before the argument that gives the value, `Source(mem=own plain, total=len(plain))` as `Source(total=len(plain), mem=own plain)`; the same rewrite where the value moved is a field and the read is a number or a `bool` field of the same record or the length of one (`Tally(lat=own state.lat, flag=state.flag)` becomes `Tally(flag=state.flag, lat=own state.lat)`; `own state.lat` consumes `state`); where several fields are moved out of one `mut` record the function declares (`Tally(lat=own state.lat, status=own state.status, flag=state.flag)`), write each as `take(mut state.field)`, which leaves the field's default (an empty collection, `None`, or a record built from its field defaults), provided the statement is the last use of the record, no loop that does not declare it holds the statement, and the function checks with the `take`s written (FR63); a `const` record, a parameter or a later use gets the message and no edit; any other use of a moved value has no edit (FR41) |
| `E_BORROW_SOURCE` | remove a duplicate source name, or remove `from` from a nongeneric result with no managed successful value |
| `E_SINGLE_OWNER_BORROW` (a bare read of a narrowed option) | insert `own ` before a bare `x` stored where a value is kept, where `x` is an option local or `own` parameter narrowed to `Some` (`if x is None: return`), nothing reads `x` after the line and no loop `x` was declared outside of holds it: `own x` moves the payload and consumes the option (NARROW-OWN) |
| `E_SINGLE_OWNER_BORROW` (marked borrow) | replace `own` with a proved explicit copy, or remove it when returning the declared borrow preserves the whole `from` contract |
| `E_BORROW_UNDECLARED` | add missing parameter names to the result's `from` clause, before `fails`, in parameter order; for a function with no `from` clause yet, only when no caller in the program keeps the result (a caller keeps it when the ownership check accepts the caller while the result is new and refuses it once the result is declared `from`, for any reason but the caller's own missing `from`: a caller that returns the result passes it on and gets its own clause next round); where one does, wrap each borrowed return in `copy(...)` instead and name that caller (F-8, F-15) |
| `E_BORROW_MIXED` | where all borrowed returns can be copied exactly, copy them and remove `from` so every value result is owned |
| `E_BORROW_VIEWS_REMOVED` | replace `TextView` with `str`, `ByteView` with `bytes`, and a removed `.borrow(start, end)` or `.view(start, end)` call with a slice where certain |
| `W_COPY_FOR_STORE` | in a project check, declare `own` a parameter a function copies into storage it keeps, writing `own ` before it and `own name` for each copy that is its last use, where the function is not generic, recursive or named as a value, nor `public` unless two things hold: the project's `selka.json` sets no `interface_files`, and its modules have more than one top-level name, which a package root (`NAME.selka` and `NAME/`) cannot have; the warning then says the public signature changes, the parameter has no default and no `from`, and every caller passes a new value (a literal, a call's result, a constructor, a concatenation or a `copy(...)`) or the bare name of an owned local or `own` parameter it does not use again, before which the repair writes `own ` at the call, in whatever file the caller is (`selka fix FILE` sets such a repair aside; a directory run applies it). A plain list parameter whose elements a loop copies into storage is the same repair, under the same conditions: `own ` before it, `for x in own xs:` and `own x` or `own x.f` for the copy (see [managed memory](../managed-memory.md)) |
| `W_COPY_RETURNED` | in a project check, declare `from p` the result of a function every return of which copies a place of parameter `p` (or is `None`, `""`, `[]`), writing ` from p` after the result type and each returned `copy(PLACE)` as `PLACE`, where the function is not generic, recursive or named as a value, nor `public` unless the two things hold that `W_COPY_FOR_STORE` has above (no `interface_files`, and more than one top-level name), the warning then saying the public signature changes, and no caller in the project is refused with the result `from p`; no caller is edited; the repair is applied only in a round that applies no other fix, so that a caller another repair makes take the result is seen as it then is |
| `W_COPY_IN_RECURSION` | delete every `copy(...)` of a record passed to the function's own recursive call, where each of its managed fields then borrows: a place of a read-only parameter or of a loop variable over one, a literal, `None`, or `Some` of a read-only record parameter (see [lint](../tooling/lint.md#copies-in-recursion)) |
| `E_MODULE_NOT_IMPORTED` | insert `import MODULE` where the line belongs in the file's sorted directive block (leading comments, then the block, one blank line, the declarations). A file that lacks several modules needs one round: the lines that belong at one point of the block are one insertion in sorted order, the others sit at their own points, so the block stays as the formatter keeps it (FR28). A refusal ends its statement's check, so the imports named later in the same statement are reported with it (a qualifier that a local, a declaration or a member names is not one). A module file of the project is answered the same way: `util.twice(2)` without `import util` when `util.selka` is under the import root, or `calc.f(x)` when the one `calc.selka` below the root is `shared/calc.selka`, where the line is `import shared.calc` (FR32) |
| `W_UNUSED_IMPORT` | delete the import's line when it holds only that import |
| `E_ERROR_CASE_AMBIGUOUS` (`fail value`) | wrap the value in the constructor of the first enum case that can carry it, `fail AppErr.Parse(value="text")`: the case the compiler chose before the one-case rule. A generic union's case is built through its bare name (`fail Wrap.First(value=x)`), which takes its type arguments from the `fails` clause, in a generic function too; a refusal of one instance of a generic function (the cases fit only for its type arguments), and a `try`, get no edit |
| `W_NEEDLESS_COPY` | delete the `copy(...)` call whose copy-free form checks, keeping its operand: an argument (of a call or of a function value), print or f-string hole the callee only reads; a value that is already new (a module constant, a fresh call result); a borrowed value (a call's borrowed result, an option's default) in a read-only position; the last use of an owned local or of a field of one (`own row.name`); the copy of a payload of a `match name:` statement, or of `const x = name else:`, on an owned local nothing reads after it (`own ` in front of `name`, `own payload` for the copy: one repair of two edits, and the front edit of two arms that copy is applied once); a `const` that only reads a parameter's or a field's place while it does not change; the key of a dictionary store, of `dicts.setdefault`, `dicts.add` or `dicts.append_to`, and the member of `sets.add` (rewritten `sets.include`), which copy a key only when it is new; a field or element of a local that nothing reads again, taken with `take(mut place)` (a `const` local's `const` becomes `mut` in the same repair, once for all its fields); `opt.unwrap_or(d)` of an option nothing reads again, written `options.take_or(own opt, d)` (with `import options` when the unit lacks it) (see [lint](../tooling/lint.md#needless-copies)) |
| `E_SINGLE_OWNER_BORROW` (element read bound with `mut`) | when the function checks with the binding `const` and nothing else changes, change `mut` to `const`, which borrows the element; when the binding is changed only through scalar fields and the block ends with the write-back `xs[i] = x`, write the fields through `xs[i]` and delete the declaration and the write-back; otherwise wrap the element read in `copy(...)`, which runs on every call or iteration. No edit when a later line writes through the binding or passes it with `mut`, no write-back is proved and the element's owner is one the function may change (a local, an `own` or a `mut` parameter): the copy would take the write and leave the element unchanged, so the message offers both spellings (W2) |
| `E_SINGLE_OWNER_BORROW` and `E_SINGLE_OWNER_OVERLAP` (a lent value stored by `sets.add`) | rename `add` to `include` in `NAME.add(mut PLACE, VALUE)`, which stores the same element and copies it only when the set does not hold it yet; one round reaches that text, where the `copy(VALUE)` it replaces needed `W_NEEDLESS_COPY` to rewrite it in a second. A lent value stored anywhere else is wrapped in `copy(...)` |
| `E_UNREACHABLE` | delete the whole line, indentation, comment and line end, of a `return` or `fail` that ends its block and follows a statement that always leaves: a `return`, `fail`, `break` or `continue`, or a `match` or `if`/`else` chain whose every branch leaves, which the message names ("every arm of the match at line 7 returns, so this statement cannot run"). The line never ran, so deleting it changes nothing; a comment line above it stays. Any other statement there (two statements after a `return`, a call, an assignment) keeps the refusal and has no edit, since the early exit may be the author's mistake |
| `E_TOKEN` (a `!r` or `!s` conversion in an f-string hole, `f"{text!r}"`) | write the call the conversion stands for around the expression, `{repr(text)}` or `{str(text)}`, keeping a format specification after it. Only where the hole is one expression and `r` or `s` alone; `!a`, two conversions and an expression that does not parse carry no fix |
| `E_REPETITION_REMOVED` (`"-" * n`, `n * "-"`, `b"ab" * 3`, `[0] * n`) | write `strings.repeat("-", n)`, `byte_builder.repeat(b"ab", 3)` or `lists.filled(n, 0)` and add the import; a `u64` count, or a count written first beside an operand whose order of evaluation the call would change, gets a generated helper function beside the use instead |

The borrowed-result migration changes declarations, including declarations in
imported project modules. It does not insert copies to disguise an undeclared
borrow. Unknown or ineligible `from` sources still need a hand edit: select an
eligible plain or `mut` managed parameter, or change the intended result contract.
Duplicate sources and nongeneric results without managed successful storage have
the deletion repairs listed above.

Ownership move repairs check the whole function. One exception (FR61): where that
check stops at another refusal that the function without the marker stops at as well,
the `own` marker is still offered when the moved local is used nowhere else in the
function and no loop gives it away without declaring it again; then `fix` writes it
and the next check prints the other refusal. Otherwise the marker's message says that
the repair waits for the error at the line and column it names. Checked generic instances can
offer these repairs when the affected occurrence's type is independent of type
parameters; dependent occurrences carry no edit. A copy repair is withheld when
source declarations shadow `copy`, because the generated call would not reliably
name the builtin. These cases need a deliberate source edit.

The `E_OWN_PARAMETER` insertion applies to parameter declarations and function-type
positions. The same code can refuse a provider-owner copy under rule T2; that
expression does not carry a parameter insertion repair.

The receiver split repair is deliberately narrow and requires a direct call. For example,
`items[selected(mut items)] = 9` can become a call bound to a fresh local,
followed by `items[that_local] = 9`, so `selected` runs once before the receiver
is borrowed. The compiler offers this edit only when moving that call cannot
reorder another effect or an earlier observation of storage the call may change.
Conditional calls, `own` transfers, borrowed managed results and mutations that
would still invalidate another view are outside the repair. Uncertain cases
have no edit: evaluate earlier observations in their
original order, then the mutation, then the update. Two simultaneously
overlapping call arguments (M5) still require a manual rewrite.

The retired `.view(start, end)` range spelling uses the slice repair too:
`raw.view(2, 4).parse_int()` becomes `raw[2:4].parse_int()`, and the next round's W13 repair
`bytes.parse_int(raw[2:4])`. The repair preserves
the range endpoints, including in generic and fused numeric-parse calls.

A fix never captures a user declaration. A wrapper named for the builtin it
wraps, such as `func parse_int(s: str) -> int?` around `int(s)`, keeps its
diagnostic without a fix rather than a call of itself (it once got the `str`
method `s.parse_int()`, which W13 removed); a removed float helper inside a user
`func abs` keeps its diagnostic without a fix, for a hand edit.

## Removed spellings

The method forms of text, bytes, the byte buffer, lists and sets, and the second spellings `math.min`, the bare
`unwrap_or` and `exists(fs, path)`, are refused since W13-S5 (`E_METHOD_REMOVED`, `E_REMOVED_SPELLING`); W13-S2 had
reported them as the warnings `W_METHOD_FORM` and `W_DUPLICATE_SPELLING`, with the same rewrite. Every refusal with
a certain rewrite carries it (table above), and the checker goes on past a refusal, so one round of `selka fix`
rewrites every site of a function. No waiver excuses one: a `# lint: allow method-form` comment names a rule nothing
reads any more. A function that a program calls from a standard module it does not import (`strings.encode(text)`
with no `import strings`, the commonest slip after the move) is `E_MODULE_NOT_IMPORTED`, with the import as its
repair, in an expression, a statement and a type's place; every missing import of a file is one round (`test/fixtures/fix-migration/missing-imports.selka`). The corpus `test/fixtures/fix-migration/method-forms.selka`
holds every certain row, `method-forms-s5.selka` the shapes W13-S5 made certain, and `method-forms-uncertain.selka` every
row that is refused without an edit.

## selka fix

That is the Lox interpreter port moved across the call-site `mut` change: 957
markers restored in one command, identical to the hand migration except for the
one aliasing rewrite the compiler cannot choose for you.

- **A directory that is one project is checked once a round** (FR23). When every
  entry is a module of the project `selka check DIR` loads (the directory's
  `selka.json` root is every entry's root, no file is skipped for its name or
  left out by `release.exclude`), there is more than one entry, and no source
  under the root holds a docstring example (`>>> `) or a link that leaves it, a
  round is one `selka check DIR`: each module is checked once, where checking
  each entry on its own checked the modules it imports again for every entry.
  The repairs are those the entries' checks offer, chosen and applied by the same
  rules, so the tree it leaves is the same; on the port (523 files) the migration
  of 14 November took 3.7 minutes at `SELKA_JOBS=3`,
  where three to five hours were estimated for the old rounds. Two things differ. A project
  check stops at the first stage with an error in any module, where an entry
  clear of that error went on to its warnings, so a run through errors can take
  more rounds (the Lox corpus: 29 instead of 16) to the same tree. And the final
  report is that project check's: each remaining diagnostic once, a `W_COPY_MOVE`
  hint judged against every caller in the project (as `selka check DIR` judges
  it) rather than against each entry's own callers, and one `warnings: N in M
  unmodified modules` line. The entries are checked on their own instead, from
  that round on, when the project check fails as a host, stops at errors with
  nothing to apply, offers a tuple or domain migration or an `E_BORROW_UNDECLARED`
  repair (whose edit depends on which callers the checked program holds), or is
  not clean under `--check` (which reports the first round, so it reports the
  entries' round); and the final check is the entries' when the project check
  finds an error. `--report` adds one last line that counts the checks of each
  kind: `fix report: 5 rounds with edits, 7 directory checks, 0 entry checks, 0
  example checks`.
  With no `selka.json` the root of `selka check DIR` is the directory, and
  `rows/more.selka` is the module `rows.more` of it, where a check of that one file
  takes `rows/` as its root; so a file in a folder below such a directory counts
  as a module of the project too (FR50), and `import rows` in it finds `rows.selka`
  beside the folder, as it does under `check DIR`. The one-project round is
  tried first for such a tree. A folder of independent programs, each importing
  the files beside it, is refused by `check DIR` (`E_MODULE_READ`, "import it as
  `a.helper`, or move `selka.json` into `a`"): that round stops at the refusal
  and every file is checked on its own with its own folder as root, as before. A
  tree that the one-project round does not take (a docstring example, a file
  skipped for its name, one entry) is checked entry by entry, so a file below
  the directory that `import`s across folders is checked with its own folder as
  root there.
- Otherwise a round checks every entry, side by side, as many at once as
  `SELKA_JOBS` says, or else as many as the machine's cores allow at 2 GiB of
  free memory each (a Debug compiler's check of a 268-module program held
  1.4 GiB). Results are read back in entry order, so the edits and the report
  are the same at any width. An entry is checked again only when the previous
  round wrote a file it imports or would edit, and a round that finds nothing is
  confirmed by checking every entry afresh.
- Tuple declaration repairs wait for complete migration facts from every entry
  in the connected group of imported user modules. Errors in a disjoint, fully
  loaded and parsed group do not block those repairs. An incomplete import graph
  or declaration parse, or an aliased source file, keeps tuple repairs deferred
  across the whole directory.
  `fix` names withheld proposals and their reason on stderr; when no edit can run,
  its summary says that tuple repairs were withheld and diagnostics remain.

- The `E_BUILTIN_FUNCTION_NAME` rename leaves a bare call whose arguments cannot be the declared function's: their count is
  outside what its parameters take, or an argument whose kind the source writes (a literal, a list literal, a parameter of
  the enclosing function) binds a parameter declared with another kind (a number, text, a `bool`, a `Stream`, a collection).
  Beside `func flush(n: int)`, `flush(out)` with `out: Stream` stays the builtin's and `flush(1)` is renamed; the message
  names the call it leaves. Every other bare use is renamed. A module that re-exports the name cannot keep such a call bare,
  so there the repair is withheld and the message says which call is in the way.
- A rename that follows a declaration into the modules importing it (`E_BUILTIN_FUNCTION_NAME`, `E_BUILTIN_TYPE_NAME`) waits
  while a file of the directory does not parse and imports a module the rename edits: that file's qualified uses cannot be
  renamed with the declaration, and a partial rename would turn its syntax error into an unknown name once it is repaired.
  `fix` applies none of the rename, names the file and the module on stderr (`lib.selka: withheld E_BUILTIN_FUNCTION_NAME
  repairs: broken.selka does not parse and imports `lib`...`), keeps the diagnostic, and the next run, after the file parses,
  renames everything together. A module is known by the last segment of its dotted name, so two modules with one stem wait
  for each other's broken importers too.
- Within a round, a fix whose edits would overlap another's waits for the next
  round, which sees the updated file; the same edit reported twice (a generic
  function's instances) is applied once. A nested legacy expression and the one
  around it therefore migrate in successive rounds. A fix whose own edits
  overlap is never applied: `fix` names it on stderr and leaves the file alone.
- The `W_COPY_RETURNED` repair waits for a round of its own. It declares a result `from p` after judging every caller as it is
  written now, and another repair of the same round may rewrite a caller so that it takes the result (`for x in own keys(row)`,
  a parameter that becomes `own`), which `from p` would then refuse. So the round that applies any other fix, in any file of the
  run, leaves it out and says nothing; the next round's check judges it again against the callers as they then are, and
  applies it only when none takes the result. A run that needed this takes one round more. `check --warnings` still prints
  both warnings with their repairs, and `--check` shows the first round's, which has the other fixes only.

## Generated files

A module a generator writes is written again by that generator, and the generator's own check compares bytes: a repair
`selka fix` made there is lost at the next run, or breaks `--check` of the generator (the site's `viewgen --all --check`
failed after every `fix` until the three generated view modules were reverted by hand). So `fix` leaves a generated file
alone. A file is generated when **its first line is a `#` comment that starts with `generated by`, in any letter case**
(`# generated by tools/gen.py`, `# GENERATED by viewgen from detail.view`, `# Generated by protoc-gen-selka`). That is the
rule `selka lint` and the change review already use, so one first line says it to all three, and the generators of the
site and of `selka-protobuf` already write it. There is no list in `selka.json`: a list is a second place a generator
must keep in step with the files it writes, and the first line it writes costs it nothing.

## Docstring examples

Fenced examples in Markdown documentation are a separate path. `selka fix` visits
`.selka` files only, and `selka doctest` checks, builds or runs a fence without ever
running `selka test`, so it does not compile a `>>>` example inside a fence at all.
The repository's `scripts/migrate_embedded.py` stages each fence as a `.selka` copy
and runs this `fix` on it, so a docstring example in a staged fence is repaired
by the path above.

## Migrating across a breaking change

The gate proves this on real code (`FIX-MIGRATION-2`).
`test/fixtures/fix-migration/lox/` pins nine modules and tests of the Lox
interpreter port with every call-site `mut` marker stripped, as a program
written before the markers were required reads; the test copies them, runs
`selka fix` on the directory, and requires the current declarations and call
markers, every entry checking clean, and a second `selka fix --check` finding
nothing. The per-change scripts under `scripts/` (such as
`migrate_mut_arguments.py`) are superseded by the fixes the compiler carries.

## Embedded sources

The developer helper stages guest programs from `.selka` files, Markdown fences,
Zig multiline strings and golden JSON sources, runs the compiler's own fixes,
and checks the result before replacing a file. It does not implement a second
set of syntax rewrites. Preview a selected group with:

```bash
scripts/build-slot.sh build python3 scripts/migrate_embedded.py \
  --compiler ./zig-out/bin/selka --dry-run \
  --report .selka-cache/migration-preview.json docs/functions.md
```

Remove `--dry-run` to apply validated edits. The report records exclusions,
unsafe source shapes and each compiler invocation. Headerless embedded modules
need unambiguous host path bindings; quoted or concatenated host strings that
cannot be rewritten safely are reported for explicit handling. Golden IDs,
options and expected results stay fixed. Writes replace one validated file
atomically and refuse a file changed since it was read.

The repository's `zig build fmt-check` also checks live `.selka` sources. Its
reasoned exclusions in `scripts/my_format_exclusions.json` preserve migration
inputs, deliberate rejections, internal builtin syntax and recorded source spans.
New files under the selected live roots join the check automatically.
