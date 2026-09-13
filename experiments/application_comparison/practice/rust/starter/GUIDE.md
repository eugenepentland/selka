# Rust preparation utility

Compile with `rustc --edition=2021 main.rs -o /tmp/practice-rust` and provide
exact bytes on stdin. In the isolated session use `/tools/rust/bin/rustc`.
Compile and run within one command because each command receives a fresh scratch
directory, for example `/tools/rust/bin/rustc --edition=2021 main.rs -o
/tmp/practice-rust && printf m | /tmp/practice-rust`.

Repair the unresolved constant first, then the helper call and malformed-digit
fallback. `mod helper` loads `helper.rs`; call its public function through the
module name. `Result` and `unwrap_or` make the failure value explicit.

The expected results are `m` → 42, `d` → 9, and `f0` … `f9` → the
digit's integer value. Every other input returns -1, including malformed `f`
inputs, empty input, and inputs longer than 256 bytes. Do not trim or decode the
input. Output one JSON integer and a newline. This starter has exactly three
deliberate defects and uses only Rust's standard library and its local module.
