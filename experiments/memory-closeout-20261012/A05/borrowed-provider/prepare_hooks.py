#!/usr/bin/env python3
"""Prepare reviewable shared-file hooks without editing the integration checkout."""
import argparse, difflib, hashlib, json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('integration',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
a.output.mkdir(parents=True,exist_ok=True)
changes={}; identities={}
def load(name):
    s=(a.integration/name).read_text(); changes[name]=s; identities[name]=hashlib.sha256(s.encode()).hexdigest();return s
def edit(name,before,after):
    s=changes.get(name)
    if s is None:s=load(name)
    if s.count(before)!=1: raise SystemExit(f'{name}: expected one hook, got {s.count(before)}: {before[:80]}')
    changes[name]=s.replace(before,after)
edit('src/core/single_owner.zig','    ambiguous_borrow: bool = false,','    ambiguous_borrow: bool = false,\n    provider_context: bool = false,')
edit('src/core/single_owner.zig','        if (c.state[slot].ambiguous_borrow and access != .read)', '        if (c.state[root].provider_context and access != .read) return c.reject(span, borrow_error, "a borrowed provider context is read-only and cannot be moved, stored or returned");\n        if (c.state[slot].ambiguous_borrow and access != .read)')
edit('src/core/single_owner.zig','''        const local = c.function.scope.locals[slot];
        if (c.view(local.ty)) {''','''        const local = c.function.scope.locals[slot];
        if (c.zero_rc and initializing and @import("borrowed_provider.zig").initializer(c.program, c.function, store.value)) {
            for (c.program.nodes[@backingInt(store.value)].data.record) |field| try c.expression(field.value, .read);
            c.state[slot] = .{ .available = true, .borrowed = true, .provider_context = true };
            return;
        }
        if (c.view(local.ty)) {''')
edit('src/core/single_owner.zig','''            .field => |field| {
                if (access == .move and c.owns(node.ty))''','''            .field => |field| {
                if (access != .read and c.owns(node.ty)) if (c.origin(field.base)) |root| {
                    if (c.state[root].provider_context) return c.reject(node.span, borrow_error, "a borrowed provider context cannot transfer a provider field; pass it to a read-only helper");
                };
                if (access == .move and c.owns(node.ty))''')
edit('src/core/build.zig','''        const value = try self.expressionPlace(store.value, &place);
        const block = self.current orelse return;
        try self.providerStore''','''        const borrowed_context = self.module().zero_rc and !assign and @import("borrowed_provider.zig").initializer(self.mb.input.program, self.checked, store.value);
        const value = if (borrowed_context) try self.borrowedProvider(store.value, span) else try self.expressionPlace(store.value, &place);
        const block = self.current orelse return;
        try self.providerStore''')
edit('src/core/build.zig','''    /// `Name(fields)`: the fields are evaluated in the order written and placed in declaration order.
    fn recordMake''','''    /// A local parameter-rooted provider context borrows each field without clearing ownership pins.
    fn borrowedProvider(self: *FnBuilder, id: typed.NodeId, span: u32) Error!ir.Ref {
        const ty = try self.typeOf(id);
        const stored = self.module().compound(ty).record;
        const values = try self.allocator().alloc(ir.Ref, stored.len);
        @memset(values, .none);
        for (self.nodeOf(id).data.record) |field| {
            const value = try self.expression(field.value);
            if (self.current == null) return .none;
            values[field.index] = try self.boxFor(stored[field.index], value, span);
        }
        const callee = @import("borrowed_provider.zig").declare(self.allocator(), self.module(), ty) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnsupportedInstruction => return self.mb.refuse("invalid borrowed provider context", span),
        };
        return self.emit(.{ .op = .call, .ty = ty, .a = @fromBackingInt(callee), .data = try self.extraSlice(values), .span = span });
    }

    /// `Name(fields)`: the fields are evaluated in the order written and placed in declaration order.
    fn recordMake''')
edit('src/core/own.zig','''                .call => if (self.viewSource(instruction) orelse self.encodedSource(instruction))''','''                .call => if ((@import("borrowed_provider.zig").call(self.module, f, instruction) catch return error.Unsupported) != null) .borrowed else if (self.viewSource(instruction) orelse self.encodedSource(instruction))''')
edit('src/core/own.zig','''    if (borrowedItem(module, f, record) != null) return false;
''','''    if (borrowedItem(module, f, record) != null) return false;
    if ((@import("borrowed_provider.zig").call(module, f, record) catch null) != null) return false;
''')
edit('src/core/emit_llvm.zig','''        if (try @import("borrow_selection.zig").declaration(self.module, &self.module.functions.items[index])) return;''','''        if (try @import("borrow_selection.zig").declaration(self.module, &self.module.functions.items[index])) return;
        if (try @import("borrowed_provider.zig").declaration(self.module, &self.module.functions.items[index])) return;''')
edit('src/core/emit_llvm.zig','''        if (try self.borrowedSelection(out, name, inst)) return;
''','''        if ((try @import("borrowed_provider.zig").call(self.state.module, self.function, inst)) != null) {
            var construction = inst;
            construction.op = .record_make;
            construction.a = .none;
            try self.recordMake(out, name, construction);
            return;
        }
        if (try self.borrowedSelection(out, name, inst)) return;
''')
edit('src/core/verify_ir.zig','''        _ = @import("borrow_selection.zig").declaration(module, f) catch {''','''        _ = @import("borrowed_provider.zig").declaration(module, f) catch {
            failure.* = .{ .function = f.name, .reason = "invalid borrowed provider context declaration" };
            return error.InvalidIr;
        };
        _ = @import("borrow_selection.zig").declaration(module, f) catch {''')
edit('src/core/verify_ir.zig','''                _ = @import("borrow_selection.zig").call(m, self.f, inst) catch break :blk false;''','''                _ = @import("borrowed_provider.zig").call(m, self.f, inst) catch break :blk false;
                _ = @import("borrow_selection.zig").call(m, self.f, inst) catch break :blk false;''')
# The current call exclusion suffices; this explicit guard preserves the invariant if policies expand.
for anchor in ['''            const helper = cfg.qualifies(callee);''','''            const result = leaf(callee) orelse continue;''']:
    edit('src/core/inline.zig',anchor,'''            if (@import("borrowed_provider.zig").contains(module, callee)) continue;
'''+anchor)
edit('src/core/marker_validation.zig','const selection = @import("borrow_selection.zig");','const selection = @import("borrow_selection.zig");\nconst providers = @import("borrowed_provider.zig");')
edit('src/core/marker_validation.zig','    if (!present(module, function)) return;\n    try selection.validate(a, module, function);','    if (!present(module, function) and !providers.contains(module, function)) return;\n    try providers.validate(a, module, function);\n    try selection.validate(a, module, function);')
edit('src/core/marker_validation.zig','        _ = try selection.declaration(module, function);','        _ = try providers.declaration(module, function);\n        _ = try selection.declaration(module, function);')
edit('src/core/cost.zig', 'fn calleeAllocation(module: *const ir.Module, callee: *const ir.Function) Allocation {', 'fn calleeAllocation(module: *const ir.Module, callee: *const ir.Function) Allocation {\n    if (@import("borrowed_provider.zig").declaration(module, callee) catch return .unresolved) return .never;\n    if (@import("borrowed_provider.zig").keepalive(module, callee) catch return .unresolved) return .never;')
patch=[]
for name,new in changes.items():
    old=(a.integration/name).read_text()
    if hashlib.sha256(old.encode()).hexdigest()!=identities[name]: raise SystemExit('inputs changed: '+name)
    path=a.output/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(new)
    patch.extend(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='a/'+name,tofile='b/'+name))
(a.output/'shared-hooks.patch').write_text(''.join(patch));(a.output/'source-hashes.json').write_text(json.dumps(identities,indent=2)+'\n')
print('Prepared',len(changes),'shared files; no integration files modified.')
