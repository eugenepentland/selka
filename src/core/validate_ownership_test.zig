//! The ownership validator (docs/design/ownership-certificates.md §5) on certificates stated in the format itself:
//! functions it accepts, and one function for each judgment it rejects.
const std = @import("std");
const validate = @import("validate_ownership.zig");
const parse = @import("ownership_parse.zig");
const form = @import("ownership_function.zig");

/// A fixture: a name, one function in the certificate format, and the judgment that must reject it (null: accepted).
const Fixture = struct { name: []const u8, text: []const u8, reject: ?validate.Check = null };

const accepted = [_]Fixture{
    // FX12: the null owner (an `undef` of a managed type) fills a join's edge, and the joined value is dropped; nothing
    // reads it, so the rule that refuses a read of it accepts this.
    .{ .name = "an undef of a managed type (the null owner) on one edge of an owned phi", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 scalar
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %2 undef Constant reads - consumes - state immortal parents -
    \\block b0 preds -
    \\term branch %0 b1 b2
    \\block b1 preds b0
    \\inst %3 list_new Fresh reads %1 consumes - state owned parents -
    \\term jump b3
    \\block b2 preds b0
    \\term jump b3
    \\block b3 preds b1,b2
    \\phi %4 owned parents - edges b1:%3,b2:%2
    \\inst - drop Drop reads - consumes %4 state none parents -
    \\term ret %1
    \\end
    \\
    },
    // Phase 2 of lane VAL (format v2): an owned option that holds a view of its borrowed parameter as a loan, listed among
    // its parents and its views (condition 2 of construct-read).
    .{ .name = "an owned option that holds a list view of a borrowed parameter as a loan it lists among its views (construct-read)", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 list_view_of View reads %0 consumes - state borrowed parents %0
    \\inst %2 union_make Construct reads %1 consumes - state owned parents %1 views %1
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %9
    \\end
    \\
    },
    // Lane VAL, the construct-read rule (J6): design entry 19, an owned record that takes an owner and holds a view of it as a
    // loan; the view is rooted in the owner the constructor consumes and listed among its parents.
    .{ .name = "an owned record that takes an owner and lists a view of it as a loan (entry 19, construct-read)", .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 list_new Fresh reads %9 consumes - state owned parents -
    \\inst %2 list_view_of View reads %1 consumes - state borrowed parents %1
    \\inst %3 record_make Construct reads %2 consumes %1 state owned parents %2 views %2
    \\inst - drop Drop reads - consumes %3 state none parents -
    \\term ret %9
    \\end
    \\
    },
    // Design entry 28 through a slot: an emptied record that takes an owned record and reads a view of one of its slots; the
    // view's root is a slot of the owner the constructor consumes.
    .{ .name = "an emptied record that takes an owner and reads a view of one of its slots (entry 28, construct-read)", .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 list_new Fresh reads %9 consumes - state owned parents -
    \\inst %2 record_make Construct reads - consumes %1 state owned parents -
    \\inst %3 record_get Project reads %2 consumes - state borrowed parents %2 slot f0
    \\inst %4 record_make Construct reads %3 consumes %2 state emptied parents - slots f0
    \\inst %5 record_get Project reads %4 consumes - state owned parents - slot f0
    \\inst - drop Drop reads - consumes %5 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "an owned parameter returned", .text =
    \\function f result owned from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\block b0 preds -
    \\term ret %0
    \\end
    \\
    },
    .{ .name = "a list built, measured and dropped", .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\inst %3 list_push Update reads - consumes %2,%1 state owned parents -
    \\inst %4 list_len Inspect reads %3 consumes - state scalar parents -
    \\inst - drop Drop reads - consumes %3 state none parents -
    \\term ret %4
    \\end
    \\
    },
    .{ .name = "a view of a borrowed parameter returned under its from", .text =
    \\function f result borrowed from 0 unchecked -
    \\param 0 %0 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\block b0 preds -
    \\inst %1 str_view_of View reads %0 consumes - state borrowed parents %0
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "a borrow of one slot read again from the container after another slot is replaced", .text =
    \\function f result owned from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %3 list_len Inspect reads %1 consumes - state scalar parents -
    \\inst %2 record_set Update reads - consumes %0,%9 state owned parents -
    \\inst %4 record_get Project reads %2 consumes - state borrowed parents %2 slot f0
    \\inst %5 list_len Inspect reads %4 consumes - state scalar parents -
    \\term ret %2
    \\end
    \\
    },
    // 4e: `return []` in a `from` accessor is a view of the runtime's static empty list, an immortal constant, as
    // `return ""` is a view of a constant text: the result borrows no owner of the function.
    .{ .name = "a view of the static empty list returned beside a borrow", .text =
    \\function f result borrowed from 0 unchecked -
    \\param 0 %0 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %3 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %10 text_sentinel Constant reads - consumes - state immortal parents -
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f1
    \\inst %2 union_tag Inspect reads %1 consumes - state scalar parents -
    \\inst %4 cmp Pure reads %2,%3 consumes - state scalar parents - imm 0
    \\term branch %4 b2 b3
    \\block b2 preds b0
    \\inst %6 union_payload Project reads %1 consumes - state borrowed parents %1
    \\inst %7 list_view_of View reads %6 consumes - state borrowed parents %6
    \\term ret %7
    \\block b3 preds b0
    \\inst %11 list_view_of View reads %10 consumes - state borrowed parents %10
    \\term ret %11
    \\end
    \\
    },
    // 4a: `for pin in own pins: append(mut out, own pin.pad)` turns the list around once (a runtime call that takes it
    // and answers it), takes its last element and closes the take with `list_pop` each iteration, and drops the emptied
    // shell at the exit.
    .{ .name = "a consuming loop pops each taken element and drops the emptied list", .text =
    \\function f result owned from - unchecked -
    \\param 0 %0 owned
    \\callee 0 myl_core_owned_list_reverse runtime take,read-scalar owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %3 iconst Constant reads - consumes - state scalar parents - imm 16
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %13 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\inst %4 call Call reads %3 consumes %0 state owned parents - from - callee 0
    \\term jump b1
    \\block b1 preds b0,b3
    \\phi %6 owned parents - edges b0:%4,b3:%16
    \\phi %17 owned parents - edges b0:%2,b3:%19
    \\inst %7 list_len Inspect reads %6 consumes - state scalar parents -
    \\inst %8 convert Pure reads %7 consumes - state scalar parents -
    \\inst %10 cmp Pure reads %8,%9 consumes - state scalar parents - imm 4
    \\term branch %10 b2 b4
    \\block b2 preds b1
    \\inst %12 list_len Inspect reads %6 consumes - state scalar parents -
    \\inst %14 sub Pure reads %12,%13 consumes - state scalar parents -
    \\inst %15 list_get Project reads %6,%14 consumes - state owned parents - slot e%14
    \\inst %16 list_pop Update reads - consumes %6 state owned parents - slot e%14
    \\inst %18 record_take Take reads - consumes %15 state owned parents - noloans
    \\inst %19 list_push Update reads - consumes %17,%18 state owned parents -
    \\term jump b3
    \\block b3 preds b2
    \\term jump b1
    \\block b4 preds b1
    \\inst - drop Drop reads - consumes %6 state none parents -
    \\term ret %17
    \\end
    \\
    },
    // 4e with 4c: `r.names.unwrap_or([])` under `from`: the default is the static empty list, an immortal parent of the
    // borrowed phi, as a literal text default is.
    .{ .name = "an empty list default of unwrap_or returned under from: the borrowed phi takes the static empty list", .text =
    \\function f result borrowed from 0 unchecked -
    \\param 0 %0 borrowed
    \\callee 0 myl_core_borrow_choice_v1_optional_default_acf7d8d2906befdb5621c8885bc9bae2_16789d1fd35b0b50e5821119fc9542dc marker read,read,read owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %2 text_sentinel Constant reads - consumes - state immortal parents -
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %3 union_tag Inspect reads %1 consumes - state scalar parents -
    \\inst %5 cmp Pure reads %3,%4 consumes - state scalar parents - imm 0
    \\term branch %5 b1 b2
    \\block b1 preds b0
    \\inst %7 union_payload Project reads %1 consumes - state borrowed parents %1
    \\term jump b3
    \\block b2 preds b0
    \\term jump b3
    \\block b3 preds b1,b2
    \\phi %10 borrowed parents %1,%2 edges b1:%7,b2:%2
    \\inst %11 call Call reads %10,%1,%2 consumes - state borrowed parents %10 from %10 callee 0
    \\inst %12 list_view_of View reads %11 consumes - state borrowed parents %11
    \\term ret %12
    \\end
    \\
    },
    // G3 3A: `take(mut xs[0])` reads the element as an owned take of its slot and closes it with the store of the
    // replacement; the place read the receiver staged first is a forward take, borrowed from the take.
    .{ .name = "a list element taken and closed by the store of its replacement", .text =
    \\function f result owned from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %3 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 list_get Project reads %0,%1 consumes - state borrowed parents %5 slot e#0
    \\inst %4 list_new Fresh reads %3 consumes - state owned parents -
    \\inst %5 list_get Project reads %0,%1 consumes - state owned parents - slot e#0
    \\inst %6 list_set Update reads %1 consumes %0,%4 state owned parents - slot e#0 released -
    \\inst %7 record_make Construct reads - consumes %5,%6 state owned parents -
    \\term ret %7
    \\end
    \\
    },
    // FX15: `lists.exchange(mut xs, 0, Rec(text="new"))` on a list of records with one managed field. The exchange takes the
    // old element (a transferred read), the store of the replacement closes the take, and the one field read takes the
    // record's only managed part, so the element is `emptied`: the certificate the compiler gives `s2::main`.
    .{ .name = "an exchanged element emptied by its field read, its take closed by the store of the replacement", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 scalar
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 2
    \\inst %3 str_const Constant reads - consumes - state immortal parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %10 str_const Constant reads - consumes - state immortal parents -
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\inst %4 record_make Construct reads - consumes %3 state owned parents -
    \\inst %5 list_push Update reads - consumes %2,%4 state owned parents -
    \\inst %11 record_make Construct reads - consumes %10 state owned parents -
    \\inst %13 list_get Project reads %5,%9 consumes - state emptied parents - slot e%9 slots f0
    \\inst %14 list_set Update reads %9 consumes %5,%11 state owned parents - slot e%9 released -
    \\inst %15 record_get Project reads %13 consumes - state owned parents - slot f0
    \\inst - print Output reads %0,%15 consumes - state none parents -
    \\inst - drop Drop reads - consumes %14 state none parents -
    \\inst - drop Drop reads - consumes %15 state none parents -
    \\term ret %9
    \\end
    \\
    },
    // G3 3A: `exchange(mut xs[i].items, value)` takes the element's field by its path and closes the same path.
    .{ .name = "an element field taken by its path and closed by a store on the same path", .text =
    \\function f result owned from - unchecked -
    \\param 0 %0 owned
    \\param 1 %1 scalar
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %1 param Parameter reads - consumes - state scalar parents -
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 3
    \\inst %18 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %3 list_get_field Project reads %0,%1 consumes - state borrowed parents %13 slot e%1p0
    \\inst %5 list_new Fresh reads %4 consumes - state owned parents -
    \\inst %13 list_get_field Project reads %0,%1 consumes - state owned parents - slot e%1p0
    \\inst %15 list_set_field Update reads %1 consumes %0,%5,%18 state owned parents - slot e%1p0 released -
    \\inst %16 record_make Construct reads - consumes %13,%15 state owned parents -
    \\term ret %16
    \\end
    \\
    },
    // G3 3A: `take(mut payload.holds)` in a `match mut` arm takes the payload, takes its field, and closes both from the
    // inside out before the union is built again around the payload.
    .{ .name = "a match mut payload's field taken and closed inside the rebuilt payload", .text =
    \\function f result owned from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %8 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %9 list_new Fresh reads %8 consumes - state owned parents -
    \\inst %10 union_take Take reads - consumes %0 state owned parents - noloans
    \\inst %11 record_get Project reads %10 consumes - state owned parents - slot f0
    \\inst %12 record_get Project reads %11 consumes - state owned parents - slot f0
    \\inst %13 record_set Update reads - consumes %11,%9 state owned parents - slot f0
    \\inst %14 record_set Update reads - consumes %10,%13 state owned parents - slot f0
    \\inst %15 union_make Construct reads - consumes %14 state owned parents -
    \\inst %16 record_make Construct reads - consumes %12,%15 state owned parents -
    \\term ret %16
    \\end
    \\
    },
    .{ .name = "a field taken, grown and stored back", .text =
    \\function f result owned from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state owned parents - slot f0
    \\inst %2 list_push Update reads - consumes %1,%9 state owned parents -
    \\inst %3 record_set Update reads - consumes %0,%2 state owned parents - slot f0
    \\term ret %3
    \\end
    \\
    },
    .{ .name = "a record whose fields were all taken", .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %6 iconst Constant reads - consumes - state scalar parents -
    \\inst %7 str_const Constant reads - consumes - state immortal parents -
    \\block b0 preds -
    \\inst %5 list_new Fresh reads %6 consumes - state owned parents -
    \\inst %1 record_make Construct reads - consumes %5,%7 state emptied parents - slots f0,f1
    \\inst %2 record_get Project reads %1 consumes - state owned parents - slot f0
    \\inst %3 record_get Project reads %1 consumes - state owned parents - slot f1
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\inst - drop Drop reads - consumes %3 state none parents -
    \\term ret %6
    \\end
    \\
    },
    .{ .name = "a join that both arms reach with the same owners", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 scalar
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\term branch %0 b1 b2
    \\block b1 preds b0
    \\term jump b3
    \\block b2 preds b0
    \\term jump b3
    \\block b3 preds b1,b2
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "a loop that carries a list through an owned phi", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 scalar
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\term jump b1
    \\block b1 preds b0,b2
    \\phi %3 owned parents - edges b0:%2,b2:%5
    \\term branch %0 b2 b3
    \\block b2 preds b1
    \\inst %5 list_push Update reads - consumes %3,%1 state owned parents -
    \\term jump b1
    \\block b3 preds b1
    \\inst - drop Drop reads - consumes %3 state none parents -
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "a trap path that leaves an owner live", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 scalar
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\term branch %0 b1 b2
    \\block b1 preds b0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %1
    \\block b2 preds b0
    \\term unreachable
    \\end
    \\
    },
    .{ .name = "a stack list that is only read", .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state stack parents -
    \\inst %3 list_push Update reads - consumes %2,%1 state stack parents -
    \\inst %4 list_len Inspect reads %3 consumes - state scalar parents -
    \\term ret %4
    \\end
    \\
    },
    .{ .name = "a take and its close under two branches on the same test", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 18446744073709551615
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 dict_find Inspect reads %0,%9 consumes - state scalar parents -
    \\inst %4 cmp Pure reads %2,%1 consumes - state scalar parents - imm 1
    \\term branch %4 b1 b2
    \\block b1 preds b0
    \\inst %5 dict_entry_value Project reads %0,%2 consumes - state owned parents - slot v%2
    \\inst - drop Drop reads - consumes %5 state none parents -
    \\term jump b3
    \\block b2 preds b0
    \\term jump b3
    \\block b3 preds b1,b2
    \\inst %6 cmp Pure reads %2,%1 consumes - state scalar parents - imm 1
    \\term branch %6 b4 b5
    \\block b4 preds b3
    \\inst %7 dict_remove Update reads %2 consumes %0 state owned parents - slot v%2 released - taken value
    \\term jump b6
    \\block b5 preds b3
    \\term jump b6
    \\block b6 preds b4,b5
    \\phi %8 owned parents - edges b4:%7,b5:%0
    \\inst - drop Drop reads - consumes %8 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a unit value is named, owns nothing, and may be consumed", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %1 undef Constant reads - consumes - state none parents -
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %3 dict_insert Update reads - consumes %0,%2,%1 state owned parents -
    \\inst - drop Drop reads - consumes %3 state none parents -
    \\term ret %2
    \\end
    \\
    },
    .{ .name = "a borrow of a slot read before the slot is taken", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %3 list_len Inspect reads %1 consumes - state scalar parents -
    \\inst %2 record_get Project reads %0 consumes - state owned parents - slot f0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\inst %5 list_new Fresh reads %9 consumes - state owned parents -
    \\inst %6 record_set Update reads - consumes %0,%5 state owned parents - slot f0 released -
    \\inst - drop Drop reads - consumes %6 state none parents -
    \\term ret %3
    \\end
    \\
    },
    .{ .name = "a phi that takes over the owner keeps the borrows of it alive", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 scalar
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\inst %3 list_view_of View reads %2 consumes - state borrowed parents %2
    \\term jump b1
    \\block b1 preds b0
    \\phi %4 owned parents - edges b0:%2
    \\inst %5 list_len Inspect reads %3 consumes - state scalar parents -
    \\inst - drop Drop reads - consumes %4 state none parents -
    \\term ret %5
    \\end
    \\
    },
    .{ .name = "a view written ahead of the take of its slot lives in the take once it is taken", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 myl_core_fixture_0 runtime read,read scalar -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %2 slot f0
    \\inst %2 record_get Project reads %0 consumes - state owned parents - slot f0
    \\inst %3 call Call reads %2,%1 consumes - state scalar parents - from - callee 0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\inst %5 list_new Fresh reads %9 consumes - state owned parents -
    \\inst %6 record_set Update reads - consumes %0,%5 state owned parents - slot f0 released -
    \\inst - drop Drop reads - consumes %6 state none parents -
    \\term ret %3
    \\end
    \\
    },
    .{ .name = "an owner consumed after the call result that holds a loan on it", .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime read owned -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %9 consumes - state owned parents -
    \\inst %3 list_view_of View reads %2 consumes - state borrowed parents %2
    \\inst %4 call Call reads %3 consumes - state owned parents %3 from - callee 0
    \\inst - drop Drop reads - consumes %4 state none parents -
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a record built from an owner and a view of it, and emptied at once", .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 list_new Fresh reads %9 consumes - state owned parents -
    \\inst %2 list_view_of View reads %1 consumes - state borrowed parents %1
    \\inst %3 record_make Construct reads %2 consumes %1 state emptied parents - slots f0
    \\inst %4 record_get Project reads %3 consumes - state owned parents - slot f0
    \\inst - drop Drop reads - consumes %4 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "an edge that decides a test the other way is not taken", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 scalar
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %2 cmp Pure reads %0,%1 consumes - state scalar parents - imm 1
    \\term branch %2 b1 b2
    \\block b1 preds b0
    \\inst %3 cmp Pure reads %0,%1 consumes - state scalar parents - imm 1
    \\term branch %3 b3 b4
    \\block b2 preds b0
    \\term ret %1
    \\block b3 preds b1
    \\term ret %1
    \\block b4 preds b1
    \\inst %5 list_len Inspect reads %7 consumes - state scalar parents -
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "a block that only reaches a trap merges its edges once the owners they abandon are listed", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 scalar
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\term branch %0 b1 b2
    \\block b1 preds b0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term jump b3
    \\block b2 preds b0
    \\term jump b3
    \\block b3 preds b1,b2
    \\abandon b2 %2
    \\term jump b4
    \\block b4 preds b3
    \\term unreachable
    \\end
    \\
    },
    .{ .name = "a lent list read by a task and dropped after the group is joined", .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime - scalar -
    \\callee 1 myl_core_fixture_1 runtime read scalar -
    \\callee 2 myl_core_fixture_2 runtime - owned -
    \\callee 3 myl_core_fixture_3 runtime take,read,read,read scalar -
    \\callee 4 myl_core_fixture_4 runtime read,read owned -
    \\callee 5 myl_core_fixture_5 runtime take scalar -
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 2
    \\inst %8 iconst Constant reads - consumes - state scalar parents - imm 3
    \\inst %10 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %13 iconst Constant reads - consumes - state scalar parents - imm 2000
    \\inst %16 func_ref Constant reads - consumes - state scalar parents -
    \\inst %17 iconst Constant reads - consumes - state scalar parents - imm 18446744073709551615
    \\inst %23 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\inst - call Call reads %23 consumes - state none parents - from - callee 1
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 2
    \\inst %3 list_new Fresh reads %2 consumes - state owned parents -
    \\inst %5 list_push Update reads - consumes %3,%4 state owned parents -
    \\inst %7 list_push Update reads - consumes %5,%6 state owned parents -
    \\inst %9 list_push Update reads - consumes %7,%8 state owned parents -
    \\inst %11 list_push Update reads - consumes %9,%10 state owned parents -
    \\inst %12 box_make Construct reads %11,%1 consumes - state owned parents - lent %1
    \\inst %14 record_make Construct reads - consumes %12,%13 state owned parents -
    \\inst %15 box_make Construct reads - consumes %14 state owned parents -
    \\inst %18 call Call reads %1,%16,%17 consumes %15 state scalar parents - from - callee 3
    \\inst %19 call Call reads %1,%18 consumes - state owned parents - from - callee 4
    \\inst %20 box_take Take reads - consumes %19 state scalar parents -
    \\inst - call Call reads - consumes %1 state none parents - from - callee 5
    \\inst - drop Drop reads - consumes %11 state none parents -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\term ret %20
    \\end
    \\
    },
    .{ .name = "a lend of a borrowed parameter needs no drop after the group is joined", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\callee 0 myl_core_fixture_0 runtime - owned -
    \\callee 1 myl_core_fixture_1 runtime take,read,read,read scalar -
    \\callee 2 myl_core_fixture_2 runtime take scalar -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %8 func_ref Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 0
    \\inst %3 box_make Construct reads %0,%1 consumes - state owned parents - lent %1
    \\inst %4 box_make Construct reads - consumes %3 state owned parents -
    \\inst %5 call Call reads %1,%8,%9 consumes %4 state scalar parents - from - callee 1
    \\inst - call Call reads - consumes %1 state none parents - from - callee 2
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a lent slot view is taken only after the group is joined", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 myl_core_fixture_0 runtime - owned -
    \\callee 1 myl_core_fixture_1 runtime take,read,read,read scalar -
    \\callee 2 myl_core_fixture_2 runtime take scalar -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %8 func_ref Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 0
    \\inst %2 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %3 box_make Construct reads %2,%1 consumes - state owned parents - lent %1
    \\inst %4 box_make Construct reads - consumes %3 state owned parents -
    \\inst %5 call Call reads %1,%8,%9 consumes %4 state scalar parents - from - callee 1
    \\inst - call Call reads - consumes %1 state none parents - from - callee 2
    \\inst %6 record_get Project reads %0 consumes - state owned parents - slot f0
    \\inst %7 record_set Update reads - consumes %0,%6 state owned parents - slot f0
    \\inst - drop Drop reads - consumes %7 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a lender moved into an owned aggregate keeps its loan until the group is joined", .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime - owned -
    \\callee 1 myl_core_fixture_1 runtime take,read,read,read scalar -
    \\callee 2 myl_core_fixture_2 runtime take scalar -
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %9 func_ref Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 0
    \\inst %2 list_new Fresh reads %0 consumes - state owned parents -
    \\inst %3 box_make Construct reads %2,%1 consumes - state owned parents - lent %1
    \\inst %4 box_make Construct reads - consumes %3 state owned parents -
    \\inst %5 call Call reads %1,%9,%0 consumes %4 state scalar parents - from - callee 1
    \\inst %6 record_make Construct reads - consumes %2,%0 state owned parents -
    \\inst - call Call reads - consumes %1 state none parents - from - callee 2
    \\inst - drop Drop reads - consumes %6 state none parents -
    \\term ret %0
    \\end
    \\
    },
    .{ .name = "a group carried through a phi is still ended by the call that joins it", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 scalar
    \\callee 0 myl_core_fixture_0 runtime - owned -
    \\callee 1 myl_core_fixture_1 runtime take,read,read,read scalar -
    \\callee 2 myl_core_fixture_2 runtime take scalar -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %9 func_ref Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 0
    \\inst %2 list_new Fresh reads %0 consumes - state owned parents -
    \\inst %3 box_make Construct reads %2,%1 consumes - state owned parents - lent %1
    \\inst %4 box_make Construct reads - consumes %3 state owned parents -
    \\inst %5 call Call reads %1,%9,%0 consumes %4 state scalar parents - from - callee 1
    \\term branch %0 b1 b2
    \\block b1 preds b0
    \\term jump b3
    \\block b2 preds b0
    \\term jump b3
    \\block b3 preds b1,b2
    \\phi %6 owned parents - edges b1:%1,b2:%1
    \\inst - call Call reads - consumes %6 state none parents - from - callee 2
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %0
    \\end
    \\
    },
    .{ .name = "a group live on every edge into a trap block", .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime - owned -
    \\callee 1 myl_core_fixture_1 runtime take,read scalar -
    \\callee 2 myl_core_fixture_2 runtime read scalar -
    \\inst %9 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %0 call Call reads - consumes - state owned parents - from - callee 0
    \\inst %1 list_new Fresh reads - consumes - state owned parents -
    \\inst %2 box_make Construct reads %1,%0 consumes - state owned parents - lent %0
    \\inst %3 record_make Construct reads - consumes %2 state owned parents -
    \\inst %4 call Call reads %0 consumes %3 state scalar parents - from - callee 1
    \\term branch %9 b1 b2
    \\block b1 preds b0
    \\term jump b3
    \\block b2 preds b0
    \\term jump b3
    \\block b3 preds b1,b2
    \\inst - call Call reads %9 consumes - state none parents - from - callee 2
    \\term unreachable
    \\end
    \\
    },
    .{ .name = "a call that agrees with its callee table entry", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 helper program take,read-scalar owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads %9 consumes %0 state owned parents - from - callee 0
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a call through a function value agrees with the entry of its type", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 - indirect read-scalar scalar -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %8 func_ref Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst - drop Drop reads - consumes %0 state none parents -
    \\inst %1 call_indirect Call reads %8,%9 consumes - state scalar parents - from - callee 0
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a runtime callee is judged by its arity alone", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 myl_core_task_take runtime read-scalar owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst - drop Drop reads - consumes %0 state none parents -
    \\inst %1 call Call reads %9 consumes - state scalar parents - from - callee 0
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a call that returns a record taken apart at once has an owner result", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 helper program take owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads - consumes %0 state emptied parents - slots f0 from - callee 0
    \\inst %2 record_get Project reads %1 consumes - state owned parents - slot f0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a borrowed result names the arguments its callee borrows from among its parents", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 view program read borrowed 0
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst - drop Drop reads - consumes %0 state none parents -
    \\inst %2 list_new Fresh reads %9 consumes - state owned parents -
    \\inst %1 call Call reads %2 consumes - state borrowed parents %2 from %2 callee 0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a function marked unchecked is skipped whatever it holds", .text =
    \\function f result owned from - unchecked task-group
    \\block b- preds -
    \\block b0 preds -
    \\term ret -
    \\end
    \\
    },
    .{ .name = "the result record of a call with a mut argument lists no parent for the union it consumes", .text =
    \\function withmut result owned from 0 unchecked -
    \\param 0 %0 borrowed
    \\param 1 %1 scalar
    \\callee 0 myl_core_view_slice runtime read,read-scalar,read-scalar,read-scalar borrowed 0
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %1 param Parameter reads - consumes - state scalar parents -
    \\inst %6 str_const Constant reads - consumes - state immortal parents -
    \\inst %10 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %27 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 list_len Inspect reads %0 consumes - state scalar parents -
    \\inst %3 convert Pure reads %2 consumes - state scalar parents -
    \\inst %4 cmp Pure reads %1,%3 consumes - state scalar parents - imm 4
    \\term branch %4 b1 b2
    \\block b1 preds b0
    \\inst %7 union_make Construct reads - consumes %6 state owned parents -
    \\inst %8 record_make Construct reads - consumes %7,%1 state owned parents -
    \\term ret %8
    \\block b2 preds b0
    \\inst %11 cmp Pure reads %1,%10 consumes - state scalar parents - imm 2
    \\term branch %11 b3 b4
    \\block b3 preds b2
    \\inst %13 list_len Inspect reads %0 consumes - state scalar parents -
    \\inst %14 convert Pure reads %13 consumes - state scalar parents -
    \\term unreachable
    \\block b4 preds b2
    \\inst %16 list_len Inspect reads %0 consumes - state scalar parents -
    \\inst %17 convert Pure reads %16 consumes - state scalar parents -
    \\inst %18 cmp Pure reads %1,%17 consumes - state scalar parents - imm 4
    \\term branch %18 b5 b6
    \\block b5 preds b4
    \\inst %20 list_len Inspect reads %0 consumes - state scalar parents -
    \\inst %21 convert Pure reads %20 consumes - state scalar parents -
    \\term jump b6
    \\block b6 preds b4,b5
    \\phi %23 scalar parents - edges b4:%1,b5:%21
    \\inst %25 list_len Inspect reads %0 consumes - state scalar parents -
    \\inst %26 convert Pure reads %25 consumes - state scalar parents -
    \\inst %28 call Call reads %0,%23,%26,%27 consumes - state borrowed parents %0 from %0 callee 0
    \\inst %30 list_len Inspect reads %0 consumes - state scalar parents -
    \\inst %31 convert Pure reads %30 consumes - state scalar parents -
    \\inst %32 union_make Construct reads %28 consumes - state owned parents %28 views %28
    \\inst %33 record_make Construct reads - consumes %32,%31 state owned parents -
    \\term ret %33
    \\end
    \\
    },
    .{ .name = "a match on the result of a call with a mut argument reads the payload under the callee's from", .text =
    \\function one result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\callee 0 plain program read,read-scalar owned 0
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %12 iconst Constant reads - consumes - state scalar parents - imm 18446744073709551615
    \\block b0 preds -
    \\inst %2 call Call reads %0,%1 consumes - state owned parents %0 from %0 callee 0
    \\inst %3 union_tag Inspect reads %2 consumes - state scalar parents -
    \\inst %5 cmp Pure reads %3,%4 consumes - state scalar parents - imm 0
    \\term branch %5 b2 b3
    \\block b2 preds b0
    \\inst %7 union_payload Project reads %2 consumes - state borrowed parents %0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\inst %8 list_len Inspect reads %7 consumes - state scalar parents -
    \\inst %9 convert Pure reads %8 consumes - state scalar parents -
    \\term ret %9
    \\block b3 preds b0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term jump b4
    \\block b4 preds b3
    \\term ret %12
    \\end
    \\
    },
    .{ .name = "match own of an own parameter: its payload taken, a field moved out, the other arm dropping it", .text =
    \\function drain result owned from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %10 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 union_tag Inspect reads %0 consumes - state scalar parents -
    \\inst %3 cmp Pure reads %1,%2 consumes - state scalar parents - imm 0
    \\term branch %3 b2 b3
    \\block b2 preds b0
    \\inst %5 union_take Take reads - consumes %0 state emptied parents - slots f0
    \\inst %6 record_get Project reads %5 consumes - state owned parents - slot f0
    \\inst %7 record_take Take reads - consumes %6 state owned parents - noloans
    \\term ret %7
    \\block b3 preds b0
    \\inst - drop Drop reads - consumes %0 state none parents -
    \\term jump b4
    \\block b4 preds b3
    \\inst %11 list_new Fresh reads %10 consumes - state owned parents -
    \\term ret %11
    \\end
    \\
    },
    .{ .name = "a mut local holding a borrow carried around a loop: a borrowed phi of the parameter's views", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %3 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %26 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %31 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f1
    \\inst %2 list_len Inspect reads %1 consumes - state scalar parents -
    \\inst %4 str_view_of View reads %1,%3,%2 consumes - state borrowed parents %1
    \\inst %5 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %7 list_len Inspect reads %5 consumes - state scalar parents -
    \\inst %8 convert Pure reads %7 consumes - state scalar parents -
    \\term jump b1
    \\block b1 preds b0,b3
    \\phi %10 scalar parents - edges b0:%6,b3:%32
    \\phi %19 borrowed parents %4,%36 edges b0:%4,b3:%36
    \\inst %12 cmp Pure reads %10,%8 consumes - state scalar parents - imm 2
    \\term branch %12 b2 b4
    \\block b2 preds b1
    \\inst %15 list_get Project reads %5,%10 consumes - state borrowed parents %5 slot e%10
    \\inst %16 record_get Project reads %15 consumes - state borrowed parents %15 slot f0
    \\inst %17 list_len Inspect reads %16 consumes - state scalar parents -
    \\inst %18 convert Pure reads %17 consumes - state scalar parents -
    \\inst %20 list_len Inspect reads %19 consumes - state scalar parents -
    \\inst %21 convert Pure reads %20 consumes - state scalar parents -
    \\inst %22 cmp Pure reads %18,%21 consumes - state scalar parents - imm 4
    \\term branch %22 b5 b6
    \\block b3 preds b6
    \\inst %32 add Pure reads %10,%31 consumes - state scalar parents -
    \\term jump b1
    \\block b4 preds b1
    \\inst %37 list_len Inspect reads %19 consumes - state scalar parents -
    \\inst %38 convert Pure reads %37 consumes - state scalar parents -
    \\term ret %38
    \\block b5 preds b2
    \\inst %24 record_get Project reads %15 consumes - state borrowed parents %15 slot f0
    \\inst %25 list_len Inspect reads %24 consumes - state scalar parents -
    \\inst %27 str_view_of View reads %24,%26,%25 consumes - state borrowed parents %24
    \\term jump b6
    \\block b6 preds b2,b5
    \\phi %36 borrowed parents %19,%27 edges b2:%19,b5:%27
    \\term jump b3
    \\end
    \\
    },
    .{ .name = "a literal default of unwrap_or returned under from: the borrowed phi takes the immortal constant", .text =
    \\function f result borrowed from 0 unchecked -
    \\param 0 %0 borrowed
    \\callee 0 myl_core_borrow_choice_v1_optional_default_f82d761364b47229aa6223c6bf20357e_47457acde1e6d1d8766a9b33e9ed4ead marker read,read,read owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %2 str_const Constant reads - consumes - state immortal parents -
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %13 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %3 union_tag Inspect reads %1 consumes - state scalar parents -
    \\inst %5 cmp Pure reads %3,%4 consumes - state scalar parents - imm 0
    \\term branch %5 b1 b2
    \\block b1 preds b0
    \\inst %7 union_payload Project reads %1 consumes - state borrowed parents %1
    \\term jump b3
    \\block b2 preds b0
    \\term jump b3
    \\block b3 preds b1,b2
    \\phi %10 borrowed parents %1,%2 edges b1:%7,b2:%2
    \\inst %11 call Call reads %10,%1,%2 consumes - state borrowed parents %10 from %10 callee 0
    \\inst %12 list_len Inspect reads %11 consumes - state scalar parents -
    \\inst %14 str_view_of View reads %11,%13,%12 consumes - state borrowed parents %11
    \\term ret %14
    \\end
    \\
    },
    .{ .name = "a borrowed record (1A) of a lent owner: the owner is dropped after the record's last use", .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_bytes_concat runtime read,read owned -
    \\callee 1 size program read scalar -
    \\block b- preds -
    \\inst %0 str_const Constant reads - consumes - state immortal parents -
    \\inst %1 str_const Constant reads - consumes - state immortal parents -
    \\inst %5 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 call Call reads %0,%1 consumes - state owned parents - from - callee 0
    \\inst %3 borrow Borrow reads %2 consumes - state borrowed parents %2
    \\inst %4 borrow Borrow reads %3 consumes - state borrowed parents %3
    \\inst %6 record_make Construct reads %4 consumes %5 state borrowed parents %4
    \\inst %7 borrow Borrow reads %6 consumes - state borrowed parents %6
    \\inst %8 call Call reads %7 consumes - state scalar parents - from - callee 1
    \\inst %9 list_len Inspect reads %2 consumes - state scalar parents -
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\inst %10 convert Pure reads %9 consumes - state scalar parents -
    \\inst %11 add Pure reads %8,%10 consumes - state scalar parents -
    \\term ret %11
    \\end
    \\
    },
    .{ .name = "a borrowed record (1A) returned under from: its field is a projection of the parameter", .text =
    \\function f result borrowed from 0 unchecked -
    \\param 0 %0 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 7
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %2 borrow Borrow reads %1 consumes - state borrowed parents %1
    \\inst %3 borrow Borrow reads %2 consumes - state borrowed parents %2
    \\inst %5 record_make Construct reads %3 consumes %4 state borrowed parents %3
    \\term ret %5
    \\end
    \\
    },
    .{ .name = "a dictionary store with a borrowed key: the entry replaced on a hit, the key copied only on a miss", .text =
    \\function put result owned from - unchecked -
    \\param 0 %0 owned
    \\param 1 %1 borrowed
    \\param 2 %2 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %1 param Parameter reads - consumes - state borrowed parents ^1
    \\inst %2 param Parameter reads - consumes - state borrowed parents ^2
    \\inst %3 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %5 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %4 dict_find Inspect reads %0,%1 consumes - state scalar parents -
    \\inst %6 cmp Pure reads %4,%5 consumes - state scalar parents - imm 5
    \\term branch %6 b1 b2
    \\block b1 preds b0
    \\inst %8 dict_set_value Update reads %4 consumes %0,%3 state owned parents -
    \\term jump b3
    \\block b2 preds b0
    \\inst %15 str_from_view Copy reads %1 consumes - state owned parents -
    \\inst %10 dict_insert Update reads %4 consumes %0,%15,%3 state owned parents -
    \\term jump b3
    \\block b3 preds b1,b2
    \\phi %12 owned parents - edges b1:%8,b2:%10
    \\term ret %12
    \\end
    \\
    },
    .{ .name = "an own record parameter only read: its fields borrowed, the record dropped whole", .text =
    \\function count result scalar from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %2 list_len Inspect reads %1 consumes - state scalar parents -
    \\inst %3 convert Pure reads %2 consumes - state scalar parents -
    \\inst %4 record_get Project reads %0 consumes - state borrowed parents %0 slot f1
    \\inst %5 str_len Inspect reads %4 consumes - state scalar parents -
    \\inst - drop Drop reads - consumes %0 state none parents -
    \\inst %6 convert Pure reads %5 consumes - state scalar parents -
    \\inst %7 add Pure reads %3,%6 consumes - state scalar parents -
    \\term ret %7
    \\end
    \\
    },
    .{ .name = "two mut arguments at two depths of one record: the nested record is taken through its sibling's update (O3, F-RA-710)", .text =
    \\function child result owned from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %5 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %10 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %21 str_const Constant reads - consumes - state immortal parents -
    \\block b0 preds -
    \\inst %6 record_get Project reads %0 consumes - state owned parents - slot f0
    \\inst %7 record_get Project reads %0 consumes - state owned parents - slot f1
    \\inst %8 record_get Project reads %7 consumes - state owned parents - slot f0
    \\inst %11 bit_and Pure reads %9,%10 consumes - state scalar parents -
    \\term branch %11 b1 b2
    \\block b1 preds b0
    \\abandon b0 %0,%6,%7,%8
    \\term unreachable
    \\block b2 preds b0
    \\inst %22 list_push Update reads - consumes %8,%21 state owned parents -
    \\inst %23 record_make Construct reads - consumes %6,%22 state emptied parents - slots f0,f1
    \\inst %15 record_get Project reads %23 consumes - state owned parents - slot f0
    \\inst %16 record_get Project reads %23 consumes - state owned parents - slot f1
    \\inst %17 record_set Update reads - consumes %0,%15 state owned parents - slot f0
    \\inst %18 record_set Update reads - consumes %7,%16 state owned parents - slot f0
    \\inst %19 record_set Update reads - consumes %17,%18 state owned parents - slot f1
    \\term ret %19
    \\end
    \\
    },
    .{ .name = "a call lends a record and its nested field, and a later read takes the field for a sibling's write-back (O3, F-RA-14)", .text =
    \\function bad result owned from - unchecked -
    \\param 0 %0 scalar
    \\param 1 %1 owned
    \\callee 0 derive program read,read,read,read,read owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %1 param Parameter reads - consumes - state owned parents -
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 2
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 2
    \\inst %32 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %3 list_new Fresh reads %2 consumes - state owned parents -
    \\inst %5 list_push Update reads - consumes %3,%4 state owned parents -
    \\inst %7 list_push Update reads - consumes %5,%6 state owned parents -
    \\inst %8 record_get Project reads %1 consumes - state owned parents - slot f1
    \\inst %38 record_get Project reads %8 consumes - state owned parents - slot f0
    \\inst %9 record_set Update reads - consumes %8,%7 state owned parents - slot f0
    \\inst - drop Drop reads - consumes %38 state none parents -
    \\inst %10 record_set Update reads - consumes %1,%9 state owned parents - slot f1
    \\inst %33 add Pure reads %0,%32 consumes - state scalar parents -
    \\inst %34 record_get Project reads %10 consumes - state borrowed parents %10 slot f2
    \\inst %35 list_copy Copy reads %34 consumes - state owned parents -
    \\inst %36 record_make Construct reads - consumes %35 state owned parents -
    \\inst %37 record_make Construct reads - consumes %36,%33 state emptied parents - slots f0
    \\inst %12 record_get Project reads %37 consumes - state emptied parents - slot f0 slots f0
    \\inst %14 record_get Project reads %12 consumes - state owned parents - slot f0
    \\inst %16 record_get Project reads %10 consumes - state borrowed parents %10 slot f1
    \\inst %17 record_get Project reads %16 consumes - state borrowed parents %16 slot f0
    \\inst %18 list_copy Copy reads %17 consumes - state owned parents -
    \\inst %19 list_view_of View reads %14 consumes - state borrowed parents %14
    \\inst %20 list_view_of View reads %18 consumes - state borrowed parents %18
    \\inst %21 call Call reads %10,%19,%20,%14,%18 consumes - state emptied parents - slots f0,f1 from - callee 0
    \\inst - drop Drop reads - consumes %14 state none parents -
    \\inst - drop Drop reads - consumes %18 state none parents -
    \\inst %22 record_get Project reads %21 consumes - state owned parents - slot f0
    \\inst %24 record_get Project reads %10 consumes - state owned parents - slot f1
    \\inst %40 record_get Project reads %24 consumes - state owned parents - slot f1
    \\inst %25 record_set Update reads - consumes %24,%22 state owned parents - slot f1
    \\inst - drop Drop reads - consumes %40 state none parents -
    \\inst %26 record_set Update reads - consumes %10,%25 state owned parents - slot f1
    \\inst %27 record_get Project reads %21 consumes - state owned parents - slot f1
    \\inst %28 list_len Inspect reads %27 consumes - state scalar parents -
    \\inst - drop Drop reads - consumes %27 state none parents -
    \\inst %29 convert Pure reads %28 consumes - state scalar parents -
    \\inst %30 record_make Construct reads - consumes %29,%33,%26 state owned parents -
    \\term ret %30
    \\end
    \\
    },
    .{ .name = "a conditional removal from a set field puts the set back on both edges (O3, F-RA-807)", .text =
    \\function main::resolve result owned from - unchecked -
    \\param 0 %0 owned
    \\param 1 %1 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %1 param Parameter reads - consumes - state borrowed parents ^1
    \\inst %5 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %10 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %3 record_get Project reads %0 consumes - state owned parents - slot f0
    \\inst %4 dict_find Inspect reads %3,%1 consumes - state scalar parents -
    \\inst %6 cmp Pure reads %4,%5 consumes - state scalar parents - imm 5
    \\term branch %6 b1 b2
    \\block b1 preds b0
    \\term jump b3
    \\block b2 preds b0
    \\term jump b3
    \\block b3 preds b1,b2
    \\inst %11 cmp Pure reads %4,%10 consumes - state scalar parents - imm 5
    \\term branch %11 b4 b5
    \\block b4 preds b3
    \\inst %13 dict_remove Update reads %4 consumes %3 state owned parents - slot v%4 released key taken -
    \\term jump b6
    \\block b5 preds b3
    \\term jump b6
    \\block b6 preds b4,b5
    \\phi %16 owned parents - edges b4:%13,b5:%3
    \\inst %17 record_set Update reads - consumes %0,%16 state owned parents - slot f0
    \\term ret %17
    \\end
    \\
    },
    .{ .name = "a borrowed option of a written mut parameter returned beside its final value (O3, F-RA-115)", .text =
    \\function next result owned from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %11 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %16 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state scalar parents -
    \\inst %2 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %3 list_len Inspect reads %2 consumes - state scalar parents -
    \\inst %4 convert Pure reads %3 consumes - state scalar parents -
    \\inst %5 cmp Pure reads %1,%4 consumes - state scalar parents - imm 5
    \\term branch %5 b1 b2
    \\block b1 preds b0
    \\inst %7 union_make Construct reads - consumes - state borrowed parents -
    \\inst %8 record_make Construct reads %7 consumes %0 state owned parents %7 views %7
    \\term ret %8
    \\block b2 preds b0
    \\inst %10 record_get Project reads %0 consumes - state scalar parents -
    \\inst %12 add Pure reads %10,%11 consumes - state scalar parents -
    \\inst %13 record_set Update reads - consumes %0,%12 state owned parents -
    \\inst %14 record_get Project reads %13 consumes - state borrowed parents %13 slot f0
    \\inst %17 sub Pure reads %12,%16 consumes - state scalar parents -
    \\inst %18 list_get Project reads %14,%17 consumes - state borrowed parents %14 slot e%17
    \\inst %19 borrow Borrow reads %18 consumes - state borrowed parents %18
    \\inst %20 union_make Construct reads %19 consumes - state borrowed parents %19
    \\inst %21 record_make Construct reads %20 consumes %13 state owned parents %20 views %20
    \\term ret %21
    \\end
    \\
    },
    .{ .name = "a borrowed option of a mut parameter's final value read by the caller through the call's emptied result (O3, F-RA-115)", .text =
    \\function main result scalar from - unchecked -
    \\callee 0 next program take owned -
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %2 str_const Constant reads - consumes - state immortal parents -
    \\inst %5 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %11 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %21 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 list_new Fresh reads %0 consumes - state owned parents -
    \\inst %3 record_make Construct reads - consumes %2 state owned parents -
    \\inst %4 list_push Update reads - consumes %1,%3 state owned parents -
    \\inst %6 record_make Construct reads - consumes %4,%5 state owned parents -
    \\inst %7 call Call reads - consumes %6 state emptied parents - slots f1 from - callee 0
    \\inst %8 record_get Project reads %7 consumes - state owned parents - slot f1
    \\inst %9 record_get Project reads %7 consumes - state borrowed parents %7
    \\inst %10 union_tag Inspect reads %9 consumes - state scalar parents -
    \\inst %12 cmp Pure reads %10,%11 consumes - state scalar parents - imm 0
    \\term branch %12 b2 b3
    \\block b1 preds b4
    \\term ret %21
    \\block b2 preds b0
    \\inst %14 union_payload Project reads %9 consumes - state borrowed parents %8
    \\inst %15 record_get Project reads %14 consumes - state borrowed parents %14 slot f0
    \\inst %16 list_len Inspect reads %15 consumes - state scalar parents -
    \\inst - drop Drop reads - consumes %8 state none parents -
    \\inst %17 convert Pure reads %16 consumes - state scalar parents -
    \\term ret %17
    \\block b3 preds b0
    \\inst - drop Drop reads - consumes %8 state none parents -
    \\term jump b4
    \\block b4 preds b3
    \\term jump b1
    \\end
    \\
    },
    .{ .name = "an owned Result that lends its argument is dropped before the argument where both die (O3, loans first)", .text =
    \\function main result scalar from - unchecked -
    \\callee 0 at program read owned 0
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %2 str_const Constant reads - consumes - state immortal parents -
    \\inst %5 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %18 iconst Constant reads - consumes - state scalar parents - imm 2
    \\block b0 preds -
    \\inst %1 list_new Fresh reads %0 consumes - state owned parents -
    \\inst %3 record_make Construct reads - consumes %2 state owned parents -
    \\inst %4 list_push Update reads - consumes %1,%3 state owned parents -
    \\inst %6 record_make Construct reads - consumes %4,%5 state owned parents -
    \\inst %7 call Call reads %6 consumes - state owned parents %6 from %6 callee 0
    \\inst %8 union_tag Inspect reads %7 consumes - state scalar parents -
    \\inst %10 cmp Pure reads %8,%9 consumes - state scalar parents - imm 0
    \\term branch %10 b2 b3
    \\block b2 preds b0
    \\inst %12 union_payload Project reads %7 consumes - state borrowed parents %6
    \\inst - drop Drop reads - consumes %7 state none parents -
    \\inst %13 record_get Project reads %12 consumes - state borrowed parents %12 slot f0
    \\inst %14 list_len Inspect reads %13 consumes - state scalar parents -
    \\inst - drop Drop reads - consumes %6 state none parents -
    \\inst %15 convert Pure reads %14 consumes - state scalar parents -
    \\term ret %15
    \\block b3 preds b0
    \\inst - drop Drop reads - consumes %7 state none parents -
    \\inst - drop Drop reads - consumes %6 state none parents -
    \\term jump b4
    \\block b4 preds b3
    \\term ret %18
    \\end
    \\
    },
    .{ .name = "a borrowed Ok payload two projections below a call names the mut parameter's final value as a later take (O3)", .text =
    \\function main result scalar from - unchecked -
    \\callee 0 next program take owned -
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %2 str_const Constant reads - consumes - state immortal parents -
    \\inst %5 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %11 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %16 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %26 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %29 iconst Constant reads - consumes - state scalar parents - imm 2
    \\block b0 preds -
    \\inst %1 list_new Fresh reads %0 consumes - state owned parents -
    \\inst %3 record_make Construct reads - consumes %2 state owned parents -
    \\inst %4 list_push Update reads - consumes %1,%3 state owned parents -
    \\inst %6 record_make Construct reads - consumes %4,%5 state owned parents -
    \\inst %7 call Call reads - consumes %6 state emptied parents - slots f1 from - callee 0
    \\inst %8 record_get Project reads %7 consumes - state owned parents - slot f1
    \\inst %9 record_get Project reads %7 consumes - state borrowed parents %7
    \\inst %10 union_tag Inspect reads %9 consumes - state scalar parents -
    \\inst %12 cmp Pure reads %10,%11 consumes - state scalar parents - imm 0
    \\term branch %12 b2 b3
    \\block b2 preds b0
    \\inst %14 union_payload Project reads %9 consumes - state borrowed parents %9,%7
    \\inst %15 union_tag Inspect reads %14 consumes - state scalar parents -
    \\inst %17 cmp Pure reads %15,%16 consumes - state scalar parents - imm 0
    \\term branch %17 b5 b6
    \\block b3 preds b0
    \\inst - drop Drop reads - consumes %8 state none parents -
    \\term jump b8
    \\block b4 preds b7
    \\term ret %26
    \\block b5 preds b2
    \\inst %19 union_payload Project reads %14 consumes - state borrowed parents %8
    \\inst %20 record_get Project reads %19 consumes - state borrowed parents %19 slot f0
    \\inst %21 list_len Inspect reads %20 consumes - state scalar parents -
    \\inst - drop Drop reads - consumes %8 state none parents -
    \\inst %22 convert Pure reads %21 consumes - state scalar parents -
    \\term ret %22
    \\block b6 preds b2
    \\inst - drop Drop reads - consumes %8 state none parents -
    \\term jump b7
    \\block b7 preds b6
    \\term jump b4
    \\block b8 preds b3
    \\term ret %29
    \\end
    \\
    },
    .{ .name = "a narrowed option read as its payload in place after `if found is None: return` (O3, zero-copy 3a)", .text =
    \\function f204 result scalar from - unchecked -
    \\param 0 %0 scalar
    \\callee 0 lookup program read-scalar owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %3 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %13 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %17 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %25 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads %0 consumes - state owned parents - from - callee 0
    \\inst %2 union_tag Inspect reads %1 consumes - state scalar parents -
    \\inst %4 cmp Pure reads %2,%3 consumes - state scalar parents - imm 0
    \\term branch %4 b2 b3
    \\block b1 preds b2,b4
    \\phi %11 scalar parents - edges b2:%6,b4:%9
    \\term branch %11 b5 b6
    \\block b2 preds b0
    \\term jump b1
    \\block b3 preds b0
    \\term jump b4
    \\block b4 preds b3
    \\term jump b1
    \\block b5 preds b1
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %13
    \\block b6 preds b1
    \\inst %16 union_tag Inspect reads %1 consumes - state scalar parents -
    \\inst %18 cmp Pure reads %16,%17 consumes - state scalar parents - imm 0
    \\term branch %18 b8 b9
    \\block b7 preds b8
    \\inst %24 list_len Inspect reads %20 consumes - state scalar parents -
    \\inst %26 str_view_of View reads %20,%25,%24 consumes - state borrowed parents %20
    \\inst %27 list_len Inspect reads %26 consumes - state scalar parents -
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\inst %28 convert Pure reads %27 consumes - state scalar parents -
    \\term ret %28
    \\block b8 preds b6
    \\inst %20 union_payload Project reads %1 consumes - state borrowed parents %1
    \\term jump b7
    \\block b9 preds b6
    \\abandon b6 %1
    \\term jump b10
    \\block b10 preds b9
    \\term unreachable
    \\end
    \\
    },
    .{ .name = "a loop variable read again after each mut call on a sibling field of its record (O3, zero-copy 3b)", .text =
    \\function collect result owned from - unchecked -
    \\param 0 %0 owned
    \\callee 0 remember program take,read owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %32 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %36 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %41 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %47 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %70 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f1
    \\inst %3 list_len Inspect reads %1 consumes - state scalar parents -
    \\inst %4 convert Pure reads %3 consumes - state scalar parents -
    \\term jump b1
    \\block b1 preds b0,b10
    \\phi %6 scalar parents - edges b0:%2,b10:%71
    \\phi %7 scalar parents - edges b0:%4,b10:%68
    \\phi %10 owned parents - edges b0:%0,b10:%50
    \\inst %8 cmp Pure reads %6,%7 consumes - state scalar parents - imm 2
    \\term branch %8 b2 b4
    \\block b2 preds b1
    \\inst %12 record_get Project reads %10 consumes - state borrowed parents %10 slot f1
    \\inst %13 list_len Inspect reads %12 consumes - state scalar parents -
    \\inst %14 convert Pure reads %13 consumes - state scalar parents -
    \\inst %15 cmp Pure reads %14,%7 consumes - state scalar parents - imm 2
    \\term branch %15 b5 b6
    \\block b3 preds b6
    \\inst %53 record_get Project reads %50 consumes - state borrowed parents %50 slot f1
    \\inst %54 list_len Inspect reads %53 consumes - state scalar parents -
    \\inst %55 convert Pure reads %54 consumes - state scalar parents -
    \\inst %56 cmp Pure reads %55,%27 consumes - state scalar parents - imm 2
    \\term branch %56 b9 b10
    \\block b4 preds b1
    \\inst %73 record_get Project reads %10 consumes - state borrowed parents %10 slot f0
    \\inst %74 list_len Inspect reads %73 consumes - state scalar parents -
    \\inst %75 convert Pure reads %74 consumes - state scalar parents -
    \\inst %76 record_make Construct reads - consumes %75,%10 state owned parents -
    \\term ret %76
    \\block b5 preds b2
    \\inst %17 record_get Project reads %10 consumes - state borrowed parents %10 slot f1
    \\inst %18 list_len Inspect reads %17 consumes - state scalar parents -
    \\inst %19 convert Pure reads %18 consumes - state scalar parents -
    \\inst %20 cmp Pure reads %19,%7 consumes - state scalar parents - imm 0
    \\term branch %20 b7 b8
    \\block b6 preds b2,b7
    \\inst %25 record_get Project reads %10 consumes - state borrowed parents %10 slot f1
    \\inst %26 list_len Inspect reads %25 consumes - state scalar parents -
    \\inst %27 convert Pure reads %26 consumes - state scalar parents -
    \\inst %33 list_get_field Project reads %25,%6 consumes - state borrowed parents %25 slot e%6p0
    \\inst %34 record_get Project reads %10 consumes - state owned parents - slot f0
    \\inst %35 list_len Inspect reads %33 consumes - state scalar parents -
    \\inst %37 str_view_of View reads %33,%36,%35 consumes - state borrowed parents %33
    \\inst %38 call Call reads %37 consumes %34 state owned parents - from - callee 0
    \\inst %39 record_set Update reads - consumes %10,%38 state owned parents - slot f0
    \\inst %40 record_get Project reads %39 consumes - state owned parents - slot f0
    \\inst %42 record_get Project reads %39 consumes - state borrowed parents %39 slot f1
    \\inst %44 list_get_field Project reads %42,%6 consumes - state borrowed parents %42 slot e%6p0
    \\inst %46 list_len Inspect reads %44 consumes - state scalar parents -
    \\inst %48 str_view_of View reads %44,%47,%46 consumes - state borrowed parents %44
    \\inst %49 call Call reads %48 consumes %40 state owned parents - from - callee 0
    \\inst %50 record_set Update reads - consumes %39,%49 state owned parents - slot f0
    \\term jump b3
    \\block b7 preds b5
    \\term jump b6
    \\block b8 preds b5
    \\abandon b5 %10
    \\term unreachable
    \\block b9 preds b3
    \\inst %58 record_get Project reads %50 consumes - state borrowed parents %50 slot f1
    \\inst %59 list_len Inspect reads %58 consumes - state scalar parents -
    \\inst %60 convert Pure reads %59 consumes - state scalar parents -
    \\inst %61 cmp Pure reads %60,%27 consumes - state scalar parents - imm 0
    \\term branch %61 b11 b12
    \\block b10 preds b3,b11
    \\inst %66 record_get Project reads %50 consumes - state borrowed parents %50 slot f1
    \\inst %67 list_len Inspect reads %66 consumes - state scalar parents -
    \\inst %68 convert Pure reads %67 consumes - state scalar parents -
    \\inst %71 add Pure reads %6,%70 consumes - state scalar parents -
    \\term jump b1
    \\block b11 preds b9
    \\term jump b10
    \\block b12 preds b9
    \\abandon b9 %50
    \\term unreachable
    \\end
    \\
    },
    .{ .name = "an inner loop's collection read again from the outer loop variable's place after each write (O3, zero-copy 3b)", .text =
    \\function adjacency result owned from - unchecked -
    \\param 0 %0 owned
    \\callee 0 put program take,read owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %32 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %46 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %50 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %55 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %79 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %3 list_len Inspect reads %1 consumes - state scalar parents -
    \\inst %4 convert Pure reads %3 consumes - state scalar parents -
    \\term jump b1
    \\block b1 preds b0,b14
    \\phi %6 scalar parents - edges b0:%2,b14:%80
    \\phi %7 scalar parents - edges b0:%4,b14:%76
    \\phi %10 owned parents - edges b0:%0,b14:%40
    \\inst %8 cmp Pure reads %6,%7 consumes - state scalar parents - imm 2
    \\term branch %8 b2 b4
    \\block b2 preds b1
    \\inst %12 record_get Project reads %10 consumes - state borrowed parents %10 slot f0
    \\inst %13 list_len Inspect reads %12 consumes - state scalar parents -
    \\inst %14 convert Pure reads %13 consumes - state scalar parents -
    \\inst %15 cmp Pure reads %14,%7 consumes - state scalar parents - imm 2
    \\term branch %15 b5 b6
    \\block b3 preds b12
    \\inst %60 record_get Project reads %40 consumes - state borrowed parents %40 slot f0
    \\inst %61 list_len Inspect reads %60 consumes - state scalar parents -
    \\inst %62 convert Pure reads %61 consumes - state scalar parents -
    \\inst %64 cmp Pure reads %62,%27 consumes - state scalar parents - imm 2
    \\term branch %64 b13 b14
    \\block b4 preds b1
    \\inst %82 record_get Project reads %10 consumes - state borrowed parents %10 slot f1
    \\inst %83 dict_len Inspect reads %82 consumes - state scalar parents -
    \\inst %84 convert Pure reads %83 consumes - state scalar parents -
    \\inst %85 record_make Construct reads - consumes %84,%10 state owned parents -
    \\term ret %85
    \\block b5 preds b2
    \\inst %17 record_get Project reads %10 consumes - state borrowed parents %10 slot f0
    \\inst %18 list_len Inspect reads %17 consumes - state scalar parents -
    \\inst %19 convert Pure reads %18 consumes - state scalar parents -
    \\inst %20 cmp Pure reads %19,%7 consumes - state scalar parents - imm 0
    \\term branch %20 b7 b8
    \\block b6 preds b2,b7
    \\inst %25 record_get Project reads %10 consumes - state borrowed parents %10 slot f0
    \\inst %26 list_len Inspect reads %25 consumes - state scalar parents -
    \\inst %27 convert Pure reads %26 consumes - state scalar parents -
    \\inst %31 list_get_field Project reads %25,%6 consumes - state borrowed parents %25 slot e%6p1
    \\inst %33 list_len Inspect reads %31 consumes - state scalar parents -
    \\inst %34 convert Pure reads %33 consumes - state scalar parents -
    \\term jump b9
    \\block b7 preds b5
    \\term jump b6
    \\block b8 preds b5
    \\abandon b5 %10
    \\term unreachable
    \\block b9 preds b6,b11
    \\phi %36 scalar parents - edges b6:%32,b11:%56
    \\phi %40 owned parents - edges b6:%10,b11:%53
    \\inst %38 cmp Pure reads %36,%34 consumes - state scalar parents - imm 2
    \\term branch %38 b10 b12
    \\block b10 preds b9
    \\inst %41 record_get Project reads %40 consumes - state borrowed parents %40 slot f0
    \\inst %43 list_get_field Project reads %41,%6 consumes - state borrowed parents %41 slot e%6p1
    \\inst %47 list_get_field Project reads %43,%36 consumes - state borrowed parents %43 slot e%36p0
    \\inst %48 record_get Project reads %40 consumes - state owned parents - slot f1
    \\inst %49 list_len Inspect reads %47 consumes - state scalar parents -
    \\inst %51 str_view_of View reads %47,%50,%49 consumes - state borrowed parents %47
    \\inst %52 call Call reads %51 consumes %48 state owned parents - from - callee 0
    \\inst %53 record_set Update reads - consumes %40,%52 state owned parents - slot f1
    \\term jump b11
    \\block b11 preds b10
    \\inst %56 add Pure reads %36,%55 consumes - state scalar parents -
    \\term jump b9
    \\block b12 preds b9
    \\term jump b3
    \\block b13 preds b3
    \\inst %66 record_get Project reads %40 consumes - state borrowed parents %40 slot f0
    \\inst %67 list_len Inspect reads %66 consumes - state scalar parents -
    \\inst %68 convert Pure reads %67 consumes - state scalar parents -
    \\inst %69 cmp Pure reads %68,%27 consumes - state scalar parents - imm 0
    \\term branch %69 b15 b16
    \\block b14 preds b3,b15
    \\inst %74 record_get Project reads %40 consumes - state borrowed parents %40 slot f0
    \\inst %75 list_len Inspect reads %74 consumes - state scalar parents -
    \\inst %76 convert Pure reads %75 consumes - state scalar parents -
    \\inst %80 add Pure reads %6,%79 consumes - state scalar parents -
    \\term jump b1
    \\block b15 preds b13
    \\term jump b14
    \\block b16 preds b13
    \\abandon b13 %40
    \\term unreachable
    \\end
    \\
    },
    .{ .name = "a match arm with a number payload writes the element it matched (O3, zero-copy 3b)", .text =
    \\function m_fields::unadopt result owned from - unchecked -
    \\param 0 %0 owned
    \\param 1 %1 scalar
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %1 param Parameter reads - consumes - state scalar parents -
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %7 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %12 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %18 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %3 list_get_field Project reads %0,%1 consumes - state scalar parents -
    \\inst %5 cmp Pure reads %3,%4 consumes - state scalar parents - imm 0
    \\term branch %5 b2 b3
    \\block b2 preds b0
    \\inst %8 record_make Construct reads - consumes %7,%0 state owned parents -
    \\term ret %8
    \\block b3 preds b0
    \\term jump b4
    \\block b4 preds b3
    \\inst %11 list_get_field Project reads %0,%1 consumes - state scalar parents -
    \\inst %13 cmp Pure reads %11,%12 consumes - state scalar parents - imm 4
    \\term branch %13 b5 b6
    \\block b5 preds b4
    \\inst %15 union_make Construct reads - consumes - state scalar parents -
    \\inst %16 list_set Update reads %1 consumes %0,%15 state owned parents -
    \\term jump b6
    \\block b6 preds b4,b5
    \\phi %19 owned parents - edges b4:%0,b5:%16
    \\inst %20 record_make Construct reads - consumes %18,%19 state owned parents -
    \\term ret %20
    \\end
    \\
    },
    .{ .name = "a slice of a bytes view binding sliced again in place (O3, zero-copy 3c)", .text =
    \\function degree_len result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\callee 0 myl_core_view_slice runtime read,read-scalar,read-scalar,read-scalar borrowed 0
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 3
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %19 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %21 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %22 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %39 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %3 iconst Constant reads - consumes - state scalar parents - imm 0
    \\term branch %3 b1 b2
    \\block b1 preds b0
    \\inst %5 list_len Inspect reads %0 consumes - state scalar parents -
    \\inst %6 convert Pure reads %5 consumes - state scalar parents -
    \\term unreachable
    \\block b2 preds b0
    \\inst %8 list_len Inspect reads %0 consumes - state scalar parents -
    \\inst %9 convert Pure reads %8 consumes - state scalar parents -
    \\inst %10 cmp Pure reads %1,%9 consumes - state scalar parents - imm 4
    \\term branch %10 b3 b4
    \\block b3 preds b2
    \\inst %12 list_len Inspect reads %0 consumes - state scalar parents -
    \\inst %13 convert Pure reads %12 consumes - state scalar parents -
    \\term jump b4
    \\block b4 preds b2,b3
    \\phi %15 scalar parents - edges b2:%1,b3:%13
    \\inst %17 list_len Inspect reads %0 consumes - state scalar parents -
    \\inst %18 convert Pure reads %17 consumes - state scalar parents -
    \\inst %20 call Call reads %0,%15,%18,%19 consumes - state borrowed parents %0 from %0 callee 0
    \\inst %23 iconst Constant reads - consumes - state scalar parents - imm 0
    \\term branch %23 b5 b6
    \\block b5 preds b4
    \\inst %25 list_len Inspect reads %20 consumes - state scalar parents -
    \\inst %26 convert Pure reads %25 consumes - state scalar parents -
    \\term unreachable
    \\block b6 preds b4
    \\inst %28 list_len Inspect reads %20 consumes - state scalar parents -
    \\inst %29 convert Pure reads %28 consumes - state scalar parents -
    \\inst %30 cmp Pure reads %21,%29 consumes - state scalar parents - imm 4
    \\term branch %30 b7 b8
    \\block b7 preds b6
    \\inst %32 list_len Inspect reads %20 consumes - state scalar parents -
    \\inst %33 convert Pure reads %32 consumes - state scalar parents -
    \\term jump b8
    \\block b8 preds b6,b7
    \\phi %35 scalar parents - edges b6:%21,b7:%33
    \\inst %37 list_len Inspect reads %20 consumes - state scalar parents -
    \\inst %38 convert Pure reads %37 consumes - state scalar parents -
    \\inst %40 call Call reads %20,%35,%38,%39 consumes - state borrowed parents %20 from %20 callee 0
    \\inst %41 list_len Inspect reads %40 consumes - state scalar parents -
    \\inst %42 convert Pure reads %41 consumes - state scalar parents -
    \\term ret %42
    \\end
    \\
    },
    .{ .name = "a mut local holding a literal or an element field borrow (O3, zero-copy 3d)", .text =
    \\function label_of result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\param 1 %1 scalar
    \\param 2 %2 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %1 param Parameter reads - consumes - state scalar parents -
    \\inst %2 param Parameter reads - consumes - state borrowed parents ^2
    \\inst %3 str_const Constant reads - consumes - state immortal parents -
    \\inst %5 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %7 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %13 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %4 list_len Inspect reads %3 consumes - state scalar parents -
    \\inst %6 str_view_of View reads %3,%5,%4 consumes - state borrowed parents %3
    \\inst %8 cmp Pure reads %1,%7 consumes - state scalar parents - imm 5
    \\term branch %8 b1 b2
    \\block b1 preds b0
    \\inst %11 list_get_field Project reads %0,%1 consumes - state borrowed parents %0 slot e%1p0
    \\inst %12 list_len Inspect reads %11 consumes - state scalar parents -
    \\inst %14 str_view_of View reads %11,%13,%12 consumes - state borrowed parents %11
    \\term jump b2
    \\block b2 preds b0,b1
    \\phi %16 borrowed parents %6,%14 edges b0:%6,b1:%14
    \\inst %17 list_len Inspect reads %16 consumes - state scalar parents -
    \\inst %18 convert Pure reads %17 consumes - state scalar parents -
    \\term ret %18
    \\end
    \\
    },
    .{ .name = "a mut local holding a field borrow or a from call result (O3, zero-copy 3d)", .text =
    \\function pick result owned from - unchecked -
    \\param 0 %0 borrowed
    \\param 1 %1 scalar
    \\callee 0 flip program read borrowed 0
    \\callee 1 myl_core_view_copy_bytes runtime read owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %1 param Parameter reads - consumes - state scalar parents -
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %3 list_len Inspect reads %2 consumes - state scalar parents -
    \\inst %5 str_view_of View reads %2,%4,%3 consumes - state borrowed parents %2
    \\term branch %1 b1 b2
    \\block b1 preds b0
    \\inst %7 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %8 list_len Inspect reads %7 consumes - state scalar parents -
    \\inst %10 str_view_of View reads %7,%9,%8 consumes - state borrowed parents %7
    \\inst %11 call Call reads %10 consumes - state borrowed parents %10 from %10 callee 0
    \\term jump b2
    \\block b2 preds b0,b1
    \\phi %13 borrowed parents %5,%11 edges b0:%5,b1:%11
    \\inst %14 call Call reads %13 consumes - state owned parents - from - callee 1
    \\term ret %14
    \\end
    \\
    },
    .{ .name = "a mut local holding a literal or the field of a loop variable's element (O3, zero-copy 3d)", .text =
    \\function by_loop_variable result owned from - unchecked -
    \\param 0 %0 borrowed
    \\param 1 %1 borrowed
    \\callee 0 myl_core_str_eq runtime read,read scalar -
    \\callee 1 myl_core_view_copy_bytes runtime read owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %1 param Parameter reads - consumes - state borrowed parents ^1
    \\inst %2 str_const Constant reads - consumes - state immortal parents -
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %17 str_const Constant reads - consumes - state immortal parents -
    \\inst %22 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %27 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %3 list_len Inspect reads %2 consumes - state scalar parents -
    \\inst %5 str_view_of View reads %2,%4,%3 consumes - state borrowed parents %2
    \\inst %7 list_len Inspect reads %0 consumes - state scalar parents -
    \\inst %8 convert Pure reads %7 consumes - state scalar parents -
    \\term jump b1
    \\block b1 preds b0,b3
    \\phi %10 scalar parents - edges b0:%6,b3:%28
    \\phi %32 borrowed parents %5,%33 edges b0:%5,b3:%33
    \\inst %12 cmp Pure reads %10,%8 consumes - state scalar parents - imm 2
    \\term branch %12 b2 b4
    \\block b2 preds b1
    \\inst %15 list_get Project reads %0,%10 consumes - state borrowed parents %0 slot e%10
    \\inst %16 record_get Project reads %15 consumes - state borrowed parents %15 slot f0
    \\inst %18 call Call reads %16,%17 consumes - state scalar parents - from - callee 0
    \\term branch %18 b5 b6
    \\block b3 preds b6
    \\inst %28 add Pure reads %10,%27 consumes - state scalar parents -
    \\term jump b1
    \\block b4 preds b1
    \\inst %34 call Call reads %32 consumes - state owned parents - from - callee 1
    \\term ret %34
    \\block b5 preds b2
    \\inst %20 record_get Project reads %15 consumes - state borrowed parents %15 slot f1
    \\inst %21 list_len Inspect reads %20 consumes - state scalar parents -
    \\inst %23 str_view_of View reads %20,%22,%21 consumes - state borrowed parents %20
    \\term jump b6
    \\block b6 preds b2,b5
    \\phi %33 borrowed parents %32,%23 edges b2:%32,b5:%23
    \\term jump b3
    \\end
    \\
    },
    .{ .name = "a frame box (O4): Some(scope) of a read-only parameter lent into a borrowed record, never dropped", .text =
    \\function child result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\callee 0 depth program read scalar -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\block b0 preds -
    \\inst %4 box_frame View reads %0 consumes - state borrowed parents %0
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %2 borrow Borrow reads %1 consumes - state borrowed parents %1
    \\inst %3 borrow Borrow reads %2 consumes - state borrowed parents %2
    \\inst %5 union_make Construct reads %4 consumes - state borrowed parents %4
    \\inst %6 borrow Borrow reads %5 consumes - state borrowed parents %5
    \\inst %7 borrow Borrow reads %6 consumes - state borrowed parents %6
    \\inst %8 record_make Construct reads %3,%7 consumes - state borrowed parents %3,%7
    \\inst %9 borrow Borrow reads %8 consumes - state borrowed parents %8
    \\inst %10 call Call reads %9 consumes - state scalar parents - from - callee 0
    \\term ret %10
    \\end
    \\
    },
};

const rejected = [_]Fixture{
    // FX12: a `match mut` binding read as a method's receiver was lowered to an `undef` of `str`, the null owner, and the
    // runtime helper that read it crashed. The null owner may fill a join, a store or a drop, but nothing may read it.
    .{ .name = "an undef of a managed type (the null owner) read by an operation", .reject = .j3, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %2 undef Constant reads - consumes - state immortal parents -
    \\block b0 preds -
    \\inst %3 str_len Inspect reads %2 consumes - state scalar parents -
    \\term ret %3
    \\end
    \\
    },
    // FX15: the two unsound neighbours of the exchanged element emptied by its field read (accepted above).
    .{ .name = "an exchanged element emptied but its field never taken", .reject = .j8, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 scalar
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 2
    \\inst %3 str_const Constant reads - consumes - state immortal parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %10 str_const Constant reads - consumes - state immortal parents -
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\inst %4 record_make Construct reads - consumes %3 state owned parents -
    \\inst %5 list_push Update reads - consumes %2,%4 state owned parents -
    \\inst %11 record_make Construct reads - consumes %10 state owned parents -
    \\inst %13 list_get Project reads %5,%9 consumes - state emptied parents - slot e%9 slots f0
    \\inst %14 list_set Update reads %9 consumes %5,%11 state owned parents - slot e%9 released -
    \\inst - drop Drop reads - consumes %14 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "an exchanged element emptied by its field read, and the store releases the slot it took", .reject = .j8, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 scalar
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 2
    \\inst %3 str_const Constant reads - consumes - state immortal parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %10 str_const Constant reads - consumes - state immortal parents -
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\inst %4 record_make Construct reads - consumes %3 state owned parents -
    \\inst %5 list_push Update reads - consumes %2,%4 state owned parents -
    \\inst %11 record_make Construct reads - consumes %10 state owned parents -
    \\inst %13 list_get Project reads %5,%9 consumes - state emptied parents - slot e%9 slots f0
    \\inst %14 list_set Update reads %9 consumes %5,%11 state owned parents - slot e%9 released old
    \\inst %15 record_get Project reads %13 consumes - state owned parents - slot f0
    \\inst - print Output reads %0,%15 consumes - state none parents -
    \\inst - drop Drop reads - consumes %14 state none parents -
    \\inst - drop Drop reads - consumes %15 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a list never dropped", .reject = .j2, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "a list dropped twice", .reject = .j2, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "a list read after its drop", .reject = .j3, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\inst %3 list_len Inspect reads %2 consumes - state scalar parents -
    \\term ret %3
    \\end
    \\
    },
    .{ .name = "a view used after its owner is dropped", .reject = .j4, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\inst %3 list_view_of View reads %2 consumes - state borrowed parents %2
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\inst %4 list_len Inspect reads %3 consumes - state scalar parents -
    \\term ret %4
    \\end
    \\
    },
    .{ .name = "a borrowed parameter dropped", .reject = .j5, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst - drop Drop reads - consumes %0 state none parents -
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "a borrow returned outside the result's from", .reject = .j5, .text =
    \\function f result borrowed from - unchecked -
    \\param 0 %0 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\block b0 preds -
    \\inst %1 str_view_of View reads %0 consumes - state borrowed parents %0
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "an owner consumed by the call that also reads it", .reject = .j6, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime take,read scalar -
    \\block b- preds -
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\inst %3 call Call reads %2 consumes %2 state scalar parents - from - callee 0
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "a stack list returned", .reject = .j7, .text =
    \\function f result owned from - unchecked -
    \\block b- preds -
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state stack parents -
    \\term ret %2
    \\end
    \\
    },
    .{ .name = "a stack list handed to a call that takes it", .reject = .j7, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime take scalar -
    \\block b- preds -
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state stack parents -
    \\inst %3 call Call reads - consumes %2 state scalar parents - from - callee 0
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "an owner pushed into a stack list", .reject = .j7, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state stack parents -
    \\inst %3 list_new Fresh reads %1 consumes - state owned parents -
    \\inst %4 list_push Update reads - consumes %2,%3 state stack parents -
    \\term ret %1
    \\end
    \\
    },
    // 4e: the lowering never returns a view of a fresh empty list under `from`: the returned borrow would live in a list
    // this function owns, which nobody destroys and which the caller cannot reach.
    .{ .name = "a view of a fresh empty list returned as a borrowed result", .reject = .j5, .text =
    \\function f result borrowed from 0 unchecked -
    \\param 0 %0 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %10 list_new Fresh reads %9 consumes - state owned parents -
    \\inst %11 list_view_of View reads %10 consumes - state borrowed parents %10
    \\term ret %11
    \\end
    \\
    },
    // 4a: a drain that took the last element without popping it would carry the open take round the loop.
    .{ .name = "a consuming loop that takes an element without popping it", .reject = .j8, .text =
    \\function f result owned from - unchecked -
    \\param 0 %0 owned
    \\callee 0 myl_core_owned_list_reverse runtime take,read-scalar owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %3 iconst Constant reads - consumes - state scalar parents - imm 16
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %13 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\inst %4 call Call reads %3 consumes %0 state owned parents - from - callee 0
    \\term jump b1
    \\block b1 preds b0,b3
    \\phi %6 owned parents - edges b0:%4,b3:%6
    \\phi %17 owned parents - edges b0:%2,b3:%19
    \\inst %7 list_len Inspect reads %6 consumes - state scalar parents -
    \\inst %8 convert Pure reads %7 consumes - state scalar parents -
    \\inst %10 cmp Pure reads %8,%9 consumes - state scalar parents - imm 4
    \\term branch %10 b2 b4
    \\block b2 preds b1
    \\inst %12 list_len Inspect reads %6 consumes - state scalar parents -
    \\inst %14 sub Pure reads %12,%13 consumes - state scalar parents -
    \\inst %15 list_get Project reads %6,%14 consumes - state owned parents - slot e%14
    \\inst %18 record_take Take reads - consumes %15 state owned parents - noloans
    \\inst %19 list_push Update reads - consumes %17,%18 state owned parents -
    \\term jump b3
    \\block b3 preds b2
    \\term jump b1
    \\block b4 preds b1
    \\inst - drop Drop reads - consumes %6 state none parents -
    \\term ret %17
    \\end
    \\
    },
    // G3 3A: the lowering closes an element take with the store of the replacement. Without it, the list would be
    // returned holding a pointer the caller also owns.
    .{ .name = "a list returned while the take of one of its elements is open", .reject = .j8, .text =
    \\function f result owned from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %5 list_get Project reads %0,%1 consumes - state owned parents - slot e#0
    \\inst %7 record_make Construct reads - consumes %5,%0 state owned parents -
    \\term ret %7
    \\end
    \\
    },
    // G3 3A: a store at another element does not close the take: the taken element is still open at the return.
    .{ .name = "a list store at another element leaves an element take open", .reject = .j8, .text =
    \\function f result owned from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %3 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %4 list_new Fresh reads %3 consumes - state owned parents -
    \\inst %5 list_get Project reads %0,%1 consumes - state owned parents - slot e#0
    \\inst %6 list_set Update reads %2 consumes %0,%4 state owned parents - slot e#1 released -
    \\inst %7 record_make Construct reads - consumes %5,%6 state owned parents -
    \\term ret %7
    \\end
    \\
    },
    .{ .name = "one slot taken twice", .reject = .j8, .text =
    \\function f result owned from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state owned parents - slot f0
    \\inst %2 record_get Project reads %0 consumes - state owned parents - slot f0
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %0
    \\end
    \\
    },
    .{ .name = "a container dropped while a take from it is open", .reject = .j8, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state owned parents - slot f0
    \\inst - drop Drop reads - consumes %0 state none parents -
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a store into a slot nothing took", .reject = .j8, .text =
    \\function f result owned from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %9 consumes - state owned parents -
    \\inst %3 record_set Update reads - consumes %0,%2 state owned parents - slot f0
    \\term ret %3
    \\end
    \\
    },
    .{ .name = "a take from a borrowed container", .reject = .j8, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %9 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state owned parents - slot f0
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a return with a take still open", .reject = .j8, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state owned parents - slot f0
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "an emptied record whose slot is taken twice", .reject = .j8, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %6 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %5 list_new Fresh reads %6 consumes - state owned parents -
    \\inst %1 record_make Construct reads - consumes %5 state emptied parents - slots f0
    \\inst %2 record_get Project reads %1 consumes - state owned parents - slot f0
    \\inst %3 record_get Project reads %1 consumes - state owned parents - slot f0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\inst - drop Drop reads - consumes %3 state none parents -
    \\term ret %6
    \\end
    \\
    },
    .{ .name = "an emptied record that is consumed", .reject = .j8, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %6 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %5 list_new Fresh reads %6 consumes - state owned parents -
    \\inst %1 record_make Construct reads - consumes %5 state emptied parents - slots f0
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %6
    \\end
    \\
    },
    .{ .name = "an operation stated as another class", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %2 list_len Fresh reads %1 consumes - state owned parents -
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "arithmetic that yields an owner", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %2 add Pure reads %1,%1 consumes - state owned parents -
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "a join where one arm consumed the owner", .reject = .j2, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 scalar
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\term branch %0 b1 b2
    \\block b1 preds b0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term jump b3
    \\block b2 preds b0
    \\term jump b3
    \\block b3 preds b1,b2
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "a borrowed name defined on one path only", .reject = .j4, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 scalar
    \\param 1 %5 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %5 param Parameter reads - consumes - state borrowed parents ^1
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\term branch %0 b1 b2
    \\block b1 preds b0
    \\inst %3 str_view_of View reads %5 consumes - state borrowed parents %5
    \\term jump b3
    \\block b2 preds b0
    \\term jump b3
    \\block b3 preds b1,b2
    \\inst %4 str_len Inspect reads %3 consumes - state scalar parents -
    \\term ret %4
    \\end
    \\
    },
    .{ .name = "a take closed under a branch on another test", .reject = .j8, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 18446744073709551615
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 dict_find Inspect reads %0,%9 consumes - state scalar parents -
    \\inst %4 cmp Pure reads %2,%1 consumes - state scalar parents - imm 1
    \\term branch %4 b1 b2
    \\block b1 preds b0
    \\inst %5 dict_entry_value Project reads %0,%2 consumes - state owned parents - slot v%2
    \\inst - drop Drop reads - consumes %5 state none parents -
    \\term jump b3
    \\block b2 preds b0
    \\term jump b3
    \\block b3 preds b1,b2
    \\inst %6 cmp Pure reads %2,%1 consumes - state scalar parents - imm 0
    \\term branch %6 b4 b5
    \\block b4 preds b3
    \\inst %7 dict_remove Update reads %2 consumes %0 state owned parents - slot v%2 released - taken value
    \\term jump b6
    \\block b5 preds b3
    \\term jump b6
    \\block b6 preds b4,b5
    \\phi %8 owned parents - edges b4:%7,b5:%0
    \\inst - drop Drop reads - consumes %8 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a take closed on the arm where the decision says it is not open", .reject = .j8, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 18446744073709551615
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 dict_find Inspect reads %0,%9 consumes - state scalar parents -
    \\inst %4 cmp Pure reads %2,%1 consumes - state scalar parents - imm 1
    \\term branch %4 b1 b2
    \\block b1 preds b0
    \\inst %5 dict_entry_value Project reads %0,%2 consumes - state owned parents - slot v%2
    \\inst - drop Drop reads - consumes %5 state none parents -
    \\term jump b3
    \\block b2 preds b0
    \\term jump b3
    \\block b3 preds b1,b2
    \\inst %6 cmp Pure reads %2,%1 consumes - state scalar parents - imm 1
    \\term branch %6 b5 b4
    \\block b4 preds b3
    \\inst %7 dict_remove Update reads %2 consumes %0 state owned parents - slot v%2 released - taken value
    \\term jump b6
    \\block b5 preds b3
    \\term jump b6
    \\block b6 preds b4,b5
    \\phi %8 owned parents - edges b4:%7,b5:%0
    \\inst - drop Drop reads - consumes %8 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a unit value read as an operand", .reject = .j3, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %1 undef Constant reads - consumes - state none parents -
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %3 list_len Inspect reads %1 consumes - state scalar parents -
    \\term ret %2
    \\end
    \\
    },
    // R2, disjoint fields: the lowering never produces this shape. A `const` binding of `self.items[i]` that is read after `self.count`
    // was written is read again from the updated record (the accepted twin below); the validator still refuses the borrow that
    // outlives the update of the container it was read from, so no proof depends on the lowering's care.
    .{ .name = "a borrow of one slot used after another slot of its container is replaced", .reject = .j4, .text =
    \\function f result owned from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %2 record_set Update reads - consumes %0,%9 state owned parents -
    \\inst %3 list_len Inspect reads %1 consumes - state scalar parents -
    \\term ret %2
    \\end
    \\
    },
    .{ .name = "a borrow of a slot used after the slot is taken", .reject = .j4, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %2 record_get Project reads %0 consumes - state owned parents - slot f0
    \\inst %3 list_len Inspect reads %1 consumes - state scalar parents -
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\inst %5 list_new Fresh reads %9 consumes - state owned parents -
    \\inst %6 record_set Update reads - consumes %0,%5 state owned parents - slot f0 released -
    \\inst - drop Drop reads - consumes %6 state none parents -
    \\term ret %3
    \\end
    \\
    },
    .{ .name = "a phi takes the owner over on one edge while the other edge destroyed it", .reject = .j4, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 scalar
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\inst %3 list_view_of View reads %2 consumes - state borrowed parents %2
    \\term branch %0 b1 b2
    \\block b1 preds b0
    \\term jump b3
    \\block b2 preds b0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\inst %6 list_new Fresh reads %1 consumes - state owned parents -
    \\term jump b3
    \\block b3 preds b1,b2
    \\phi %4 owned parents - edges b1:%2,b2:%6
    \\inst %5 list_len Inspect reads %3 consumes - state scalar parents -
    \\inst - drop Drop reads - consumes %4 state none parents -
    \\term ret %5
    \\end
    \\
    },
    .{ .name = "a removal releases a value an owned read has taken", .reject = .j8, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 dict_find Inspect reads %0,%9 consumes - state scalar parents -
    \\inst %5 dict_entry_value Project reads %0,%2 consumes - state owned parents - slot v%2
    \\inst - drop Drop reads - consumes %5 state none parents -
    \\inst %7 dict_remove Update reads %2 consumes %0 state owned parents - slot v%2 released value
    \\inst - drop Drop reads - consumes %7 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a view written ahead of a take, read before the take is defined", .reject = .j4, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %2 slot f0
    \\inst %3 list_len Inspect reads %1 consumes - state scalar parents -
    \\inst %2 record_get Project reads %0 consumes - state owned parents - slot f0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\inst %5 list_new Fresh reads %9 consumes - state owned parents -
    \\inst %6 record_set Update reads - consumes %0,%5 state owned parents - slot f0 released -
    \\inst - drop Drop reads - consumes %6 state none parents -
    \\term ret %3
    \\end
    \\
    },
    .{ .name = "an owner consumed while the call result that holds a loan on it is live", .reject = .j4, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime read owned -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %9 consumes - state owned parents -
    \\inst %3 list_view_of View reads %2 consumes - state borrowed parents %2
    \\inst %4 call Call reads %3 consumes - state owned parents %3 from - callee 0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\inst - drop Drop reads - consumes %4 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a slot taken while an owned value holds a loan on it", .reject = .j4, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 myl_core_fixture_0 runtime read owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %4 call Call reads %1 consumes - state owned parents %1 from - callee 0
    \\inst %2 record_get Project reads %0 consumes - state owned parents - slot f0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\inst - drop Drop reads - consumes %4 state none parents -
    \\inst %5 list_new Fresh reads %9 consumes - state owned parents -
    \\inst %6 record_set Update reads - consumes %0,%5 state owned parents - slot f0 released -
    \\inst - drop Drop reads - consumes %6 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a lender dropped before the group is joined", .reject = .j4, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime - scalar -
    \\callee 1 myl_core_fixture_1 runtime read scalar -
    \\callee 2 myl_core_fixture_2 runtime - owned -
    \\callee 3 myl_core_fixture_3 runtime take,read,read,read scalar -
    \\callee 4 myl_core_fixture_4 runtime read,read owned -
    \\callee 5 myl_core_fixture_5 runtime take scalar -
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 2
    \\inst %8 iconst Constant reads - consumes - state scalar parents - imm 3
    \\inst %10 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %13 iconst Constant reads - consumes - state scalar parents - imm 2000
    \\inst %16 func_ref Constant reads - consumes - state scalar parents -
    \\inst %17 iconst Constant reads - consumes - state scalar parents - imm 18446744073709551615
    \\inst %23 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\inst - call Call reads %23 consumes - state none parents - from - callee 1
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 2
    \\inst %3 list_new Fresh reads %2 consumes - state owned parents -
    \\inst %5 list_push Update reads - consumes %3,%4 state owned parents -
    \\inst %7 list_push Update reads - consumes %5,%6 state owned parents -
    \\inst %9 list_push Update reads - consumes %7,%8 state owned parents -
    \\inst %11 list_push Update reads - consumes %9,%10 state owned parents -
    \\inst %12 box_make Construct reads %11,%1 consumes - state owned parents - lent %1
    \\inst %14 record_make Construct reads - consumes %12,%13 state owned parents -
    \\inst %15 box_make Construct reads - consumes %14 state owned parents -
    \\inst %18 call Call reads %1,%16,%17 consumes %15 state scalar parents - from - callee 3
    \\inst %19 call Call reads %1,%18 consumes - state owned parents - from - callee 4
    \\inst %20 box_take Take reads - consumes %19 state scalar parents -
    \\inst - drop Drop reads - consumes %11 state none parents -
    \\inst - call Call reads - consumes %1 state none parents - from - callee 5
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\term ret %20
    \\end
    \\
    },
    .{ .name = "a lender consumed by an update before the group is joined", .reject = .j4, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime - scalar -
    \\callee 1 myl_core_fixture_1 runtime read scalar -
    \\callee 2 myl_core_fixture_2 runtime - owned -
    \\callee 3 myl_core_fixture_3 runtime take,read,read,read scalar -
    \\callee 4 myl_core_fixture_4 runtime read,read owned -
    \\callee 5 myl_core_fixture_5 runtime take scalar -
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 2
    \\inst %8 iconst Constant reads - consumes - state scalar parents - imm 3
    \\inst %10 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %13 iconst Constant reads - consumes - state scalar parents - imm 2000
    \\inst %16 func_ref Constant reads - consumes - state scalar parents -
    \\inst %17 iconst Constant reads - consumes - state scalar parents - imm 18446744073709551615
    \\inst %23 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\inst - call Call reads %23 consumes - state none parents - from - callee 1
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 2
    \\inst %3 list_new Fresh reads %2 consumes - state owned parents -
    \\inst %5 list_push Update reads - consumes %3,%4 state owned parents -
    \\inst %7 list_push Update reads - consumes %5,%6 state owned parents -
    \\inst %9 list_push Update reads - consumes %7,%8 state owned parents -
    \\inst %11 list_push Update reads - consumes %9,%10 state owned parents -
    \\inst %12 box_make Construct reads %11,%1 consumes - state owned parents - lent %1
    \\inst %14 record_make Construct reads - consumes %12,%13 state owned parents -
    \\inst %15 box_make Construct reads - consumes %14 state owned parents -
    \\inst %18 call Call reads %1,%16,%17 consumes %15 state scalar parents - from - callee 3
    \\inst %19 call Call reads %1,%18 consumes - state owned parents - from - callee 4
    \\inst %20 box_take Take reads - consumes %19 state scalar parents -
    \\inst %99 list_push Update reads - consumes %11,%10 state owned parents -
    \\inst - call Call reads - consumes %1 state none parents - from - callee 5
    \\inst - drop Drop reads - consumes %11 state none parents -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\term ret %20
    \\end
    \\
    },
    .{ .name = "a lent slot view whose slot is taken before the group is joined", .reject = .j4, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 myl_core_fixture_0 runtime - owned -
    \\callee 1 myl_core_fixture_1 runtime take,read,read,read scalar -
    \\callee 2 myl_core_fixture_2 runtime take scalar -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %8 func_ref Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 0
    \\inst %2 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %3 box_make Construct reads %2,%1 consumes - state owned parents - lent %1
    \\inst %4 box_make Construct reads - consumes %3 state owned parents -
    \\inst %5 call Call reads %1,%8,%9 consumes %4 state scalar parents - from - callee 1
    \\inst %6 record_get Project reads %0 consumes - state owned parents - slot f0
    \\inst - call Call reads - consumes %1 state none parents - from - callee 2
    \\inst %7 record_set Update reads - consumes %0,%6 state owned parents - slot f0
    \\inst - drop Drop reads - consumes %7 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a group that is never joined", .reject = .j2, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\callee 0 myl_core_fixture_0 runtime - owned -
    \\callee 1 myl_core_fixture_1 runtime take,read,read,read scalar -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %8 func_ref Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 0
    \\inst %3 box_make Construct reads %0,%1 consumes - state owned parents - lent %1
    \\inst %4 box_make Construct reads - consumes %3 state owned parents -
    \\inst %5 call Call reads %1,%8,%9 consumes %4 state scalar parents - from - callee 1
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a lender dropped while its group is never joined", .reject = .j4, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime - scalar -
    \\callee 1 myl_core_fixture_1 runtime read scalar -
    \\callee 2 myl_core_fixture_2 runtime - owned -
    \\callee 3 myl_core_fixture_3 runtime take,read,read,read scalar -
    \\callee 4 myl_core_fixture_4 runtime read,read owned -
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 2
    \\inst %8 iconst Constant reads - consumes - state scalar parents - imm 3
    \\inst %10 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %13 iconst Constant reads - consumes - state scalar parents - imm 2000
    \\inst %16 func_ref Constant reads - consumes - state scalar parents -
    \\inst %17 iconst Constant reads - consumes - state scalar parents - imm 18446744073709551615
    \\inst %23 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\inst - call Call reads %23 consumes - state none parents - from - callee 1
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 2
    \\inst %3 list_new Fresh reads %2 consumes - state owned parents -
    \\inst %5 list_push Update reads - consumes %3,%4 state owned parents -
    \\inst %7 list_push Update reads - consumes %5,%6 state owned parents -
    \\inst %9 list_push Update reads - consumes %7,%8 state owned parents -
    \\inst %11 list_push Update reads - consumes %9,%10 state owned parents -
    \\inst %12 box_make Construct reads %11,%1 consumes - state owned parents - lent %1
    \\inst %14 record_make Construct reads - consumes %12,%13 state owned parents -
    \\inst %15 box_make Construct reads - consumes %14 state owned parents -
    \\inst %18 call Call reads %1,%16,%17 consumes %15 state scalar parents - from - callee 3
    \\inst %19 call Call reads %1,%18 consumes - state owned parents - from - callee 4
    \\inst %20 box_take Take reads - consumes %19 state scalar parents -
    \\inst - drop Drop reads - consumes %11 state none parents -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\term ret %20
    \\end
    \\
    },
    .{ .name = "a group never joined whose lender is dropped by nobody", .reject = .j2, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime - scalar -
    \\callee 1 myl_core_fixture_1 runtime read scalar -
    \\callee 2 myl_core_fixture_2 runtime - owned -
    \\callee 3 myl_core_fixture_3 runtime take,read,read,read scalar -
    \\callee 4 myl_core_fixture_4 runtime read,read owned -
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 2
    \\inst %8 iconst Constant reads - consumes - state scalar parents - imm 3
    \\inst %10 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %13 iconst Constant reads - consumes - state scalar parents - imm 2000
    \\inst %16 func_ref Constant reads - consumes - state scalar parents -
    \\inst %17 iconst Constant reads - consumes - state scalar parents - imm 18446744073709551615
    \\inst %23 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\inst - call Call reads %23 consumes - state none parents - from - callee 1
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 2
    \\inst %3 list_new Fresh reads %2 consumes - state owned parents -
    \\inst %5 list_push Update reads - consumes %3,%4 state owned parents -
    \\inst %7 list_push Update reads - consumes %5,%6 state owned parents -
    \\inst %9 list_push Update reads - consumes %7,%8 state owned parents -
    \\inst %11 list_push Update reads - consumes %9,%10 state owned parents -
    \\inst %12 box_make Construct reads %11,%1 consumes - state owned parents - lent %1
    \\inst %14 record_make Construct reads - consumes %12,%13 state owned parents -
    \\inst %15 box_make Construct reads - consumes %14 state owned parents -
    \\inst %18 call Call reads %1,%16,%17 consumes %15 state scalar parents - from - callee 3
    \\inst %19 call Call reads %1,%18 consumes - state owned parents - from - callee 4
    \\inst %20 box_take Take reads - consumes %19 state scalar parents -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\term ret %20
    \\end
    \\
    },
    .{ .name = "a task submitted after the group is joined", .reject = .j3, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime - scalar -
    \\callee 1 myl_core_fixture_1 runtime read scalar -
    \\callee 2 myl_core_fixture_2 runtime - owned -
    \\callee 3 myl_core_fixture_3 runtime take,read,read,read scalar -
    \\callee 4 myl_core_fixture_4 runtime read,read owned -
    \\callee 5 myl_core_fixture_5 runtime take scalar -
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 2
    \\inst %8 iconst Constant reads - consumes - state scalar parents - imm 3
    \\inst %10 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %13 iconst Constant reads - consumes - state scalar parents - imm 2000
    \\inst %16 func_ref Constant reads - consumes - state scalar parents -
    \\inst %17 iconst Constant reads - consumes - state scalar parents - imm 18446744073709551615
    \\inst %23 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\inst - call Call reads %23 consumes - state none parents - from - callee 1
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 2
    \\inst %3 list_new Fresh reads %2 consumes - state owned parents -
    \\inst %5 list_push Update reads - consumes %3,%4 state owned parents -
    \\inst %7 list_push Update reads - consumes %5,%6 state owned parents -
    \\inst %9 list_push Update reads - consumes %7,%8 state owned parents -
    \\inst %11 list_push Update reads - consumes %9,%10 state owned parents -
    \\inst %12 box_make Construct reads %11,%1 consumes - state owned parents - lent %1
    \\inst %14 record_make Construct reads - consumes %12,%13 state owned parents -
    \\inst %15 box_make Construct reads - consumes %14 state owned parents -
    \\inst %18 call Call reads %1,%16,%17 consumes %15 state scalar parents - from - callee 3
    \\inst %19 call Call reads %1,%18 consumes - state owned parents - from - callee 4
    \\inst %20 box_take Take reads - consumes %19 state scalar parents -
    \\inst - call Call reads - consumes %1 state none parents - from - callee 5
    \\inst %99 call Call reads %1,%16,%17 consumes %15 state scalar parents - from - callee 3
    \\inst - drop Drop reads - consumes %11 state none parents -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\term ret %20
    \\end
    \\
    },
    .{ .name = "a lend onto a value that is not owned", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime - scalar -
    \\callee 1 myl_core_fixture_1 runtime read scalar -
    \\callee 2 myl_core_fixture_2 runtime take,read,read,read scalar -
    \\callee 3 myl_core_fixture_3 runtime read,read owned -
    \\callee 4 myl_core_fixture_4 runtime take scalar -
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 2
    \\inst %8 iconst Constant reads - consumes - state scalar parents - imm 3
    \\inst %10 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %13 iconst Constant reads - consumes - state scalar parents - imm 2000
    \\inst %16 func_ref Constant reads - consumes - state scalar parents -
    \\inst %17 iconst Constant reads - consumes - state scalar parents - imm 18446744073709551615
    \\inst %23 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\inst - call Call reads %23 consumes - state none parents - from - callee 1
    \\inst %1 call Call reads - consumes - state scalar parents - from - callee 0
    \\inst %3 list_new Fresh reads %2 consumes - state owned parents -
    \\inst %5 list_push Update reads - consumes %3,%4 state owned parents -
    \\inst %7 list_push Update reads - consumes %5,%6 state owned parents -
    \\inst %9 list_push Update reads - consumes %7,%8 state owned parents -
    \\inst %11 list_push Update reads - consumes %9,%10 state owned parents -
    \\inst %12 box_make Construct reads %11,%1 consumes - state owned parents - lent %1
    \\inst %14 record_make Construct reads - consumes %12,%13 state owned parents -
    \\inst %15 box_make Construct reads - consumes %14 state owned parents -
    \\inst %18 call Call reads %1,%16,%17 consumes %15 state scalar parents - from - callee 2
    \\inst %19 call Call reads %1,%18 consumes - state owned parents - from - callee 3
    \\inst %20 box_take Take reads - consumes %19 state scalar parents -
    \\inst - call Call reads - consumes %1 state none parents - from - callee 4
    \\inst - drop Drop reads - consumes %11 state none parents -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\term ret %20
    \\end
    \\
    },
    .{ .name = "a lend that reads three values", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime - scalar -
    \\callee 1 myl_core_fixture_1 runtime read scalar -
    \\callee 2 myl_core_fixture_2 runtime - owned -
    \\callee 3 myl_core_fixture_3 runtime take,read,read,read scalar -
    \\callee 4 myl_core_fixture_4 runtime read,read owned -
    \\callee 5 myl_core_fixture_5 runtime take scalar -
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 2
    \\inst %8 iconst Constant reads - consumes - state scalar parents - imm 3
    \\inst %10 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %13 iconst Constant reads - consumes - state scalar parents - imm 2000
    \\inst %16 func_ref Constant reads - consumes - state scalar parents -
    \\inst %17 iconst Constant reads - consumes - state scalar parents - imm 18446744073709551615
    \\inst %23 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\inst - call Call reads %23 consumes - state none parents - from - callee 1
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 2
    \\inst %3 list_new Fresh reads %2 consumes - state owned parents -
    \\inst %5 list_push Update reads - consumes %3,%4 state owned parents -
    \\inst %7 list_push Update reads - consumes %5,%6 state owned parents -
    \\inst %9 list_push Update reads - consumes %7,%8 state owned parents -
    \\inst %11 list_push Update reads - consumes %9,%10 state owned parents -
    \\inst %12 box_make Construct reads %11,%1,%10 consumes - state owned parents - lent %1
    \\inst %14 record_make Construct reads - consumes %12,%13 state owned parents -
    \\inst %15 box_make Construct reads - consumes %14 state owned parents -
    \\inst %18 call Call reads %1,%16,%17 consumes %15 state scalar parents - from - callee 3
    \\inst %19 call Call reads %1,%18 consumes - state owned parents - from - callee 4
    \\inst %20 box_take Take reads - consumes %19 state scalar parents -
    \\inst - call Call reads - consumes %1 state none parents - from - callee 5
    \\inst - drop Drop reads - consumes %11 state none parents -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\term ret %20
    \\end
    \\
    },
    .{ .name = "a group joined by a drop", .reject = .j2, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime - scalar -
    \\callee 1 myl_core_fixture_1 runtime read scalar -
    \\callee 2 myl_core_fixture_2 runtime - owned -
    \\callee 3 myl_core_fixture_3 runtime take,read,read,read scalar -
    \\callee 4 myl_core_fixture_4 runtime read,read owned -
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 2
    \\inst %8 iconst Constant reads - consumes - state scalar parents - imm 3
    \\inst %10 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %13 iconst Constant reads - consumes - state scalar parents - imm 2000
    \\inst %16 func_ref Constant reads - consumes - state scalar parents -
    \\inst %17 iconst Constant reads - consumes - state scalar parents - imm 18446744073709551615
    \\inst %23 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\inst - call Call reads %23 consumes - state none parents - from - callee 1
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 2
    \\inst %3 list_new Fresh reads %2 consumes - state owned parents -
    \\inst %5 list_push Update reads - consumes %3,%4 state owned parents -
    \\inst %7 list_push Update reads - consumes %5,%6 state owned parents -
    \\inst %9 list_push Update reads - consumes %7,%8 state owned parents -
    \\inst %11 list_push Update reads - consumes %9,%10 state owned parents -
    \\inst %12 box_make Construct reads %11,%1 consumes - state owned parents - lent %1
    \\inst %14 record_make Construct reads - consumes %12,%13 state owned parents -
    \\inst %15 box_make Construct reads - consumes %14 state owned parents -
    \\inst %18 call Call reads %1,%16,%17 consumes %15 state scalar parents - from - callee 3
    \\inst %19 call Call reads %1,%18 consumes - state owned parents - from - callee 4
    \\inst %20 box_take Take reads - consumes %19 state scalar parents -
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\inst - drop Drop reads - consumes %11 state none parents -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\term ret %20
    \\end
    \\
    },
    .{ .name = "a group joined by a call that returns a value", .reject = .j2, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime - scalar -
    \\callee 1 myl_core_fixture_1 runtime read scalar -
    \\callee 2 myl_core_fixture_2 runtime - owned -
    \\callee 3 myl_core_fixture_3 runtime take,read,read,read scalar -
    \\callee 4 myl_core_fixture_4 runtime read,read owned -
    \\callee 5 myl_core_fixture_5 runtime take scalar -
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 2
    \\inst %8 iconst Constant reads - consumes - state scalar parents - imm 3
    \\inst %10 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %13 iconst Constant reads - consumes - state scalar parents - imm 2000
    \\inst %16 func_ref Constant reads - consumes - state scalar parents -
    \\inst %17 iconst Constant reads - consumes - state scalar parents - imm 18446744073709551615
    \\inst %23 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\inst - call Call reads %23 consumes - state none parents - from - callee 1
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 2
    \\inst %3 list_new Fresh reads %2 consumes - state owned parents -
    \\inst %5 list_push Update reads - consumes %3,%4 state owned parents -
    \\inst %7 list_push Update reads - consumes %5,%6 state owned parents -
    \\inst %9 list_push Update reads - consumes %7,%8 state owned parents -
    \\inst %11 list_push Update reads - consumes %9,%10 state owned parents -
    \\inst %12 box_make Construct reads %11,%1 consumes - state owned parents - lent %1
    \\inst %14 record_make Construct reads - consumes %12,%13 state owned parents -
    \\inst %15 box_make Construct reads - consumes %14 state owned parents -
    \\inst %18 call Call reads %1,%16,%17 consumes %15 state scalar parents - from - callee 3
    \\inst %19 call Call reads %1,%18 consumes - state owned parents - from - callee 4
    \\inst %20 box_take Take reads - consumes %19 state scalar parents -
    \\inst %99 call Call reads - consumes %1 state scalar parents - from - callee 5
    \\inst - drop Drop reads - consumes %11 state none parents -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\term ret %20
    \\end
    \\
    },
    .{ .name = "a group consumed by a constructor", .reject = .j2, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime - scalar -
    \\callee 1 myl_core_fixture_1 runtime read scalar -
    \\callee 2 myl_core_fixture_2 runtime - owned -
    \\callee 3 myl_core_fixture_3 runtime take,read,read,read scalar -
    \\callee 4 myl_core_fixture_4 runtime read,read owned -
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 2
    \\inst %8 iconst Constant reads - consumes - state scalar parents - imm 3
    \\inst %10 iconst Constant reads - consumes - state scalar parents - imm 4
    \\inst %13 iconst Constant reads - consumes - state scalar parents - imm 2000
    \\inst %16 func_ref Constant reads - consumes - state scalar parents -
    \\inst %17 iconst Constant reads - consumes - state scalar parents - imm 18446744073709551615
    \\inst %23 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\inst - call Call reads %23 consumes - state none parents - from - callee 1
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 2
    \\inst %3 list_new Fresh reads %2 consumes - state owned parents -
    \\inst %5 list_push Update reads - consumes %3,%4 state owned parents -
    \\inst %7 list_push Update reads - consumes %5,%6 state owned parents -
    \\inst %9 list_push Update reads - consumes %7,%8 state owned parents -
    \\inst %11 list_push Update reads - consumes %9,%10 state owned parents -
    \\inst %12 box_make Construct reads %11,%1 consumes - state owned parents - lent %1
    \\inst %14 record_make Construct reads - consumes %12,%13 state owned parents -
    \\inst %15 box_make Construct reads - consumes %14 state owned parents -
    \\inst %18 call Call reads %1,%16,%17 consumes %15 state scalar parents - from - callee 3
    \\inst %19 call Call reads %1,%18 consumes - state owned parents - from - callee 4
    \\inst %20 box_take Take reads - consumes %19 state scalar parents -
    \\inst %99 box_make Construct reads - consumes %1 state owned parents -
    \\inst - drop Drop reads - consumes %11 state none parents -
    \\inst - call Call reads - consumes - state none parents - from - callee 0
    \\term ret %20
    \\end
    \\
    },
    .{ .name = "a lender consumed by an emptied constructor while it is lent", .reject = .j4, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime - owned -
    \\callee 1 myl_core_fixture_1 runtime take,read,read,read scalar -
    \\callee 2 myl_core_fixture_2 runtime take scalar -
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %9 func_ref Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 0
    \\inst %2 list_new Fresh reads %0 consumes - state owned parents -
    \\inst %3 box_make Construct reads %2,%1 consumes - state owned parents - lent %1
    \\inst %4 box_make Construct reads - consumes %3 state owned parents -
    \\inst %5 call Call reads %1,%9,%0 consumes %4 state scalar parents - from - callee 1
    \\inst %6 record_make Construct reads - consumes %2,%0 state emptied parents - slots f0
    \\inst %7 record_get Project reads %6 consumes - state owned parents - slot f0
    \\inst - call Call reads - consumes %1 state none parents - from - callee 2
    \\inst - drop Drop reads - consumes %7 state none parents -
    \\term ret %0
    \\end
    \\
    },
    .{ .name = "a lend whose lender is its own group", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime - owned -
    \\callee 1 myl_core_fixture_1 runtime take scalar -
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 0
    \\inst %3 box_make Construct reads %1,%1 consumes - state owned parents - lent %1
    \\inst - drop Drop reads - consumes %3 state none parents -
    \\inst - call Call reads - consumes %1 state none parents - from - callee 1
    \\term ret %0
    \\end
    \\
    },
    .{ .name = "a lent mark on an instruction that is not a box_make", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime - owned -
    \\callee 1 myl_core_fixture_1 runtime take scalar -
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads - consumes - state owned parents - from - callee 0
    \\inst %2 list_new Fresh reads %0 consumes - state owned parents -
    \\inst %3 list_len Inspect reads %2,%1 consumes - state scalar parents - lent %1
    \\inst - call Call reads - consumes %1 state none parents - from - callee 1
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %3
    \\end
    \\
    },
    .{ .name = "a group live on only some of the edges into a trap block", .reject = .j2, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_fixture_0 runtime - owned -
    \\callee 1 myl_core_fixture_1 runtime take,read scalar -
    \\callee 2 myl_core_fixture_2 runtime take scalar -
    \\callee 3 myl_core_fixture_3 runtime read scalar -
    \\inst %9 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %0 call Call reads - consumes - state owned parents - from - callee 0
    \\inst %1 list_new Fresh reads - consumes - state owned parents -
    \\inst %2 box_make Construct reads %1,%0 consumes - state owned parents - lent %0
    \\inst %3 record_make Construct reads - consumes %2 state owned parents -
    \\inst %4 call Call reads %0 consumes %3 state scalar parents - from - callee 1
    \\term branch %9 b1 b2
    \\block b1 preds b0
    \\term jump b3
    \\block b2 preds b0
    \\inst - call Call reads - consumes %0 state none parents - from - callee 2
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term jump b3
    \\block b3 preds b1,b2
    \\inst - call Call reads %9 consumes - state none parents - from - callee 3
    \\term unreachable
    \\end
    \\
    },
    .{ .name = "a block that only reaches a trap, entered by edges that disagree about the live owners", .reject = .j2, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 scalar
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\term branch %0 b1 b2
    \\block b1 preds b0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term jump b3
    \\block b2 preds b0
    \\term jump b3
    \\block b3 preds b1,b2
    \\term jump b4
    \\block b4 preds b3
    \\term unreachable
    \\end
    \\
    },
    .{ .name = "a call that names no callee", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 helper program take,read-scalar owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads %9 consumes %0 state owned parents - from -
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a line that is not a call and names a callee", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 scalar
    \\callee 0 helper program read-scalar scalar -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 0 callee 0
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "a call that names an entry the table does not have", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 helper program take,read-scalar owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads %9 consumes %0 state owned parents - from - callee 3
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a call that consumes more than its callee takes", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 helper program read,read-scalar owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads %9 consumes %0 state owned parents - from - callee 0
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a call that reads fewer values than its callee reads", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 helper program take,read-scalar,read-scalar owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads %9 consumes %0 state owned parents - from - callee 0
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "an unmanaged parameter given an owner", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 helper program take,read-scalar owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %9 consumes - state owned parents -
    \\inst %1 call Call reads %2 consumes %0 state owned parents - from - callee 0
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "an owner result where the callee returns a scalar", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 helper program take,read-scalar scalar -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads %9 consumes %0 state owned parents - from - callee 0
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a call without a value where the callee returns an owner", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 helper program take,read-scalar owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst - call Call reads %9 consumes %0 state none parents - from - callee 0
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a borrowed result where the callee returns an owner", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 helper program take,read-scalar owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %9 consumes - state owned parents -
    \\inst %1 call Call reads %9 consumes %0 state borrowed parents %2 from %2 callee 0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a record result where the callee returns a scalar", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 helper program take scalar -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads - consumes %0 state emptied parents - slots f0 from - callee 0
    \\inst %2 record_get Project reads %1 consumes - state owned parents - slot f0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a borrowed result that leaves out an argument its callee borrows from", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 view program read borrowed 0
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst - drop Drop reads - consumes %0 state none parents -
    \\inst %2 list_new Fresh reads %9 consumes - state owned parents -
    \\inst %1 call Call reads %2 consumes - state borrowed parents - from - callee 0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a callee table whose entries are not numbered in order", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 1 helper program take,read-scalar owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads %9 consumes %0 state owned parents - from - callee 0
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "an indirect entry that has a name", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 helper indirect read-scalar scalar -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %8 func_ref Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst - drop Drop reads - consumes %0 state none parents -
    \\inst %1 call_indirect Call reads %8,%9 consumes - state scalar parents - from - callee 0
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "an indirect entry used by a direct call", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 - indirect take,read-scalar owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads %9 consumes %0 state owned parents - from - callee 0
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a table entry that borrows from a parameter it does not have", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 helper program take,read-scalar owned 2
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads %9 consumes %0 state owned parents - from - callee 0
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a value that nothing defines", .reject = .j3, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %1 iconst Constant reads - consumes - state scalar parents -
    \\block b0 preds -
    \\inst %3 list_len Inspect reads %7 consumes - state scalar parents -
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "an owned constructor that lists an owner it consumes as a parent", .reject = .j1, .text =
    \\function f result owned from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\block b0 preds -
    \\inst %1 record_make Construct reads - consumes %0 state owned parents %0
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "the result record of a call with a mut argument that lists the union it consumes as a parent", .reject = .j1, .text =
    \\function withmut result owned from 0 unchecked -
    \\param 0 %0 borrowed
    \\param 1 %1 scalar
    \\callee 0 myl_core_view_slice runtime read,read-scalar,read-scalar,read-scalar borrowed 0
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %1 param Parameter reads - consumes - state scalar parents -
    \\inst %6 str_const Constant reads - consumes - state immortal parents -
    \\inst %10 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %27 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 list_len Inspect reads %0 consumes - state scalar parents -
    \\inst %3 convert Pure reads %2 consumes - state scalar parents -
    \\inst %4 cmp Pure reads %1,%3 consumes - state scalar parents - imm 4
    \\term branch %4 b1 b2
    \\block b1 preds b0
    \\inst %7 union_make Construct reads - consumes %6 state owned parents -
    \\inst %8 record_make Construct reads - consumes %7,%1 state owned parents %7
    \\term ret %8
    \\block b2 preds b0
    \\inst %11 cmp Pure reads %1,%10 consumes - state scalar parents - imm 2
    \\term branch %11 b3 b4
    \\block b3 preds b2
    \\inst %13 list_len Inspect reads %0 consumes - state scalar parents -
    \\inst %14 convert Pure reads %13 consumes - state scalar parents -
    \\term unreachable
    \\block b4 preds b2
    \\inst %16 list_len Inspect reads %0 consumes - state scalar parents -
    \\inst %17 convert Pure reads %16 consumes - state scalar parents -
    \\inst %18 cmp Pure reads %1,%17 consumes - state scalar parents - imm 4
    \\term branch %18 b5 b6
    \\block b5 preds b4
    \\inst %20 list_len Inspect reads %0 consumes - state scalar parents -
    \\inst %21 convert Pure reads %20 consumes - state scalar parents -
    \\term jump b6
    \\block b6 preds b4,b5
    \\phi %23 scalar parents - edges b4:%1,b5:%21
    \\inst %25 list_len Inspect reads %0 consumes - state scalar parents -
    \\inst %26 convert Pure reads %25 consumes - state scalar parents -
    \\inst %28 call Call reads %0,%23,%26,%27 consumes - state borrowed parents %0 from %0 callee 0
    \\inst %30 list_len Inspect reads %0 consumes - state scalar parents -
    \\inst %31 convert Pure reads %30 consumes - state scalar parents -
    \\inst %32 union_make Construct reads %28 consumes - state owned parents %28 views %28
    \\inst %33 record_make Construct reads - consumes %32,%31 state owned parents %32
    \\term ret %33
    \\end
    \\
    },
    .{ .name = "an owned constructor that lists its caller as a parent", .reject = .j1, .text =
    \\function f result owned from - unchecked -
    \\param 0 %0 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\block b0 preds -
    \\inst %1 record_make Construct reads %0 consumes - state owned parents ^0
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "a scalar constructor that lists a parent", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 record_make Construct reads - consumes %9 state scalar parents %9
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "an emptied record that lists a parent", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %7 str_const Constant reads - consumes - state immortal parents -
    \\block b0 preds -
    \\inst %5 list_new Fresh reads %6 consumes - state owned parents -
    \\inst %1 record_make Construct reads - consumes %5,%7 state emptied parents %5 slots f0,f1
    \\inst %2 record_get Project reads %1 consumes - state owned parents - slot f0
    \\inst %3 record_get Project reads %1 consumes - state owned parents - slot f1
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\inst - drop Drop reads - consumes %3 state none parents -
    \\term ret %6
    \\end
    \\
    },
    .{ .name = "a borrowed constructor whose parent is not an operand it reads", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\param 1 %1 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %1 param Parameter reads - consumes - state borrowed parents ^1
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 record_make Construct reads %0 consumes - state borrowed parents %1
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "an owned call result that lists an owner it consumes as a parent", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 helper program take owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads - consumes %0 state owned parents %0 from - callee 0
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a scalar call result that lists a parent", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 helper program read-scalar scalar -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads %9 consumes - state scalar parents %9 from - callee 0
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "an emptied call result that lists a parent", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 helper program take owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads - consumes %0 state emptied parents %9 slots f0 from - callee 0
    \\inst %2 record_get Project reads %1 consumes - state owned parents - slot f0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "an owned call result that lists its caller as a parent", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\param 1 %1 borrowed
    \\callee 0 helper program take,read owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %1 param Parameter reads - consumes - state borrowed parents ^1
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 call Call reads %1 consumes %0 state owned parents ^1 from - callee 0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a borrowed call result whose from list names a value the call does not read", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\param 1 %1 borrowed
    \\callee 0 view program read borrowed 0
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %1 param Parameter reads - consumes - state borrowed parents ^1
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 call Call reads %0 consumes - state borrowed parents %0,%1 from %0,%1 callee 0
    \\inst - drop Drop reads - consumes %0 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a borrowed projection that names a scalar projection of its call as a parent", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 helper program take owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads - consumes %0 state emptied parents - slots f0 from - callee 0
    \\inst %2 record_get Project reads %1 consumes - state scalar parents -
    \\inst %3 record_get Project reads %1 consumes - state owned parents - slot f0
    \\inst %4 record_get Project reads %3 consumes - state borrowed parents %3,%2 slot f0
    \\inst %5 list_len Inspect reads %4 consumes - state scalar parents -
    \\inst - drop Drop reads - consumes %3 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a borrowed projection that names a later borrowed read of its container as a parent", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %8 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %2 list_get Project reads %0,%8 consumes - state borrowed parents %0,%3 slot e#0
    \\inst %3 list_get Project reads %0,%9 consumes - state borrowed parents %0 slot e#1
    \\inst %4 list_len Inspect reads %2 consumes - state scalar parents -
    \\inst %5 list_len Inspect reads %3 consumes - state scalar parents -
    \\term ret %4
    \\end
    \\
    },
    .{ .name = "a scalar phi that lists a parent", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 scalar
    \\param 1 %1 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %1 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 cmp Pure reads %0,%9 consumes - state scalar parents - imm 0
    \\term branch %2 b1 b2
    \\block b1 preds b0
    \\term jump b3
    \\block b2 preds b0
    \\term jump b3
    \\block b3 preds b1,b2
    \\phi %3 scalar parents %1 edges b1:%0,b2:%9
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %3
    \\end
    \\
    },
    .{ .name = "an owned phi that lists a parent", .reject = .j1, .text =
    \\function f result owned from - unchecked -
    \\param 0 %0 scalar
    \\param 1 %1 owned
    \\param 2 %2 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %1 param Parameter reads - consumes - state owned parents -
    \\inst %2 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %3 cmp Pure reads %0,%9 consumes - state scalar parents - imm 0
    \\term branch %3 b1 b2
    \\block b1 preds b0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term jump b3
    \\block b2 preds b0
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term jump b3
    \\block b3 preds b1,b2
    \\phi %4 owned parents %0 edges b1:%1,b2:%2
    \\term ret %4
    \\end
    \\
    },
    .{ .name = "a constant that is not an undef and has state none in the pseudo-block", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %8 iconst Constant reads - consumes - state none parents - imm 0
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a constant that is not an undef and has state none in a block", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 str_const Constant reads - consumes - state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a borrowed call whose contract names a parameter the callee takes", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\callee 0 view program take-scalar,read borrowed 0
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 call Call reads %0 consumes %9 state borrowed parents %0 from %0 callee 0
    \\inst - drop Drop reads - consumes %0 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a borrowed call whose contract names a stack argument that is not a parent", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 view program read borrowed 0
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 list_new Fresh reads %9 consumes - state stack parents -
    \\inst %2 call Call reads %1 consumes - state borrowed parents - from - callee 0
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "an emptied record consumed whole in a block no edge reaches", .reject = .j8, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %7 str_const Constant reads - consumes - state immortal parents -
    \\block b0 preds -
    \\term ret %6
    \\block b1 preds -
    \\inst %5 list_new Fresh reads %6 consumes - state owned parents -
    \\inst %1 record_make Construct reads - consumes %5,%7 state emptied parents - slots f0,f1
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %6
    \\end
    \\
    },
    .{ .name = "an emptied record whose slots nobody takes in a block no edge reaches", .reject = .j8, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %7 str_const Constant reads - consumes - state immortal parents -
    \\block b0 preds -
    \\term ret %6
    \\block b1 preds -
    \\inst %5 list_new Fresh reads %6 consumes - state owned parents -
    \\inst %1 record_make Construct reads - consumes %5,%7 state emptied parents - slots f0,f1
    \\term ret %6
    \\end
    \\
    },
    .{ .name = "match own of an own parameter: the union read after its payload is taken", .reject = .j3, .text =
    \\function drain result owned from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %10 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 union_tag Inspect reads %0 consumes - state scalar parents -
    \\inst %3 cmp Pure reads %1,%2 consumes - state scalar parents - imm 0
    \\term branch %3 b2 b3
    \\block b2 preds b0
    \\inst %5 union_take Take reads - consumes %0 state emptied parents - slots f0
    \\inst %6 record_get Project reads %5 consumes - state owned parents - slot f0
    \\inst %7 record_take Take reads - consumes %6 state owned parents - noloans
    \\inst %8 union_tag Inspect reads %0 consumes - state scalar parents -
    \\term ret %7
    \\block b3 preds b0
    \\inst - drop Drop reads - consumes %0 state none parents -
    \\term jump b4
    \\block b4 preds b3
    \\inst %11 list_new Fresh reads %10 consumes - state owned parents -
    \\term ret %11
    \\end
    \\
    },
    .{ .name = "match own of an own parameter: an arm that neither takes nor drops the union", .reject = .j2, .text =
    \\function drain result owned from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %2 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %10 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 union_tag Inspect reads %0 consumes - state scalar parents -
    \\inst %3 cmp Pure reads %1,%2 consumes - state scalar parents - imm 0
    \\term branch %3 b2 b3
    \\block b2 preds b0
    \\inst %5 union_take Take reads - consumes %0 state emptied parents - slots f0
    \\inst %6 record_get Project reads %5 consumes - state owned parents - slot f0
    \\inst %7 record_take Take reads - consumes %6 state owned parents - noloans
    \\term ret %7
    \\block b3 preds b0
    \\term jump b4
    \\block b4 preds b3
    \\inst %11 list_new Fresh reads %10 consumes - state owned parents -
    \\term ret %11
    \\end
    \\
    },
    .{ .name = "a mut local holding a borrow carried around a loop: the phi takes a view of an owner dropped in the iteration", .reject = .j4, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %4 list_view_of View reads %1 consumes - state borrowed parents %1
    \\term jump b1
    \\block b1 preds b0,b3
    \\phi %10 scalar parents - edges b0:%6,b3:%32
    \\phi %19 borrowed parents %4,%27 edges b0:%4,b3:%27
    \\inst %12 cmp Pure reads %10,%9 consumes - state scalar parents - imm 2
    \\term branch %12 b2 b4
    \\block b2 preds b1
    \\inst %15 list_new Fresh reads %9 consumes - state owned parents -
    \\inst %27 list_view_of View reads %15 consumes - state borrowed parents %15
    \\inst - drop Drop reads - consumes %15 state none parents -
    \\term jump b3
    \\block b3 preds b2
    \\inst %32 add Pure reads %10,%9 consumes - state scalar parents -
    \\term jump b1
    \\block b4 preds b1
    \\inst %37 list_len Inspect reads %19 consumes - state scalar parents -
    \\term ret %37
    \\end
    \\
    },
    .{ .name = "a default of unwrap_or returned under from: the borrowed phi takes a fresh owner dropped before the join", .reject = .j4, .text =
    \\function f result borrowed from 0 unchecked -
    \\param 0 %0 borrowed
    \\callee 0 myl_core_borrow_choice_v1_optional_default_f82d761364b47229aa6223c6bf20357e_47457acde1e6d1d8766a9b33e9ed4ead marker read,read,read owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %13 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %3 union_tag Inspect reads %1 consumes - state scalar parents -
    \\inst %5 cmp Pure reads %3,%4 consumes - state scalar parents - imm 0
    \\term branch %5 b1 b2
    \\block b1 preds b0
    \\inst %7 union_payload Project reads %1 consumes - state borrowed parents %1
    \\term jump b3
    \\block b2 preds b0
    \\inst %2 list_new Fresh reads %4 consumes - state owned parents -
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term jump b3
    \\block b3 preds b1,b2
    \\phi %10 borrowed parents %1,%2 edges b1:%7,b2:%2
    \\inst %11 call Call reads %10,%1,%2 consumes - state borrowed parents %10 from %10 callee 0
    \\inst %12 list_len Inspect reads %11 consumes - state scalar parents -
    \\inst %14 str_view_of View reads %11,%13,%12 consumes - state borrowed parents %11
    \\term ret %14
    \\end
    \\
    },
    .{ .name = "a borrowed record (1A) of a lent owner: the owner is dropped before the record's last use", .reject = .j4, .text =
    \\function f result scalar from - unchecked -
    \\callee 0 myl_core_bytes_concat runtime read,read owned -
    \\callee 1 size program read scalar -
    \\block b- preds -
    \\inst %0 str_const Constant reads - consumes - state immortal parents -
    \\inst %1 str_const Constant reads - consumes - state immortal parents -
    \\inst %5 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 call Call reads %0,%1 consumes - state owned parents - from - callee 0
    \\inst %3 borrow Borrow reads %2 consumes - state borrowed parents %2
    \\inst %4 borrow Borrow reads %3 consumes - state borrowed parents %3
    \\inst %6 record_make Construct reads %4 consumes %5 state borrowed parents %4
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\inst %7 borrow Borrow reads %6 consumes - state borrowed parents %6
    \\inst %8 call Call reads %7 consumes - state scalar parents - from - callee 1
    \\term ret %8
    \\end
    \\
    },
    .{ .name = "an owned record built of a borrowed field: the record consumes the borrow and drops it", .reject = .j5, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\callee 0 size program read scalar -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 7
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %5 record_make Construct reads - consumes %1,%4 state owned parents -
    \\inst %8 call Call reads %5 consumes - state scalar parents - from - callee 0
    \\inst - drop Drop reads - consumes %5 state none parents -
    \\term ret %8
    \\end
    \\
    },
    .{ .name = "a dictionary store with a borrowed key: the insertion consumes the borrowed key itself", .reject = .j5, .text =
    \\function put result owned from - unchecked -
    \\param 0 %0 owned
    \\param 1 %1 borrowed
    \\param 2 %2 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %1 param Parameter reads - consumes - state borrowed parents ^1
    \\inst %2 param Parameter reads - consumes - state borrowed parents ^2
    \\inst %3 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %5 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %4 dict_find Inspect reads %0,%1 consumes - state scalar parents -
    \\inst %6 cmp Pure reads %4,%5 consumes - state scalar parents - imm 5
    \\term branch %6 b1 b2
    \\block b1 preds b0
    \\inst %8 dict_set_value Update reads %4 consumes %0,%3 state owned parents -
    \\term jump b3
    \\block b2 preds b0
    \\inst %10 dict_insert Update reads %4 consumes %0,%1,%3 state owned parents -
    \\term jump b3
    \\block b3 preds b1,b2
    \\phi %12 owned parents - edges b1:%8,b2:%10
    \\term ret %12
    \\end
    \\
    },
    .{ .name = "a dictionary store with a borrowed key: the key is copied before the probe and abandoned on the hit edge", .reject = .j2, .text =
    \\function put result owned from - unchecked -
    \\param 0 %0 owned
    \\param 1 %1 borrowed
    \\param 2 %2 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %1 param Parameter reads - consumes - state borrowed parents ^1
    \\inst %2 param Parameter reads - consumes - state borrowed parents ^2
    \\inst %3 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %5 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %15 str_from_view Copy reads %1 consumes - state owned parents -
    \\inst %4 dict_find Inspect reads %0,%1 consumes - state scalar parents -
    \\inst %6 cmp Pure reads %4,%5 consumes - state scalar parents - imm 5
    \\term branch %6 b1 b2
    \\block b1 preds b0
    \\inst %8 dict_set_value Update reads %4 consumes %0,%3 state owned parents -
    \\term jump b3
    \\block b2 preds b0
    \\inst %10 dict_insert Update reads %4 consumes %0,%15,%3 state owned parents -
    \\term jump b3
    \\block b3 preds b1,b2
    \\phi %12 owned parents - edges b1:%8,b2:%10
    \\term ret %12
    \\end
    \\
    },
    .{ .name = "an own record parameter only read: the parameter stated owned, its line emptied", .reject = .j1, .text =
    \\function count result scalar from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state emptied parents - slots f0,f1
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state owned parents - slot f0
    \\inst %2 list_len Inspect reads %1 consumes - state scalar parents -
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\inst %3 convert Pure reads %2 consumes - state scalar parents -
    \\inst %4 record_get Project reads %0 consumes - state owned parents - slot f1
    \\inst %5 str_len Inspect reads %4 consumes - state scalar parents -
    \\inst - drop Drop reads - consumes %4 state none parents -
    \\inst %6 convert Pure reads %5 consumes - state scalar parents -
    \\inst %7 add Pure reads %3,%6 consumes - state scalar parents -
    \\term ret %7
    \\end
    \\
    },
    .{ .name = "an own record parameter only read: the record dropped before its second field is measured", .reject = .j4, .text =
    \\function count result scalar from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %2 list_len Inspect reads %1 consumes - state scalar parents -
    \\inst %3 convert Pure reads %2 consumes - state scalar parents -
    \\inst %4 record_get Project reads %0 consumes - state borrowed parents %0 slot f1
    \\inst - drop Drop reads - consumes %0 state none parents -
    \\inst %5 str_len Inspect reads %4 consumes - state scalar parents -
    \\inst %6 convert Pure reads %5 consumes - state scalar parents -
    \\inst %7 add Pure reads %3,%6 consumes - state scalar parents -
    \\term ret %7
    \\end
    \\
    },
    .{ .name = "an own record parameter only read: the record never dropped", .reject = .j2, .text =
    \\function count result scalar from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %2 list_len Inspect reads %1 consumes - state scalar parents -
    \\inst %3 convert Pure reads %2 consumes - state scalar parents -
    \\term ret %3
    \\end
    \\
    },
    .{ .name = "an owned Result that lends its argument dropped after the argument on the Err edge (O3, main's lowering)", .reject = .j4, .text =
    \\function main result scalar from - unchecked -
    \\callee 0 at program read owned 0
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %2 str_const Constant reads - consumes - state immortal parents -
    \\inst %5 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %18 iconst Constant reads - consumes - state scalar parents - imm 2
    \\block b0 preds -
    \\inst %1 list_new Fresh reads %0 consumes - state owned parents -
    \\inst %3 record_make Construct reads - consumes %2 state owned parents -
    \\inst %4 list_push Update reads - consumes %1,%3 state owned parents -
    \\inst %6 record_make Construct reads - consumes %4,%5 state owned parents -
    \\inst %7 call Call reads %6 consumes - state owned parents %6 from %6 callee 0
    \\inst %8 union_tag Inspect reads %7 consumes - state scalar parents -
    \\inst %10 cmp Pure reads %8,%9 consumes - state scalar parents - imm 0
    \\term branch %10 b2 b3
    \\block b2 preds b0
    \\inst %12 union_payload Project reads %7 consumes - state borrowed parents %6
    \\inst - drop Drop reads - consumes %7 state none parents -
    \\inst %13 record_get Project reads %12 consumes - state borrowed parents %12 slot f0
    \\inst %14 list_len Inspect reads %13 consumes - state scalar parents -
    \\inst - drop Drop reads - consumes %6 state none parents -
    \\inst %15 convert Pure reads %14 consumes - state scalar parents -
    \\term ret %15
    \\block b3 preds b0
    \\inst - drop Drop reads - consumes %6 state none parents -
    \\inst - drop Drop reads - consumes %7 state none parents -
    \\term jump b4
    \\block b4 preds b3
    \\term ret %18
    \\end
    \\
    },
    .{ .name = "a borrowed Ok payload two projections below a call names a final value its prefix does not lend (O3, main's lowering)", .reject = .j1, .text =
    \\function main result scalar from - unchecked -
    \\callee 0 next program take owned -
    \\block b- preds -
    \\inst %0 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %2 str_const Constant reads - consumes - state immortal parents -
    \\inst %5 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %11 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %16 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %26 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %29 iconst Constant reads - consumes - state scalar parents - imm 2
    \\block b0 preds -
    \\inst %1 list_new Fresh reads %0 consumes - state owned parents -
    \\inst %3 record_make Construct reads - consumes %2 state owned parents -
    \\inst %4 list_push Update reads - consumes %1,%3 state owned parents -
    \\inst %6 record_make Construct reads - consumes %4,%5 state owned parents -
    \\inst %7 call Call reads - consumes %6 state emptied parents - slots f1 from - callee 0
    \\inst %8 record_get Project reads %7 consumes - state owned parents - slot f1
    \\inst %9 record_get Project reads %7 consumes - state borrowed parents %7
    \\inst %10 union_tag Inspect reads %9 consumes - state scalar parents -
    \\inst %12 cmp Pure reads %10,%11 consumes - state scalar parents - imm 0
    \\term branch %12 b2 b3
    \\block b2 preds b0
    \\inst %14 union_payload Project reads %9 consumes - state borrowed parents %9
    \\inst %15 union_tag Inspect reads %14 consumes - state scalar parents -
    \\inst %17 cmp Pure reads %15,%16 consumes - state scalar parents - imm 0
    \\term branch %17 b5 b6
    \\block b3 preds b0
    \\inst - drop Drop reads - consumes %8 state none parents -
    \\term jump b8
    \\block b4 preds b7
    \\term ret %26
    \\block b5 preds b2
    \\inst %19 union_payload Project reads %14 consumes - state borrowed parents %8
    \\inst %20 record_get Project reads %19 consumes - state borrowed parents %19 slot f0
    \\inst %21 list_len Inspect reads %20 consumes - state scalar parents -
    \\inst - drop Drop reads - consumes %8 state none parents -
    \\inst %22 convert Pure reads %21 consumes - state scalar parents -
    \\term ret %22
    \\block b6 preds b2
    \\inst - drop Drop reads - consumes %8 state none parents -
    \\term jump b7
    \\block b7 preds b6
    \\term jump b4
    \\block b8 preds b3
    \\term ret %29
    \\end
    \\
    },
    .{ .name = "a narrowed option dropped before its payload view is read (O3, zero-copy 3a)", .reject = .j4, .text =
    \\function f204 result scalar from - unchecked -
    \\param 0 %0 scalar
    \\callee 0 lookup program read-scalar owned -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %3 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %6 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %13 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %17 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %25 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 call Call reads %0 consumes - state owned parents - from - callee 0
    \\inst %2 union_tag Inspect reads %1 consumes - state scalar parents -
    \\inst %4 cmp Pure reads %2,%3 consumes - state scalar parents - imm 0
    \\term branch %4 b2 b3
    \\block b1 preds b2,b4
    \\phi %11 scalar parents - edges b2:%6,b4:%9
    \\term branch %11 b5 b6
    \\block b2 preds b0
    \\term jump b1
    \\block b3 preds b0
    \\term jump b4
    \\block b4 preds b3
    \\term jump b1
    \\block b5 preds b1
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %13
    \\block b6 preds b1
    \\inst %16 union_tag Inspect reads %1 consumes - state scalar parents -
    \\inst %18 cmp Pure reads %16,%17 consumes - state scalar parents - imm 0
    \\term branch %18 b8 b9
    \\block b7 preds b8
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\inst %24 list_len Inspect reads %20 consumes - state scalar parents -
    \\inst %26 str_view_of View reads %20,%25,%24 consumes - state borrowed parents %20
    \\inst %27 list_len Inspect reads %26 consumes - state scalar parents -
    \\inst %28 convert Pure reads %27 consumes - state scalar parents -
    \\term ret %28
    \\block b8 preds b6
    \\inst %20 union_payload Project reads %1 consumes - state borrowed parents %1
    \\term jump b7
    \\block b9 preds b6
    \\abandon b6 %1
    \\term jump b10
    \\block b10 preds b9
    \\term unreachable
    \\end
    \\
    },
    .{ .name = "a frame box (O4) stated as an owner", .reject = .j1, .text =
    \\function child result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\callee 0 depth program read scalar -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\block b0 preds -
    \\inst %4 box_frame View reads %0 consumes - state owned parents -
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %2 borrow Borrow reads %1 consumes - state borrowed parents %1
    \\inst %3 borrow Borrow reads %2 consumes - state borrowed parents %2
    \\inst %5 union_make Construct reads %4 consumes - state borrowed parents %4
    \\inst %6 borrow Borrow reads %5 consumes - state borrowed parents %5
    \\inst %7 borrow Borrow reads %6 consumes - state borrowed parents %6
    \\inst %8 record_make Construct reads %3,%7 consumes - state borrowed parents %3,%7
    \\inst %9 borrow Borrow reads %8 consumes - state borrowed parents %8
    \\inst %10 call Call reads %9 consumes - state scalar parents - from - callee 0
    \\term ret %10
    \\end
    \\
    },
    .{ .name = "a frame box (O4) whose parent is not the parameter it holds", .reject = .j1, .text =
    \\function child result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\callee 0 depth program read scalar -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\block b0 preds -
    \\inst %4 box_frame View reads %0 consumes - state borrowed parents %1
    \\inst %1 record_get Project reads %0 consumes - state borrowed parents %0 slot f0
    \\inst %2 borrow Borrow reads %1 consumes - state borrowed parents %1
    \\inst %3 borrow Borrow reads %2 consumes - state borrowed parents %2
    \\inst %5 union_make Construct reads %4 consumes - state borrowed parents %4
    \\inst %6 borrow Borrow reads %5 consumes - state borrowed parents %5
    \\inst %7 borrow Borrow reads %6 consumes - state borrowed parents %6
    \\inst %8 record_make Construct reads %3,%7 consumes - state borrowed parents %3,%7
    \\inst %9 borrow Borrow reads %8 consumes - state borrowed parents %8
    \\inst %10 call Call reads %9 consumes - state scalar parents - from - callee 0
    \\term ret %10
    \\end
    \\
    },
    // Lane VAL, the construct-read rule (J6). The plan lane FX6 found (main 911c280fd, `dicts.items` over a dictionary of a
    // borrowed type): the item record is `emptied`, reads the dictionary's key as a borrow of %44, which it does not consume,
    // and `%34` takes the key out as an owner that is dropped each iteration. The dictionary frees the keys again.
    .{ .name = "the FX6 plan: an emptied item record that reads a dictionary's key it does not own (construct-read)", .reject = .j6, .text =
    \\function m::main result scalar from - unchecked -
    \\param 0 %0 scalar
    \\callee 0 myl_core_str_from_i64 runtime read-scalar owned -
    \\callee 1 myl_core_dict_ordinal runtime read,read-scalar scalar -
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %3 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %4 iconst Constant reads - consumes - state scalar parents - imm 7
    \\inst %7 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %17 iconst Constant reads - consumes - state scalar parents - imm 0
    \\inst %37 iconst Constant reads - consumes - state scalar parents - imm 1
    \\inst %41 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 dict_new Fresh reads %1 consumes - state owned parents -
    \\inst %5 call Call reads %4 consumes - state owned parents - from - callee 0
    \\inst %6 dict_find Inspect reads %2,%5 consumes - state scalar parents -
    \\inst %8 cmp Pure reads %6,%7 consumes - state scalar parents - imm 5
    \\term branch %8 b1 b2
    \\block b1 preds b0
    \\inst - drop Drop reads - consumes %5 state none parents -
    \\inst %10 dict_set_value Update reads %6 consumes %2,%3 state owned parents -
    \\term jump b3
    \\block b2 preds b0
    \\inst %12 dict_insert Update reads %6 consumes %2,%5,%3 state owned parents -
    \\term jump b3
    \\block b3 preds b1,b2
    \\phi %14 owned parents - edges b1:%10,b2:%12
    \\inst %15 record_make Construct reads - consumes %14 state emptied parents - slots f0
    \\inst %43 record_get Project reads %15 consumes - state owned parents - slot f0
    \\inst %44 borrow Borrow reads %43 consumes - state borrowed parents %43
    \\inst %18 dict_len Inspect reads %44 consumes - state scalar parents -
    \\inst %19 convert Pure reads %18 consumes - state scalar parents -
    \\term jump b4
    \\block b4 preds b3,b6
    \\phi %21 scalar parents - edges b3:%17,b6:%38
    \\inst %23 cmp Pure reads %21,%19 consumes - state scalar parents - imm 2
    \\term branch %23 b5 b7
    \\block b5 preds b4
    \\inst %26 borrow Borrow reads %44 consumes - state borrowed parents %44
    \\inst %27 call Call reads %26,%21 consumes - state scalar parents - from - callee 1
    \\inst %28 dict_entry_key Project reads %44,%27 consumes - state borrowed parents %44 slot k%27
    \\inst %29 borrow Borrow reads %44 consumes - state borrowed parents %44
    \\inst %30 call Call reads %29,%21 consumes - state scalar parents - from - callee 1
    \\inst %31 dict_entry_value Project reads %44,%30 consumes - state scalar parents -
    \\inst %32 record_make Construct reads %28 consumes %31 state emptied parents - slots f0
    \\inst %34 record_get Project reads %32 consumes - state owned parents - slot f0
    \\inst - print Output reads %0,%34 consumes - state none parents -
    \\inst - drop Drop reads - consumes %34 state none parents -
    \\term jump b6
    \\block b6 preds b5
    \\inst %38 add Pure reads %21,%37 consumes - state scalar parents -
    \\term jump b4
    \\block b7 preds b4
    \\inst - drop Drop reads - consumes %43 state none parents -
    \\term ret %41
    \\end
    \\
    },
    .{ .name = "an emptied record that reads a borrowed parameter, rooted in the caller (construct-read)", .reject = .j6, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 record_make Construct reads %0 consumes %9 state emptied parents - slots f0
    \\inst %2 record_get Project reads %1 consumes - state owned parents - slot f0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "an owned record that reads a view of an owner it neither takes nor lists as a loan (construct-read)", .reject = .j6, .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 list_new Fresh reads %9 consumes - state owned parents -
    \\inst %2 list_view_of View reads %1 consumes - state borrowed parents %1
    \\inst %3 record_make Construct reads %2 consumes - state owned parents -
    \\inst - drop Drop reads - consumes %3 state none parents -
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %9
    \\end
    \\
    },
    // Phase 2 of lane VAL: the same owned record listing a borrowed text as a loan without marking it a view. The text is
    // managed, so the record's destruction would destroy the caller's text.
    .{ .name = "an owned record that lists a borrowed text as a loan it does not mark a view (construct-read)", .reject = .j6, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 record_make Construct reads %0 consumes - state owned parents %0
    \\inst - drop Drop reads - consumes %1 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a constructor that lists as a view a value it does not read (views)", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 list_view_of View reads %0 consumes - state borrowed parents %0
    \\inst %2 union_make Construct reads %1 consumes - state owned parents %1 views %0
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "an instruction that is not a constructor and lists views (views)", .reject = .j1, .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 borrowed
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state borrowed parents ^0
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %1 list_view_of View reads %0 consumes - state borrowed parents %0 views %0
    \\term ret %9
    \\end
    \\
    },
};

/// A description of the first fixture whose verdict is not the one it states; empty when every fixture is judged right.
/// Texts the reader refuses: a certificate defines each value once, so a text that defines one twice is malformed input (an
/// error line for the file in both checkers), not a function with a verdict.
const malformed = [_]Fixture{
    .{ .name = "a take whose test operand is defined again before the second branch", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 18446744073709551615
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 dict_find Inspect reads %0,%9 consumes - state scalar parents -
    \\inst %4 cmp Pure reads %2,%1 consumes - state scalar parents - imm 1
    \\term branch %4 b1 b2
    \\block b1 preds b0
    \\inst %5 dict_entry_value Project reads %0,%2 consumes - state owned parents - slot v%2
    \\inst - drop Drop reads - consumes %5 state none parents -
    \\term jump b3
    \\block b2 preds b0
    \\term jump b3
    \\block b3 preds b1,b2
    \\inst %2 dict_find Inspect reads %0,%9 consumes - state scalar parents -
    \\inst %6 cmp Pure reads %2,%1 consumes - state scalar parents - imm 1
    \\term branch %6 b4 b5
    \\block b4 preds b3
    \\inst %7 dict_remove Update reads %2 consumes %0 state owned parents - slot v%2 released - taken value
    \\term jump b6
    \\block b5 preds b3
    \\term jump b6
    \\block b6 preds b4,b5
    \\phi %8 owned parents - edges b4:%7,b5:%0
    \\inst - drop Drop reads - consumes %8 state none parents -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a line that names no value but gives it a state", .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst - call Call reads - consumes - state scalar parents - from - callee 0
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a param line after a block", .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\param 0 %0 scalar
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "parameters that are not numbered from zero in order", .text =
    \\function f result scalar from - unchecked -
    \\param 1 %0 scalar
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\block b0 preds -
    \\term ret %0
    \\end
    \\
    },
    .{ .name = "a callee line after a block", .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\callee 0 helper program read-scalar scalar -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a pseudo-block that comes after b0", .text =
    \\function f result scalar from - unchecked -
    \\block b0 preds -
    \\term unreachable
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\end
    \\
    },
    .{ .name = "blocks that are not numbered in increasing order", .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\term jump b2
    \\block b2 preds b0
    \\term jump b1
    \\block b1 preds b2
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a block with no term line", .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\block b1 preds -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a block with two term lines", .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\term ret %9
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "a phi line after an inst line", .text =
    \\function f result scalar from - unchecked -
    \\param 0 %0 scalar
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state scalar parents -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\inst %2 cmp Pure reads %0,%9 consumes - state scalar parents - imm 0
    \\term branch %2 b1 b2
    \\block b1 preds b0
    \\term jump b3
    \\block b2 preds b0
    \\term jump b3
    \\block b3 preds b1,b2
    \\inst %5 add Pure reads %0,%9 consumes - state scalar parents -
    \\phi %3 scalar parents - edges b1:%0,b2:%9
    \\term ret %3
    \\end
    \\
    },
    .{ .name = "a phi line in the pseudo-block", .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\phi %3 scalar parents - edges b1:%0
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\term ret %9
    \\end
    \\
    },
    .{ .name = "an end line with a stray token", .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\term ret %9
    \\end now
    \\
    },
    .{ .name = "an edge to a block the function does not define", .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\term jump b7
    \\end
    \\
    },
    .{ .name = "a value number with a sign", .text =
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\term ret %+9
    \\end
    \\
    },
    .{ .name = "a slot given twice", .text =
    \\function f result owned from - unchecked -
    \\param 0 %0 owned
    \\block b- preds -
    \\inst %0 param Parameter reads - consumes - state owned parents -
    \\block b0 preds -
    \\inst %1 record_get Project reads %0 consumes - state owned parents - slot f0 slot f1
    \\term ret %1
    \\end
    \\
    },
    .{ .name = "a pseudo-block named with predecessors", .text =
    \\function f result scalar from - unchecked -
    \\block b- preds b0
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\term ret %9
    \\end
    \\
    },
};

fn firstWrong(a: std.mem.Allocator, fixtures: []const Fixture) ![]const u8 {
    for (fixtures) |fixture| {
        var problem: parse.Problem = .{};
        const functions = parse.parse(a, fixture.text, &problem) catch return std.fmt.allocPrint(a, "{s}: the text does not parse (line {d}: {s})", .{ fixture.name, problem.line, problem.reason });
        const verdict = try validate.validate(a, functions[0]);
        const wanted = if (fixture.reject) |check| check.label() else "accepted";
        switch (verdict) {
            .accepted, .unchecked => if (fixture.reject != null) return std.fmt.allocPrint(a, "{s}: accepted, wanted {s}", .{ fixture.name, wanted }),
            .rejected => |failure| if (fixture.reject == null or failure.check != fixture.reject.?) {
                return std.fmt.allocPrint(a, "{s}: rejected with {s} ({s}), wanted {s}", .{ fixture.name, failure.check.label(), failure.detail, wanted });
            },
        }
    }
    return "";
}

test "the validator accepts the functions that follow the rules" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("", try firstWrong(arena.allocator(), &accepted));
}

test "the validator rejects each function with the judgment that names its fault" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("", try firstWrong(arena.allocator(), &rejected));
}

/// The fixture of `list` called `name`.
fn named(list: []const Fixture, name: []const u8) Fixture {
    for (list) |fixture| if (std.mem.eql(u8, fixture.name, name)) return fixture;
    unreachable;
}

/// The verdict on the one function of `text` when the construct-read rule runs in `mode`, adding what it counts to `counted`.
fn verdictIn(a: std.mem.Allocator, text: []const u8, mode: validate.Mode, counted: *u32) !validate.Verdict {
    var problem: parse.Problem = .{};
    const functions = try parse.parse(a, text, &problem);
    return validate.validateWith(a, functions[0], .{ .construct_read = mode, .counted = counted });
}

const fx6_plan = "the FX6 plan: an emptied item record that reads a dictionary's key it does not own (construct-read)";
const caller_read = "an emptied record that reads a borrowed parameter, rooted in the caller (construct-read)";
const entry_19 = "an owned record that takes an owner and lists a view of it as a loan (entry 19, construct-read)";
const entry_28 = "an emptied record that takes an owner and reads a view of one of its slots (entry 28, construct-read)";
const unlisted_read = "an owned record that reads a view of an owner it neither takes nor lists as a loan (construct-read)";

test "the null owner (an undef of a managed type) may fill a join and be dropped, but an operation that reads it is refused (FX12)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var counted: u32 = 0;
    const read = try verdictIn(a, named(&rejected, "an undef of a managed type (the null owner) read by an operation").text, .refuse, &counted);
    try std.testing.expectEqual(validate.Check.j3, read.rejected.check);
    try std.testing.expectEqual(@as(?u32, 0), read.rejected.index);
    try std.testing.expect(std.mem.startsWith(u8, read.rejected.detail, "operand %2 is an undef of a managed type (the null owner)"));
    const joined = try verdictIn(a, named(&accepted, "an undef of a managed type (the null owner) on one edge of an owned phi").text, .refuse, &counted);
    try std.testing.expectEqual(validate.Verdict.accepted, joined);
}

test "the construct-read rule refuses the FX6 plan at its item record, and names the borrow it reads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var counted: u32 = 0;
    const verdict = try verdictIn(a, named(&rejected, fx6_plan).text, .refuse, &counted);
    try std.testing.expectEqual(validate.Check.j6, verdict.rejected.check);
    try std.testing.expectEqual(@as(?u32, 5), verdict.rejected.block);
    try std.testing.expectEqual(@as(?u32, 6), verdict.rejected.index);
    try std.testing.expect(std.mem.startsWith(u8, verdict.rejected.detail, "construct-read: the emptied constructor reads borrowed %28, which lives in an owner it does not consume"));
    try std.testing.expectEqual(@as(u32, 0), counted);
    const caller = try verdictIn(a, named(&rejected, caller_read).text, .refuse, &counted);
    try std.testing.expect(std.mem.indexOf(u8, caller.rejected.detail, "which lives in the caller") != null);
}

// Phase 1 of lane VAL: a build's validator (`build_mode`, as `passes.validateOwnership` calls it) counts the constructors the
// rule refuses and accepts the function, once per constructor however many forward passes ran; the gate's refuses them.
test "a build counts a constructor that reads a borrow it neither owns nor lends, and the gate's validator refuses it" {
    try std.testing.expectEqual(validate.Mode.count, validate.build_mode);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var counted: u32 = 0;
    try std.testing.expectEqual(validate.Verdict.accepted, try verdictIn(a, named(&rejected, fx6_plan).text, validate.build_mode, &counted));
    try std.testing.expectEqual(@as(u32, 1), counted);
    try std.testing.expectEqual(validate.Verdict.accepted, try verdictIn(a, named(&rejected, caller_read).text, .count, &counted));
    try std.testing.expectEqual(validate.Verdict.accepted, try verdictIn(a, named(&rejected, unlisted_read).text, .count, &counted));
    try std.testing.expectEqual(@as(u32, 3), counted);
    // The rule's accepted neighbours count nothing.
    try std.testing.expectEqual(validate.Verdict.accepted, try verdictIn(a, named(&accepted, entry_19).text, .count, &counted));
    try std.testing.expectEqual(validate.Verdict.accepted, try verdictIn(a, named(&accepted, entry_28).text, .count, &counted));
    try std.testing.expectEqual(@as(u32, 3), counted);
    var report: std.ArrayList(u8) = .empty;
    try @import("pipeline.zig").reportConstructReads(a, counted, &report);
    try std.testing.expectEqualStrings("selka: construct-reads: 3 constructors read a borrow they neither own nor lend (counted in builds, refused by the gate)\n", report.items);
    const gate = try verdictIn(a, named(&rejected, unlisted_read).text, .refuse, &counted);
    try std.testing.expectEqual(validate.Check.j6, gate.rejected.check);
}

test "loans are judged by the roots they live in: a forward take, a holder and a taken slot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const judged = [_]Fixture{
        named(&accepted, "a view written ahead of the take of its slot lives in the take once it is taken"),
        named(&accepted, "an owner consumed after the call result that holds a loan on it"),
        named(&rejected, "a view written ahead of a take, read before the take is defined"),
        named(&rejected, "an owner consumed while the call result that holds a loan on it is live"),
        named(&rejected, "a slot taken while an owned value holds a loan on it"),
        named(&rejected, "a borrow of a slot used after the slot is taken"),
        named(&accepted, "an edge that decides a test the other way is not taken"),
    };
    try std.testing.expectEqualStrings("", try firstWrong(arena.allocator(), &judged));
}

test "a borrow of one slot survives the replacement of another slot only when it is read again from the updated container" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const judged = [_]Fixture{
        named(&accepted, "a borrow of one slot read again from the container after another slot is replaced"),
        named(&rejected, "a borrow of one slot used after another slot of its container is replaced"),
    };
    try std.testing.expectEqualStrings("", try firstWrong(arena.allocator(), &judged));
    try std.testing.expectEqual(validate.Check.j4, judged[1].reject.?);
}

test "an element, an element field and a match mut payload are taken and closed in their own slots, [] returns borrowed as a constant, and a consuming loop pops what it takes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const judged = [_]Fixture{
        named(&accepted, "a list element taken and closed by the store of its replacement"),
        named(&accepted, "an element field taken by its path and closed by a store on the same path"),
        named(&accepted, "a match mut payload's field taken and closed inside the rebuilt payload"),
        named(&rejected, "a list returned while the take of one of its elements is open"),
        named(&rejected, "a list store at another element leaves an element take open"),
        named(&accepted, "a view of the static empty list returned beside a borrow"),
        named(&rejected, "a view of a fresh empty list returned as a borrowed result"),
        named(&accepted, "a consuming loop pops each taken element and drops the emptied list"),
        named(&rejected, "a consuming loop that takes an element without popping it"),
        named(&accepted, "an empty list default of unwrap_or returned under from: the borrowed phi takes the static empty list"),
    };
    try std.testing.expectEqualStrings("", try firstWrong(arena.allocator(), &judged));
    try std.testing.expectEqual(validate.Check.j8, judged[3].reject.?);
}

test "an exchanged element whose managed field is read is emptied: accepted, and refused without the field take or with a releasing store (FX15)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const judged = [_]Fixture{
        named(&accepted, "an exchanged element emptied by its field read, its take closed by the store of the replacement"),
        named(&rejected, "an exchanged element emptied but its field never taken"),
        named(&rejected, "an exchanged element emptied by its field read, and the store releases the slot it took"),
    };
    try std.testing.expectEqualStrings("", try firstWrong(arena.allocator(), &judged));
    try std.testing.expectEqual(validate.Check.j8, judged[1].reject.?);
}

test "match own: the certificate the lowering gives a consumed named owner, and its two unsound neighbours" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const judged = [_]Fixture{
        named(&accepted, "match own of an own parameter: its payload taken, a field moved out, the other arm dropping it"),
        named(&rejected, "match own of an own parameter: the union read after its payload is taken"),
        named(&rejected, "match own of an own parameter: an arm that neither takes nor drops the union"),
    };
    try std.testing.expectEqualStrings("", try firstWrong(arena.allocator(), &judged));
}

test "a mut local holding a borrow (4f): the loop phi the lowering gives it, and the per-iteration owner it may not borrow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const judged = [_]Fixture{
        named(&accepted, "a mut local holding a borrow carried around a loop: a borrowed phi of the parameter's views"),
        named(&rejected, "a mut local holding a borrow carried around a loop: the phi takes a view of an owner dropped in the iteration"),
    };
    try std.testing.expectEqualStrings("", try firstWrong(arena.allocator(), &judged));
}

test "a borrowed record (1A): the certificates the lowering gives a lent owner's record and a record returned under from" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const judged = [_]Fixture{
        named(&accepted, "a borrowed record (1A) of a lent owner: the owner is dropped after the record's last use"),
        named(&accepted, "a borrowed record (1A) returned under from: its field is a projection of the parameter"),
        named(&rejected, "a borrowed record (1A) of a lent owner: the owner is dropped before the record's last use"),
        named(&rejected, "an owned record built of a borrowed field: the record consumes the borrow and drops it"),
    };
    try std.testing.expectEqualStrings("", try firstWrong(arena.allocator(), &judged));
}

test "an own record parameter only read: the lowering drops it whole, and an emptied parameter line cannot be stated" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const judged = [_]Fixture{
        named(&accepted, "an own record parameter only read: its fields borrowed, the record dropped whole"),
        named(&rejected, "an own record parameter only read: the parameter stated owned, its line emptied"),
        named(&rejected, "an own record parameter only read: the record dropped before its second field is measured"),
        named(&rejected, "an own record parameter only read: the record never dropped"),
    };
    try std.testing.expectEqualStrings("", try firstWrong(arena.allocator(), &judged));
}

test "4c: a literal default is an immortal parent of the borrowed selection; a dropped fresh default is not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const judged = [_]Fixture{
        named(&accepted, "a literal default of unwrap_or returned under from: the borrowed phi takes the immortal constant"),
        named(&rejected, "a default of unwrap_or returned under from: the borrowed phi takes a fresh owner dropped before the join"),
    };
    try std.testing.expectEqualStrings("", try firstWrong(arena.allocator(), &judged));
}

test "a dictionary store with a borrowed key: the copy is made on the missing edge, and no other shape is sound" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const judged = [_]Fixture{
        named(&accepted, "a dictionary store with a borrowed key: the entry replaced on a hit, the key copied only on a miss"),
        named(&rejected, "a dictionary store with a borrowed key: the insertion consumes the borrowed key itself"),
        named(&rejected, "a dictionary store with a borrowed key: the key is copied before the probe and abandoned on the hit edge"),
    };
    try std.testing.expectEqualStrings("", try firstWrong(arena.allocator(), &judged));
    try std.testing.expectEqual(validate.Check.j5, judged[1].reject.?);
    try std.testing.expectEqual(validate.Check.j2, judged[2].reject.?);
}

test "a text that defines a value twice is malformed input, not a verdict" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var problem: parse.Problem = .{};
    try std.testing.expectError(error.Malformed, parse.parse(arena.allocator(), malformed[0].text, &problem));
    try std.testing.expectEqualStrings("a value is defined twice", problem.reason);
}

test "a line that names no value cannot give it a state, in the reader as in the checker's" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var problem: parse.Problem = .{};
    try std.testing.expectError(error.Malformed, parse.parse(arena.allocator(), malformed[1].text, &problem));
    try std.testing.expectEqualStrings("inst - must have state none", problem.reason);
}

/// The name of the first fixture of `list` among `names` whose rejection does not carry `fragment` in its detail; empty when all do.
fn detailMissing(a: std.mem.Allocator, list: []const Fixture, names: []const []const u8, fragment: []const u8) ![]const u8 {
    for (names) |name| {
        var problem: parse.Problem = .{};
        const functions = try parse.parse(a, named(list, name).text, &problem);
        switch (try validate.validate(a, functions[0])) {
            .rejected => |failure| if (std.mem.indexOf(u8, failure.detail, fragment) == null) return name,
            else => return name,
        }
    }
    return "";
}

test "an owned value lists only operands it reads, whatever instruction defines it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const owned = [_][]const u8{
        "an owned constructor that lists an owner it consumes as a parent",
        "the result record of a call with a mut argument that lists the union it consumes as a parent",
        "an owned constructor that lists its caller as a parent",
        "an owned call result that lists an owner it consumes as a parent",
        "an owned call result that lists its caller as a parent",
    };
    try std.testing.expectEqualStrings("", try detailMissing(arena.allocator(), &rejected, &owned, "parents:"));
}

test "a value that is neither owned nor borrowed has no parents, whatever instruction defines it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const bare = [_][]const u8{
        "a scalar constructor that lists a parent",
        "an emptied record that lists a parent",
        "a scalar call result that lists a parent",
        "an emptied call result that lists a parent",
    };
    try std.testing.expectEqualStrings("", try detailMissing(arena.allocator(), &rejected, &bare, "neither borrowed nor owned"));
}

test "a borrowed value borrows only from an operand, a loan of one, a later take of its container or a from value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const borrowed = [_][]const u8{
        "a borrowed constructor whose parent is not an operand it reads",
        "a borrowed call result whose from list names a value the call does not read",
        "a borrowed projection that names a scalar projection of its call as a parent",
        "a borrowed projection that names a later borrowed read of its container as a parent",
    };
    try std.testing.expectEqualStrings("", try detailMissing(arena.allocator(), &rejected, &borrowed, "parents:"));
}

/// The name of the first fixture of `list` from index `from` whose text the reader accepts; empty when it refuses them all.
fn firstAccepted(a: std.mem.Allocator, list: []const Fixture, from: usize) ![]const u8 {
    for (list[from..]) |fixture| {
        var problem: parse.Problem = .{};
        _ = parse.parse(a, fixture.text, &problem) catch continue;
        return fixture.name;
    }
    return "";
}

test "the reader refuses each text the checker's reader refuses: numbering, order, terminators, edges and signs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("", try firstAccepted(arena.allocator(), &malformed, 1));
}

test "a block that follows its terminator with another line is refused, not dropped" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text =
        \\function f result scalar from - unchecked -
        \\block b- preds -
        \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
        \\block b0 preds -
        \\term ret %9
        \\inst %1 add Pure reads %9,%9 consumes - state scalar parents -
        \\end
        \\
    ;
    var problem: parse.Problem = .{};
    try std.testing.expectError(error.Malformed, parse.parse(arena.allocator(), text, &problem));
    try std.testing.expectEqualStrings("a line after the terminator of its block", problem.reason);
}

const certificate_file =
    \\ownership-certificate-v2
    \\class iconst Constant
    \\class add Pure
    \\function f result scalar from - unchecked -
    \\block b- preds -
    \\inst %9 iconst Constant reads - consumes - state scalar parents - imm 0
    \\block b0 preds -
    \\term ret %9
    \\end
    \\
;

const unknown_operation =
    \\block b- preds -
    \\inst %9 add Pure reads - consumes - state scalar parents -
    \\block b0 preds -
    \\term ret %9
    \\end
    \\
;

test "a certificate file is read as the checker reads it: the format line, the class table and its operations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var problem: parse.Problem = .{};
    try std.testing.expectEqual(@as(usize, 1), (try parse.parseFile(a, certificate_file, &problem)).len);
    const header = "ownership-certificate-v2\n";
    const function_line = "function f result scalar from - unchecked -\n";
    const body = certificate_file[header.len..];
    const refused = [_]struct { text: []const u8, reason: []const u8 }{
        .{ .text = body, .reason = "not an ownership certificate file" },
        .{ .text = "ownership-certificate-v3\n" ++ body, .reason = "an unsupported format version" },
        .{ .text = "", .reason = "not an ownership certificate file" },
        .{ .text = header ++ "class iconst Nonsense\n", .reason = "an unknown class" },
        .{ .text = header ++ "class iconst Constant extra\n", .reason = "a malformed class line" },
        .{ .text = certificate_file ++ header, .reason = "a line outside a function" },
        .{ .text = header ++ "class iconst Constant\n" ++ function_line ++ "class add Pure\nend\n", .reason = "class line inside a function" },
        .{ .text = header ++ "class iconst Constant\n" ++ function_line ++ unknown_operation, .reason = "an operation that is not in the class table" },
    };
    for (refused) |case| {
        try std.testing.expectError(error.Malformed, parse.parseFile(a, case.text, &problem));
        try std.testing.expectEqualStrings(case.reason, problem.reason);
    }
}

test "the same text without a header or class table still reads as bare functions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var problem: parse.Problem = .{};
    const bare = certificate_file["ownership-certificate-v2\nclass iconst Constant\nclass add Pure\n".len..];
    try std.testing.expectEqual(@as(usize, 1), (try parse.parse(arena.allocator(), bare, &problem)).len);
}

test "an emptied aggregate misused in a block no edge reaches is judged like one in a block that is reached" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var problem: parse.Problem = .{};
    const whole = (try parse.parse(a, named(&rejected, "an emptied record consumed whole in a block no edge reaches").text, &problem))[0];
    const failure = (try validate.validate(a, whole)).rejected;
    try std.testing.expectEqual(validate.Check.j8, failure.check);
    try std.testing.expectEqual(@as(?u32, 1), failure.block);
    try std.testing.expectEqual(@as(?u32, 2), failure.index);
    const slots = (try parse.parse(a, named(&rejected, "an emptied record whose slots nobody takes in a block no edge reaches").text, &problem))[0];
    const unplaced = (try validate.validate(a, slots)).rejected;
    try std.testing.expectEqual(validate.Check.j8, unplaced.check);
    try std.testing.expectEqual(@as(?u32, null), unplaced.block);
}

test "a block that only reaches a trap merges like any other once the owners its paths abandon are listed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const judged = [_]Fixture{
        named(&accepted, "a block that only reaches a trap merges its edges once the owners they abandon are listed"),
        named(&accepted, "a trap path that leaves an owner live"),
        named(&rejected, "a block that only reaches a trap, entered by edges that disagree about the live owners"),
        named(&rejected, "a join where one arm consumed the owner"),
    };
    try std.testing.expectEqualStrings("", try firstWrong(arena.allocator(), &judged));
}

test "a rejection reports the block, the instruction, the judgment and its rules" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var problem: parse.Problem = .{};
    // By name, not by position: new fixtures may go anywhere in the list.
    const functions = try parse.parse(a, named(&rejected, "a list read after its drop").text, &problem);
    const verdict = try validate.validate(a, functions[0]);
    const failure = verdict.rejected;
    try std.testing.expectEqual(validate.Check.j3, failure.check);
    try std.testing.expectEqual(@as(?u32, 0), failure.block);
    try std.testing.expectEqual(@as(?u32, 2), failure.index);
    const line = try validate.describe(a, "f", failure);
    try std.testing.expect(std.mem.indexOf(u8, line, "J3 (used only while live; rules B3)") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "block b0, instruction 2") != null);
}

test "the validator imports only the form, the operation table and the operation names" {
    const sources = [_][]const u8{ @embedFile("validate_ownership.zig"), @embedFile("ownership_function.zig"), @embedFile("ownership_ops.zig"), @embedFile("ownership_certificate.zig") };
    const allowed = [_][]const u8{ "std", "builtin", "ir.zig", "flags.zig", "ownership_ops.zig", "ownership_function.zig", "ownership_certificate.zig" };
    try std.testing.expectEqual(@as(?[]const u8, null), foreignImport(&sources, &allowed));
}

/// The first `@import` of any source that is not in `allowed`, or null.
fn foreignImport(sources: []const []const u8, allowed: []const []const u8) ?[]const u8 {
    for (sources) |source| {
        var at: usize = 0;
        while (std.mem.indexOfPos(u8, source, at, "@import(\"")) |found| {
            const start = found + "@import(\"".len;
            const end = std.mem.indexOfScalarPos(u8, source, start, '"') orelse return source[found..];
            const name = source[start..end];
            at = end;
            var ok = false;
            for (allowed) |known| ok = ok or std.mem.eql(u8, known, name);
            if (!ok and !std.mem.startsWith(u8, source[found..], "@import(\"nothing")) return name;
        }
    }
    return null;
}

/// The verdict of the first function of `text`.
fn verdictOf(a: std.mem.Allocator, text: []const u8) !validate.Verdict {
    var problem: parse.Problem = .{};
    return validate.validate(a, (try parse.parse(a, text, &problem))[0]);
}

test "a block with a lend merges like any other: its edges agree on the live owners once the abandons are listed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const head =
        \\function f result scalar from - unchecked -
        \\param 0 %0 scalar
        \\callee 0 myl_core_group_open runtime - owned -
        \\block b- preds -
        \\inst %0 param Parameter reads - consumes - state scalar parents -
        \\block b0 preds -
        \\inst %1 call Call reads - consumes - state owned parents - from - callee 0
        \\inst %2 list_new Fresh reads %0 consumes - state owned parents -
        \\term branch %0 b1 b2
        \\block b1 preds b0
        \\term jump b3
        \\block b2 preds b0
        \\inst %5 list_new Fresh reads %0 consumes - state owned parents -
        \\term jump b3
        \\block b3 preds b1,b2
        \\
    ;
    const read = "inst %3 list_len Inspect reads %2 consumes - state scalar parents -\nterm unreachable\nend\n";
    const lend = "inst %3 box_make Construct reads %2,%1 consumes - state owned parents - lent %1\nterm unreachable\nend\n";
    try std.testing.expectEqual(validate.Check.j2, (try verdictOf(a, head ++ read)).rejected.check);
    try std.testing.expectEqual(validate.Check.j2, (try verdictOf(a, head ++ lend)).rejected.check);
    try std.testing.expectEqual(validate.Verdict.accepted, try verdictOf(a, head ++ "abandon b2 %5\n" ++ read));
    try std.testing.expectEqual(validate.Verdict.accepted, try verdictOf(a, head ++ "abandon b2 %5\n" ++ lend));
}

/// The line of `expected` the Lean checker gave for `function` of the file `path` (`fixtures-zig/loans.cert`), or null.
fn expectedLine(expected: []const u8, path: []const u8, function: []const u8, buffer: []u8) ?[]const u8 {
    const prefix = std.fmt.bufPrint(buffer, "{s} {s} ", .{ path, function }) catch return null;
    var lines = std.mem.splitScalar(u8, expected, '\n');
    while (lines.next()) |line| if (std.mem.startsWith(u8, line, prefix)) return line;
    return null;
}

/// The Zig validator's verdict on `function`, in the form of a line of the Lean checker's `expected.txt` after the name.
fn verdictLine(a: std.mem.Allocator, function: form.Function) ![]const u8 {
    return switch (try validate.validate(a, function)) {
        .accepted => "accept",
        .unchecked => |reason| try std.fmt.allocPrint(a, "unchecked {s}", .{reason.token()}),
        .rejected => |failure| blk: {
            // As `certcheck` and `selka validate-certificates` print it: `bN` or `b-`, an index or `-`.
            const block = if (failure.block) |id| try std.fmt.allocPrint(a, "b{d}", .{id}) else "b-";
            const index = if (failure.index) |at| try std.fmt.allocPrint(a, "{d}", .{at}) else "-";
            break :blk try std.fmt.allocPrint(a, "reject {s} {s} {s}", .{ failure.check.label(), block, index });
        },
    };
}

/// Every function of every `.cert` file of `proofs/ownership/<directory>` whose verdict from the Zig validator is not the line
/// the Lean checker gave in that directory's `expected.txt` (or has no line there); one description per line, empty when they
/// agree on all, and a function that is only in `expected.txt` is reported too.
fn differences(a: std.mem.Allocator, directory: []const u8) ![]const u8 {
    const path = try std.fmt.allocPrint(a, "proofs/ownership/{s}", .{directory});
    const expected = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, try std.fmt.allocPrint(a, "{s}/expected.txt", .{path}), a, .limited(1 << 20));
    var dir = try std.Io.Dir.cwd().openDir(std.testing.io, path, .{ .iterate = true });
    defer dir.close(std.testing.io);
    var found: std.ArrayList(u8) = .empty;
    var compared: usize = 0;
    var entries = dir.iterate();
    while (try entries.next(std.testing.io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".cert")) continue;
        const text = try dir.readFileAlloc(std.testing.io, entry.name, a, .limited(1 << 20));
        var problem: parse.Problem = .{};
        const functions = try parse.parseFile(a, text, &problem);
        const file = try std.fmt.allocPrint(a, "{s}/{s}", .{ directory, entry.name });
        var buffer: [256]u8 = undefined;
        for (functions) |function| {
            compared += 1;
            const wanted = expectedLine(expected, file, function.name, &buffer) orelse {
                try found.print(a, "{s} {s}: the expected file has no line\n", .{ file, function.name });
                continue;
            };
            const got = try std.fmt.allocPrint(a, "{s} {s} {s}", .{ file, function.name, try verdictLine(a, function) });
            if (!std.mem.eql(u8, got, wanted)) try found.print(a, "wanted `{s}`, got `{s}`\n", .{ wanted, got });
        }
    }
    const lines = std.mem.count(u8, std.mem.trimEnd(u8, expected, "\n"), "\n") + 1;
    if (lines != compared) try found.print(a, "{s}/expected.txt has {d} lines but {d} functions were compared\n", .{ directory, lines, compared });
    return found.items;
}

test "the validator gives the functions of the Lean fixtures the verdicts the Lean checker gives" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("", try differences(arena.allocator(), "fixtures-zig"));
}

test "the validator gives the trap fixtures of C9.1 the verdicts their expected file states" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("", try differences(arena.allocator(), "fixtures-zig-c9"));
}

test "the expected verdict of a fixture function is found by its file and name among the lines of others" {
    var buffer: [256]u8 = undefined;
    const text = "fixtures-zig/trap-region.cert other reject J8 b3 0\nfixtures-zig/taskgroup.cert other accept\nfixtures-zig/taskgroup.cert ok_group accept\n";
    try std.testing.expectEqualStrings("fixtures-zig/taskgroup.cert ok_group accept", expectedLine(text, "fixtures-zig/taskgroup.cert", "ok_group", &buffer).?);
    try std.testing.expectEqualStrings("fixtures-zig/taskgroup.cert other accept", expectedLine(text, "fixtures-zig/taskgroup.cert", "other", &buffer).?);
    try std.testing.expectEqual(@as(?[]const u8, null), expectedLine(text, "fixtures-zig/loans.cert", "other", &buffer));
}
