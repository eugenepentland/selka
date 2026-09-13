# Rust benchmark baseline

Use stable Rust and the standard library only. Application behavior belongs in
`app.rs`; `main.rs` and `json.rs` are frozen transport/library prerequisites.
The JSON module exposes `Value`, parsing/encoding, exact-object, bounded-array,
bounded-integer, and identifier helpers. Compile from this directory with:

```sh
rustc --edition=2021 -O main.rs -o app
```
