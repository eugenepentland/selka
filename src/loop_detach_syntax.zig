//! The words of `for x in detach place:` the parser needs (`loop_detach.zig` holds the form): the word itself, kept in
//! this one place, and the refusals of a `try` the put-back cannot cover.

/// The word that marks the loop's source. It is contextual: a value named `detach` is still a value.
pub const word = "detach";

/// The code of a `try` the put-back cannot cover.
pub const try_code = "E_TRY_POSITION";
/// Why a `try` in a position the rewrite does not cover is refused in a `detach` loop's body.
pub const try_position = "in a `detach` loop, a failing `try` puts the collection back before its error leaves when the `try` is a " ++
    "declaration's value (`const value = try f()`) or a statement of its own (`try f()`, `_ = try f()`); declare the value " ++
    "first, then use it (`const value = try f()`, then `return value`)";
/// Why a `try` that passes on a `None` is refused in a `detach` loop's body.
pub const optional_try = "in a `detach` loop, a `try` on an optional would leave without putting the collection back; write " ++
    "`const value = f() else: return None`, whose `return` puts it back";
