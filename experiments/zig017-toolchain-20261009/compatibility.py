"""Initialize ArrayList through its API on both snapshots (0.17 adds a lock)."""
import difflib
import re
from build_hashes import HERE, ROOT

def apply(source):
    changes = []
    for name in ['callables', 'nominal_catalog', 'type_catalog', 'frontend_patterns', 'generic_bodies']:
        path = source / 'src' / (name + '.zig')
        original = (ROOT / 'src' / (name + '.zig')).read_text()
        updated = re.sub(
            r'( *)(var storage: std\.ArrayList\(typed\.Record\)) = \.\{ \.items = ([^,]+), \.capacity = ([^}]+) \};',
            lambda m: f'{m[1]}{m[2]} = .empty;\n{m[1]}storage.items = {m[3]};\n{m[1]}storage.capacity = {m[4].strip()};',
            original)
        for field, kind in [('nodes', 'Node'), ('statements', 'Statement')]:
            updated = updated.replace(
                f'syntax.{field} = .{{ .items = {field}, .capacity = {field}.len }};',
                f'syntax.{field} = std.ArrayList(ast.{kind}).fromOwnedSlice({field});')
            updated = updated.replace(
                f'self.program.{field} = .{{ .items = try self.field_arena.allocator().dupe(ast.{kind}, self.program.{field}.items), .capacity = self.program.{field}.items.len }};',
                f'self.program.{field} = std.ArrayList(ast.{kind}).fromOwnedSlice(try self.field_arena.allocator().dupe(ast.{kind}, self.program.{field}.items));')
        path.write_text(updated)
        changes.extend(difflib.unified_diff(original.splitlines(True), updated.splitlines(True),
                                          fromfile='a/src/' + name + '.zig', tofile='b/src/' + name + '.zig'))
    (HERE / 'compatibility.patch').write_text(''.join(changes))
