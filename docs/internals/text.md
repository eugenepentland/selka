# Text and strings: how it works

Implementation detail moved out of the user guide, [text.md](../text.md). Each heading is the guide's heading.

## Text is bytes; scalars have helpers

`strings.find` and `strings.rfind` have their bodies in the library, so the trap's own site is a line of `@stdlib/strings.selka`; the report's first line still names the program's call, and the frame `in strings::find at @stdlib/strings.selka:...` follows it as context. The negative-position repair of the `strings.char_*` helpers counts `strings.char_count(base)` rather than `len(base)`.

## Slices are views of their source

A slice written **at its use** (`len(text[a:b])`) borrows in every build mode when the only thing the program does with it is a read the compiler can borrow for: a length is one, and so is any read inside a `@noalloc` function (where the promise forbids the copy, so a helper call borrows there too). A debug build still copies when the use needs an owned value — printing, a dictionary insert, a comparison whose helper has no span form — and a release build borrows every read-only use. `strings.char_slice` is a view of the octets that hold the scalars it selects.

## Indexing long text that is not ASCII

On a string that holds any non-ASCII scalar, the runtime finds the offset by counting scalars through the octets, 32 at a time, from the start (or from the offset of the previous lookup, when the string has one recorded). The runtime stops updating these lookup caches before worker threads can borrow text. Later reads may reuse existing metadata but do not update it, so uncached lookups after worker-pool startup may require a longer read-only walk.

## String functions

Apart from `find` and `rfind`, which wrap a native offset search, these functions are native code over the C runtime's one immutable text representation.

## Format strings

Printing or writing a format string writes its literal pieces and each hole's rendering straight to the stream, so a scalar, text or byte hole allocates nothing and no pieces are joined; storing one in a `str` fills one exactly-sized allocation instead: its literal lengths, its text holes' lengths and each scalar rendering's bound. A single piece returns its rendered text directly, so `f"{text}"` needs no allocation when `text` is already a `str`. Each hole evaluates and renders once from left to right; the implementation does not repeatedly copy a growing prefix.

## The text of a collection

Cost: one pass over the value. The elements are read in place and not copied, the text is built in one growing buffer, and the result is copied out of it once. The cost grows in step with the length: the text of 100,000 numbers takes milliseconds.

## Parsing numbers from text

One compiled grammar serves every build, and one shared table of vectors drives the Zig unit test and the native driver, so `selka run` and `selka build` cannot disagree about which text is a number or about the value it names.
