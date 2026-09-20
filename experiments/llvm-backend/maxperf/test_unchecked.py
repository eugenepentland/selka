#!/usr/bin/env python3

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
BACKEND = HERE.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(BACKEND))

from qbe_llvm import translate_text  # noqa: E402
from unchecked import Options, translate_unit  # noqa: E402


GUARDED = """export function l $checked(l %ctx, l %a, l %b) {
@entry
 %sum =l add %a, %b
 %bad =l csltl %sum, %a
 jnz %bad, @overflow1, @checked1
@overflow1
 call $myl_qbe_fail_overflow_op(l %ctx, l 0, l %a, l %b, l 64)
 jmp @failure
@checked1
 ret %sum
@failure
 ret 0
}
"""


class MaxperfTests(unittest.TestCase):
    def assembly(self, ir):
        with tempfile.TemporaryDirectory() as directory:
            ll = Path(directory) / "unit.ll"
            asm = Path(directory) / "unit.s"
            ll.write_text(ir)
            subprocess.run(["zig", "cc", "-S", "-O2", "-fPIC", "-g0",
                            str(ll), "-o", str(asm)], check=True,
                           capture_output=True, text=True)
            return asm.read_text()

    def test_baseline_is_normal_adapter_ir(self):
        expected = translate_text(GUARDED, "guarded")
        actual = translate_unit(GUARDED, Options("baseline"), unit_name="guarded")
        self.assertEqual(actual.ir, expected)
        self.assertEqual(actual.inventory.removed, {})

    def test_unchecked_removes_only_proven_failure_edge(self):
        translated = translate_unit(
            GUARDED, Options("unchecked", arena_proven=True), unit_name="guarded")
        self.assertEqual(translated.inventory.removed["overflow"], 1)
        assembly = self.assembly(translated.ir)
        self.assertNotIn("myl_qbe_fail_overflow_op", assembly)
        # The valid computation remains.
        self.assertTrue("addq" in assembly or "leaq" in assembly)

    def test_logical_result_branch_is_retained(self):
        text = """export function l $choice(l %condition) {
@entry
 jnz %condition, @err, @ok
@err
 ret 7
@ok
 ret 11
}
"""
        translated = translate_unit(
            text, Options("unchecked", arena_proven=True), unit_name="choice")
        self.assertEqual(translated.inventory.removed, {})
        self.assertIn("br i1", translated.ir)

    def test_frame_floor_and_sticky_trap_shapes_are_removed(self):
        frame = """export function l $frame(l %ctx) {
@entry
 %record =l alloc8 32
 %flooraddr =l add %ctx, 64
 %floor =l loadl %flooraddr
 %bad =l cultl %record, %floor
 jnz %bad, @floorfail1, @stackadmit1
@floorfail1
 call $myl_qbe_fail_frame(l %ctx)
 jmp @failure
@stackadmit1
 ret 9
@failure
 ret 0
}
"""
        result = translate_unit(
            frame, Options("unchecked", arena_proven=True), unit_name="frame")
        self.assertEqual(result.inventory.removed["frame_floor"], 1)

        sticky = """export function l $sticky(l %ctx) {
@entry
 %trap =l add %ctx, 32
 %set =l loadl %trap
 jnz %set, @failure, @ok1
@ok1
 ret 9
@failure
 ret 0
}
"""
        result = translate_unit(
            sticky, Options("unchecked", arena_proven=True), unit_name="sticky")
        self.assertEqual(result.inventory.removed["sticky_trap"], 1)

    def test_trace_frame_traffic_is_removed(self):
        text = """export function l $trace(l %ctx) {
@entry
 %record =l alloc8 32
 %head =l add %ctx, 48
 %old =l loadl %head
 storel %old, %record
 %meta =l add %record, 8
 storel extern $metadata, %meta
 %position =l add %record, 16
 storel 7, %position
 storel %record, %head
 %restore =l loadl %record
 storel %restore, %head
 ret 9
}
"""
        result = translate_unit(
            text, Options("unchecked", arena_proven=True), unit_name="trace")
        self.assertEqual(result.inventory.removed["trace_frame_load"], 2)
        self.assertEqual(result.inventory.removed["trace_frame_store"], 5)
        assembly = self.assembly(result.ir)
        self.assertNotIn("48(%rdi)", assembly)

    def test_arena_root_protocol_requires_proof_and_is_elided(self):
        text = """export function l $roots(l %ctx, l %value) {
@entry
 %heap =l call $myl_qbe_heap(l %ctx)
 %mark =l call $myl_qbe_root_mark(l %ctx)
 %head =l add %heap, 16
 storel %value, %head
 storel %mark, %head
 ret %value
}
"""
        with self.assertRaisesRegex(ValueError, "arena_proven"):
            translate_unit(text, Options("arena"), unit_name="roots")
        translated = translate_unit(
            text, Options("arena", arena_proven=True), unit_name="roots")
        self.assertEqual(translated.inventory.removed["arena_root_mark"], 1)
        self.assertEqual(translated.inventory.removed["arena_root_head_store"], 2)
        self.assertNotIn("call ptr @myl_qbe_root_mark", translated.ir)

    def test_ambiguous_failure_block_is_retained(self):
        text = GUARDED.replace(
            "call $myl_qbe_fail_overflow_op(l %ctx, l 0, l %a, l %b, l 64)",
            "call $myl_qbe_fail_overflow_op(l %ctx, l 0, l %a, l %b, l 64)\n"
            " call $myl_qbe_fail_cast(l %ctx, l %a, l 64)")
        translated = translate_unit(
            text, Options("unchecked", arena_proven=True), unit_name="ambiguous")
        self.assertEqual(translated.inventory.removed, {})
        self.assertEqual(translated.inventory.retained["ambiguous_failure_branch"], 1)
        self.assertIn("br i1", translated.ir)


if __name__ == "__main__":
    unittest.main()
