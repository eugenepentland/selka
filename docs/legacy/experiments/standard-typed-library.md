# Typed standard text, JSON and errors
> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

`std_result`, `std_bytes` and `std_json_view` are compiler-reserved modules.
They preserve the existing `std_json` and `std_text` APIs.

`std_result::Option<T:copy>` has `none` and `some(T)` cases.
`Result<T:copy,E:copy>` has `ok(T)` and `err(E)` cases and the usual mandatory
handling/`try` semantics. `Error` retains a named `Category` and original numeric
`code`. `parse_error`, `allocation_error`, and `io_error` are explicit adapters;
the latter takes the provider's own denied code because error codes are scoped
to providers. `ContextError` owns a `Context` byte buffer plus its `cause`.
`ContextResult<T:copy>` can propagate that whole error through `try` without
copying or dropping the context. Inspect `cause` with `read_field` and transfer
`context` with `take_field` when decomposing the owned error.

The generic wrappers currently require copyable type parameters. Concrete
`Built`, `Parsed`, and `ContextResult` cover the owned standard-library payloads;
arbitrary generic owned success/error types require the ownership-bound work.

`std_bytes` uses byte indices and lexicographic byte ordering. `compare` and
`find` do not promise Unicode normalization or grapheme semantics. `utf8` checks
strict scalar UTF-8 (rejecting overlong encodings, surrogates, truncated sequences
and values above U+10FFFF). `integer` parses an optional minus and decimal digits,
rejects whitespace/plus/trailing bytes and reports overflow separately, including
i64 minimum/maximum boundaries. Leading zeros are allowed here; this is decimal
text parsing, not the JSON number grammar.

`create(heap, capacity)` creates a bounded owned byte builder; `append` consumes
and returns it and never grows beyond that capacity. `escaped` produces a quoted
ordinary JSON string, rejects invalid UTF-8, escapes quotes, backslashes and all
control bytes, and preflights its output length. `decimal` emits signed i64,
including the minimum. `Built.err` owns no partial output; failed operations
consume/release the input builder. Bytes can be emitted by borrowing them into
`std_text::emit` under the explicitly granted I/O host.

`std_json_view::parse` returns a document or a named error and distinguishes
invalid UTF-8 from malformed JSON. `root`, `kind`, `field`, `integer`, `boolean`,
`count`, `at`, `key`, `textis`, `text_length`, and `text_byte` hide tape offsets.
`field` returns `Result<Option<Node>,Error>`: missing is `none`, present null is a
node with `Kind.null`, and querying the wrong type is an error. `count` and `at`
iterate array values or object member values; `key` returns an object member's
string node. Fractional numbers retain a named kind but no floating payload.

Nodes belong to the document where they were obtained. Typed accessors check
node bounds and expected kinds but require an unmodified parser-produced tape;
they do not authenticate a node against another document or validate arbitrary
hand-edited tapes. The raw mutable document representation remains available for
compatibility. See the executable [optional field example](../../src/stdlib/fixtures/checked_json.my)
and [owned error example](../../src/stdlib/fixtures/error_contracts.my).
