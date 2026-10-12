#!/usr/bin/env python3
"""Emit coordinator-owned wiring as a reviewable patch without applying it."""
from pathlib import Path
import difflib

ROOT = Path(__file__).resolve().parents[3]
patches = []
def edit(path, transform):
    before = (ROOT / path).read_text()
    after = transform(before)
    assert after != before, path
    patches.extend(difflib.unified_diff(before.splitlines(True), after.splitlines(True), fromfile='a/' + path, tofile='b/' + path))

def root(text):
    text = text.replace('    _ = @import("format_spec_test.zig");\n', '')
    return text.replace('test {\n    _ = @import("number_text.zig");\n    _ = @import("number_text_test.zig");\n}\n\n', '')
edit('src/root_test.zig', root)
edit('build_test_inputs.zig', lambda t: t.replace('/// The independently gated named byte-ceiling module.', '''/// Complete scalar-text implementation and embedded oracle closure.
pub const text_scalar_unit = [_][]const u8{
    "src/text_scalar_root_test.zig", "src/number_text.zig", "src/number_text_test.zig",
    "src/number_grammar.txt", "src/format_spec.zig", "src/format_spec_test.zig",
    "src/format_spec_cases.tsv",
};

/// The independently gated named byte-ceiling module.'''))
def build(text):
    start = text.index('    const tooling_unit = b.addTest(')
    end = text.index('    const unit = b.addTest(', start)
    definition = text[start:end].replace('tooling_unit', 'text_scalar_unit').replace('tooling-unit-tests', 'text-scalar-unit-tests').replace('tooling_root_test.zig', 'text_scalar_root_test.zig')
    text = text[:end] + definition + text[end:]
    start = text.index('    const run_tooling_unit = b.addRunArtifact(')
    end = text.index('    const run_budget_unit =', start)
    runs = text[start:end].replace('tooling_unit', 'text_scalar_unit').replace('focused_tooling', 'focused_text_scalar').replace('test-tooling-units', 'test-text-scalar-units').replace('independent pure tooling tests', 'independent scalar text tests')
    text = text[:end] + runs + text[end:]
    text = text.replace('    if (test_filters.len == 0) units_step.dependOn(&focused_tooling.step);', '    if (test_filters.len == 0) units_step.dependOn(&focused_tooling.step);\n    if (test_filters.len == 0) units_step.dependOn(&focused_text_scalar.step);')
    text = text.replace('    if (test_filters.len == 0) units_sharded.dependOn(&focused_tooling.step);', '    if (test_filters.len == 0) units_sharded.dependOn(&focused_tooling.step);\n    if (test_filters.len == 0) units_sharded.dependOn(&focused_text_scalar.step);')
    text = text.replace('    audit_runtime.dependOn(&focused_tooling.step);', '    audit_runtime.dependOn(&focused_tooling.step);\n    audit_runtime.dependOn(&focused_text_scalar.step);')
    text = text.replace('        .{ .label = "tooling-units", .binary = tooling_unit },', '        .{ .label = "tooling-units", .binary = tooling_unit },\n        .{ .label = "text-scalar-units", .binary = text_scalar_unit },')
    return text.replace('    verification_registry.?.artifactDependencies("tooling_unit", &.{"tooling-units"});', '    verification_registry.?.artifactDependencies("tooling_unit", &.{"tooling-units"});\n    verification_registry.?.artifactDependencies("text_scalar_unit", &.{"text-scalar-units"});')
edit('build.zig', build)
edit('tests/test_inputs_coverage.py', lambda t: t.replace('ROOTS = {', 'ROOTS = {\n    "src/text_scalar_root_test.zig": "text_scalar_unit",'))
FILES = ('text_scalar_root_test.zig', 'number_text.zig', 'number_text_test.zig', 'number_grammar.txt', 'format_spec.zig', 'format_spec_test.zig', 'format_spec_cases.tsv')
edit('scripts/affected_tests.py', lambda t: t.replace('HOST_STEPS = (', 'HOST_STEPS = (\n' + ''.join('    ("src/' + p + '", "test-text-scalar-units"),\n' for p in FILES)))
edit('scripts/focused_test.py', lambda t: t.replace('FOCUSED = {', 'FOCUSED = {"text-scalar": "test-text-scalar-units", ').replace('units, tooling, cli, golden, or full', 'units, tooling, text-scalar, cli, golden, or full'))
print(''.join(patches), end='')
