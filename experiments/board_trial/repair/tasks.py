"""Matched repair seeds; these are coordinator inputs, never repair-agent context."""

TASKS = {
    'identity': 'Restore component catalog validation. Component and net identities must remain distinct, including when their numeric values coincide.',
    'units': 'Restore the signed millimetres-to-micrometres conversion. Preserve the distinct input/output domains and return exactly input * 1000 for the provided bounded integers.',
    'state': 'Restore exhaustive preflight handling of through-vias. Validate their footprint and require their net to exist before invoking geometry. This is a missing-state regression, not a new snapshot schema.',
    'admission': 'Restore keepout net exemptions for tracks and through-vias. Admitted copper must bypass geometry; components are never net-exempt. Preserve all face/layer/block rules.',
    'boundary': 'Restore board containment: a footprint touching the board boundary is inside, while any positive extension beyond an edge is outside. Preserve keepout intersection semantics.',
}

UNIT_ZIG = '''const std = @import("std");
pub const Millimetres = enum(i64) { _ };
pub const Micrometres = enum(i64) { _ };
pub fn toMicro(value: Millimetres) Micrometres {
    return @fromBackingInt(@backingInt(value) * 1000);
}
'''


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f'seed anchor must occur once: {old!r}')
    return text.replace(old, new)


def allowed(language, task):
    if task == 'units':
        return ['guest/units.my'] if language == 'guest' else ['unit_conversion.zig']
    if language == 'zig':
        return ['baseline.zig']
    return [{'identity': 'guest/checks.my', 'state': 'guest/checks.my',
             'admission': 'guest/policy.my', 'boundary': 'guest/bounds.my'}[task]]


def seed(root, language, task):
    path = root / allowed(language, task)[0]
    text = path.read_text()
    if task == 'units':
        old = 'return Micrometres.make(unwrap(value) * 1000);' if language == 'guest' else 'return @fromBackingInt(@backingInt(value) * 1000);'
        text = replace_once(text, old, 'return value;')
    elif task == 'identity':
        old = 'inventory::has::< ids::ComponentId >(board.components, value.id, len(board.components))' if language == 'guest' else 'has(m.ComponentId, board.components, value.id)'
        new = 'inventory::has::< ids::NetId >(board.nets, value.id, len(board.nets))' if language == 'guest' else 'has(m.NetId, board.nets, value.id)'
        text = replace_once(text, old, new)
    elif task == 'state':
        old = ('''        },
        m::Feature.via(value) => {
            if !inventory::has::< ids::NetId >(board.nets, value.net, len(board.nets)) {
                return new m::Preflight.err(new m::Failure.input(new m::InputProblem.missing_net));
            }
        }
''' if language == 'guest' else '''            .via => |value| if (!has(m.NetId, board.nets, value.net)) {
                return .missing_net;
            },
''')
        text = replace_once(text, old, '        }\n' if language == 'guest' else '')
    elif task == 'admission':
        old = (' && !inventory::has::< ids::NetId >(region.allow_nets, value.net, len(region.allow_nets))'
               if language == 'guest' else ' and !has(m.NetId, region.allow_nets, value.net)')
        if text.count(old) != 2:
            raise ValueError('expected track and via exemption checks')
        text = text.replace(old, '')
        if language == 'zig':
            text = replace_once(text, '.via => |value| region.blocks.via,', '.via => region.blocks.via,')
    elif task == 'boundary':
        old = ('x >= left' if language == 'guest' else '@backingInt(inner.x) < @backingInt(outer.x)')
        new = ('x > left' if language == 'guest' else '@backingInt(inner.x) <= @backingInt(outer.x)')
        text = replace_once(text, old, new)
    else:
        raise ValueError(task)
    path.write_text(text)


def copy_files(source, target, names):
    for name in names:
        path = target / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes((source / name).read_bytes())
