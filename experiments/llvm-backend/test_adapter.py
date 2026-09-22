#!/usr/bin/env python3
"""Focused correctness tests for the LLVM adapter boundary lowering."""

import os
import json
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from qbe_llvm import translate_text, LOADS, STORES  # noqa: E402
from runtime_signatures import signature as runtime_signature  # noqa: E402
from runtime_signatures import SIGNATURES  # noqa: E402


class AdapterTests(unittest.TestCase):
    def compile_units(self, units, main):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            assemblies = []
            signatures = {}
            for name, text in units.items():
                # All test units are known together, as they are in the build's
                # signature sidecar.
                from qbe_llvm import parse_unit, signature_map
                unit = parse_unit(text, name)
                signatures[unit.function.name] = signature_map(unit)
            for name, text in units.items():
                ir = translate_text(text, name, signatures)
                ll = root / f"{name}.ll"
                asm = root / f"{name}.s"
                ll.write_text(ir)
                subprocess.run(["zig", "cc", "-S", "-O2", "-fPIC", "-g0",
                                str(ll), "-o", str(asm)], check=True,
                               capture_output=True, text=True)
                assemblies.append(str(asm))
            source = root / "main.c"
            source.write_text(main)
            binary = root / "test"
            subprocess.run(["zig", "cc", *assemblies, str(source), "-o", str(binary)],
                           check=True, capture_output=True, text=True)
            return subprocess.run([str(binary)], check=True, capture_output=True,
                                  text=True).stdout

    def test_small_aggregate_argument_is_by_value(self):
        callee = """type :t16 = align 8 { b 16 }
export function $change(:t16 %arg) {
@entry
 storel 99, %arg
 ret
}
"""
        caller = """type :t16 = align 8 { b 16 }
export function l $test() {
@entry
 %value =l alloc8 16
 storel 11, %value
 %second =l add %value, 8
 storel 22, %second
 call $change(:t16 %value)
 %answer =l loadl %value
 ret %answer
}
"""
        self.assertEqual(self.compile_units(
            {"callee": callee, "caller": caller},
            '#include <stdio.h>\nextern long test(void);\n'
            'int main(void){printf("%ld\\n",test());}\n'), "11\n")

    def test_large_aggregate_uses_byval_and_sret(self):
        callee = """type :t24 = align 8 { b 24 }
export function :t24 $make(:t24 %arg) {
@entry
 storel 99, %arg
 ret %arg
}
"""
        caller = """type :t24 = align 8 { b 24 }
export function l $test() {
@entry
 %value =l alloc8 24
 storel 11, %value
 %result =:t24 call $make(:t24 %value)
 %changed =l loadl %result
 %original =l loadl %value
 %answer =l add %changed, %original
 ret %answer
}
"""
        ir = translate_text(callee, "callee", {"make": ((":t24",), ":t24")})
        self.assertIn("ptr sret([24 x i8]) align 8", ir)
        self.assertIn("ptr byval([24 x i8]) align 8", ir)
        self.assertEqual(self.compile_units(
            {"callee": callee, "caller": caller},
            '#include <stdio.h>\nextern long test(void);\n'
            'int main(void){printf("%ld\\n",test());}\n'), "110\n")

    def test_loop_aggregate_result_uses_one_entry_buffer(self):
        callee = """type :t72 = align 8 { b 72 }
export function :t72 $make72(l %value) {
@entry
 %out =l alloc8 72
 storel %value, %out
 ret %out
}
"""
        caller = """type :t72 = align 8 { b 72 }
export function l $loop72(l %limit) {
@entry
 %i =l copy 0
 %answer =l copy 0
 jmp @loop
@loop
 %value =:t72 call $make72(l %i)
 %answer =l loadl %value
 %i =l add %i, 1
 %again =l csltl %i, %limit
 jnz %again, @loop, @done
@done
 ret %answer
}
"""
        signatures = {"make72": (("l",), ":t72"),
                      "loop72": (("l",), "l")}
        ir = translate_text(caller, "loop72", signatures)
        entry, loop = ir.split("bb_loop:", 1)
        self.assertIn("alloca [72 x i8]", entry)
        self.assertNotIn("alloca [72 x i8]", loop)
        self.assertEqual(self.compile_units(
            {"callee": callee, "caller": caller},
            '#include <stdio.h>\nextern long loop72(long);\n'
            'int main(void){printf("%ld\\n",loop72(200000));}\n'), "199999\n")

    def test_memset_and_address_gep_are_typed(self):
        text = """export function $clear(l %p) {
@entry
 %field =l add %p, 8
 call $memset(l %field, w 0, l 16)
 ret
}
"""
        ir = translate_text(text, "clear")
        self.assertIn("@llvm.memset.p0.i64(ptr ", ir)
        self.assertIn("i8 0, i64 16, i1 false", ir)
        self.assertNotIn("declare void @memset", ir)

    def test_stack_floor_uses_complete_backend_frame(self):
        text = """export function l $guard(l %ctx) {
@entry
 %record =l alloc8 32
 %flooraddr =l add %ctx, 64
 %floor =l loadl %flooraddr
 %below =l cultl %record, %floor
 jnz %below, @floorfail3, @stackadmit1
@floorfail3
 ret 1
@stackadmit1
 %scratch =l alloc8 72
 ret 0
}
"""
        ir = translate_text(text, "guard")
        self.assertIn("call ptr @llvm.stacksave()", ir)
        self.assertIn("declare ptr @llvm.stacksave()", ir)

        copied = text.replace("jnz %below", "%same =l copy %below\n %noise =l add %ctx, 0\n jnz %same")
        self.assertIn("call ptr @llvm.stacksave()", translate_text(copied, "guard-copy"))

        decoy = text.replace("%below =l cultl %record, %floor",
                             "%below =l cultl %ctx, %floor")
        with self.assertRaisesRegex(Exception, "does not match"):
            translate_text(decoy, "guard-decoy")

        redefined = text.replace("%record =l alloc8 32", "%record =l copy %ctx", 1)
        redefined = redefined.replace("@stackadmit1\n", "@stackadmit1\n %record =l alloc8 32\n")
        with self.assertRaisesRegex(Exception, "does not match"):
            translate_text(redefined, "guard-redefined-later")
        redefined_before_branch = text.replace(
            "%record =l alloc8 32", "%record =l copy %ctx", 1).replace(
            "jnz %below", "%record =l alloc8 32\n jnz %below")
        with self.assertRaisesRegex(Exception, "does not match"):
            translate_text(redefined_before_branch, "guard-redefined-before-branch")

    def test_aggregate_alignment_is_preserved(self):
        for size, alignment in ((3, 1), (4, 4), (9, 1)):
            text = f"""type :t = align {alignment} {{ b {size} }}
export function :t $echo{size}(:t %value) {{
@entry
 ret %value
}}
"""
            ir = translate_text(text, f"align{size}",
                                {f"echo{size}": ((":t",), ":t")})
            self.assertIn(f"align {alignment}", ir)
            self.assertNotIn("align 8 %p_value", ir)

    def test_sysv_c_interop_sizes_and_register_rollback(self):
        layouts = ((1, 1), (3, 1), (4, 4), (8, 8), (9, 1), (16, 8),
                   (24, 8), (40, 8), (72, 8))
        units = {}
        declarations = []
        checks = []
        for size, alignment in layouts:
            units[f"echo{size}"] = f"""type :t = align {alignment} {{ b {size} }}
export function :t $echo{size}(:t %value) {{
@entry
 ret %value
}}
"""
            declarations.append(
                f"struct __attribute__((aligned({alignment}))) S{size} "
                f"{{ unsigned char b[{size}]; }};\n"
                f"extern struct S{size} echo{size}(struct S{size});")
            checks.append(
                f"{{ struct S{size} x={{0}}; x.b[0]={size}; x.b[{size - 1}]=0x5a; "
                f"struct S{size} y=echo{size}(x); if(memcmp(&x,&y,{size})) return {size}; }}")
        units["rollback"] = """type :t16 = align 8 { b 16 }
export function l $test5(l %a0, l %a1, l %a2, l %a3, l %a4, :t16 %v) {
@entry
 %x =l loadl %v
 %s0 =l add %a0, %a1
 %s1 =l add %s0, %a2
 %s2 =l add %s1, %a3
 %s3 =l add %s2, %a4
 %answer =l add %s3, %x
 ret %answer
}
"""
        declarations.append("struct S16r { long x,y; }; "
                            "extern long test5(long,long,long,long,long,struct S16r);")
        checks.append("if(test5(1,2,3,4,5,(struct S16r){100,200}) != 115) return 100;")
        units["mixed"] = """type :t8 = align 8 { b 8 }
type :t16 = align 8 { b 16 }
export function l $mixed(:t8 %one, d %scale, :t16 %two, l %tail) {
@entry
 %a =l loadl %one
 %b =l loadl %two
 %sum =l add %a, %b
 %answer =l add %sum, %tail
 ret %answer
}
"""
        declarations.append("struct S8m { long x; }; struct S16m { long x,y; }; "
                            "extern long mixed(struct S8m,double,struct S16m,long);")
        checks.append("if(mixed((struct S8m){7},2.5,(struct S16m){11,13},17)!=35) return 101;")
        units["sret_rollback"] = """type :t16 = align 8 { b 16 }
type :t24 = align 8 { b 24 }
export function :t24 $sret5(l %a0, l %a1, l %a2, l %a3, l %a4, :t16 %v) {
@entry
 %out =l alloc8 24
 %x =l loadl %v
 storel %x, %out
 %second =l add %out, 8
 storel 32, %second
 %third =l add %out, 16
 storel 33, %third
 ret %out
}
"""
        declarations.append("struct S24r { long x,y,z; }; "
                            "extern struct S24r sret5(long,long,long,long,long,struct S16r);")
        checks.append("{ struct S24r y=sret5(1,2,3,4,5,(struct S16r){31,99}); "
                      "if(y.x!=31 || y.y!=32 || y.z!=33) return 102; }")
        main = ("#include <string.h>\n" + "\n".join(declarations) +
                "\nint main(void){" + "".join(checks) + "return 0;}\n")
        self.assertEqual(self.compile_units(units, main), "")

    def test_rhs_integer_address_does_not_invent_provenance(self):
        text = """export function l $rhs(l %index, l %base) {
@entry
 %sum =l add %index, %base
 %value =l loadl %sum
 ret %value
}
"""
        ir = translate_text(text, "rhs")
        self.assertIn(" = add i64 ", ir)
        self.assertNotIn("getelementptr i8", ir)

        mutable = """export function l $mutable() {
@entry
 %base =l alloc8 16
 %index =l alloc8 8
 storel 1, %index
 %index =l copy 8
 %sum =l add %index, %base
 storel 77, %sum
 %answer =l loadl %sum
 ret %answer
}
"""
        self.assertEqual(self.compile_units(
            {"mutable": mutable},
            '#include <stdio.h>\nextern long mutable(void);\n'
            'int main(void){printf("%ld\\n",mutable());}\n'), "77\n")

    def test_indirect_call_matches_the_direct_convention(self):
        callee = """export function l $worker(l %ctx, l %value) {
@entry
 %scaled =l mul %value, 3
 %answer =l add %scaled, 1
 ret %answer
}
"""
        caller = """export function l $test(l %ctx) {
@entry
 %slot =l alloc8 8
 storel extern $worker, %slot
 %callee =l loadl %slot
 %through =l call %callee(l %ctx, l 7)
 %direct =l call $worker(l %ctx, l 7)
 %answer =l add %through, %direct
 ret %answer
}
"""
        self.assertEqual(self.compile_units(
            {"callee": callee, "caller": caller},
            '#include <stdio.h>\nextern long test(long);\n'
            'int main(void){printf("%ld\\n",test(0));}\n'), "44\n")

    def test_indirect_aggregate_result_matches_the_direct_convention(self):
        callee = """type :t24 = align 8 { b 24 }
export function :t24 $make24(l %value) {
@entry
 %out =l alloc8 24
 storel %value, %out
 %second =l add %out, 8
 storel 5, %second
 %third =l add %out, 16
 storel 6, %third
 ret %out
}
"""
        caller = """type :t24 = align 8 { b 24 }
export function l $test(l %ctx) {
@entry
 %slot =l alloc8 8
 storel extern $make24, %slot
 %callee =l loadl %slot
 %through =:t24 call %callee(l 42)
 %direct =:t24 call $make24(l 42)
 %first =l loadl %through
 %other =l loadl %direct
 %answer =l add %first, %other
 ret %answer
}
"""
        self.assertEqual(self.compile_units(
            {"callee": callee, "caller": caller},
            '#include <stdio.h>\nextern long test(long);\n'
            'int main(void){printf("%ld\\n",test(0));}\n'), "84\n")

    def test_indirect_aggregate_argument_matches_the_direct_convention(self):
        callee = """type :t24 = align 8 { b 24 }
export function l $sum24(:t24 %value) {
@entry
 %first =l loadl %value
 %second =l add %value, 8
 %middle =l loadl %second
 %third =l add %value, 16
 %last =l loadl %third
 %partial =l add %first, %middle
 %answer =l add %partial, %last
 ret %answer
}
"""
        caller = """type :t24 = align 8 { b 24 }
export function l $test(l %ctx) {
@entry
 %value =l alloc8 24
 storel 1, %value
 %second =l add %value, 8
 storel 2, %second
 %third =l add %value, 16
 storel 3, %third
 %slot =l alloc8 8
 storel extern $sum24, %slot
 %callee =l loadl %slot
 %through =l call %callee(:t24 %value)
 %direct =l call $sum24(:t24 %value)
 %answer =l add %through, %direct
 ret %answer
}
"""
        self.assertEqual(self.compile_units(
            {"callee": callee, "caller": caller},
            '#include <stdio.h>\nextern long test(long);\n'
            'int main(void){printf("%ld\\n",test(0));}\n'), "12\n")

    def test_nested_indirect_call_operand_is_lowered(self):
        """`add %a, call %f(...)` is a computed callee in operand position."""
        callee = """export function l $bump(l %value) {
@entry
 %answer =l add %value, 1
 ret %answer
}
"""
        caller = """export function l $test(l %ctx) {
@entry
 %slot =l alloc8 8
 storel extern $bump, %slot
 %callee =l loadl %slot
 %sum =l add 10, call %callee(l 4)
 ret %sum
}
"""
        self.assertEqual(self.compile_units(
            {"callee": callee, "caller": caller},
            '#include <stdio.h>\nextern long test(long);\n'
            'int main(void){printf("%ld\\n",test(0));}\n'), "15\n")

    def test_load_and_store_mnemonics_are_the_vendored_opcodes(self):
        """A misspelled row can never match, so the table is checked, not trusted."""
        text = (HERE.parent.parent / "vendor" / "qbe" / "ops.h").read_text()
        named = set(re.findall(r"(?m)^O\((\w+),", text))
        loads = {name for name in named if name.startswith("load") and name != "load"}
        # `loadl`, `loads` and `loadd` are the base opcode plus a type letter, so
        # the generated opcode list spells them through `load`, not directly.
        loads |= {"loadl", "loads", "loadd"}
        self.assertEqual(set(LOADS), loads)
        self.assertEqual(set(STORES), {name for name in named if name.startswith("store")})

    def test_zig_exported_helper_signature_is_generated(self):
        """A `@export`ed helper has no header, so the generator reads the Zig."""
        self.assertNotIn("myl_native_bytes_buffer_append_float", SIGNATURES)
        self.assertEqual(runtime_signature("myl_native_bytes_buffer_append_float"),
                         (("ptr", "ptr", "i64"), "i32"))
        self.assertEqual(runtime_signature("myl_native_bytes_number_parse"),
                         (("ptr", "i64", "i32", "ptr"), "i32"))

    def test_unregistered_runtime_helper_fails_closed(self):
        text = """export function $bad(l %p) {
@entry
 call $myl_qbe_new_helper(l %p)
 ret
}
"""
        with self.assertRaisesRegex(Exception, "no checked C signature"):
            translate_text(text, "bad")

    def test_generated_host_boundary_uses_pointer_signature(self):
        symbol = "myl_f_" + "a" * 64 + "_host"
        self.assertEqual(runtime_signature(symbol), (("ptr", "ptr", "ptr"), "void"))
        self.assertIsNone(runtime_signature("arbitrary_host"))
        self.assertIsNone(runtime_signature("myl_f_short_host"))
        unit = f"""export function l $test() {{
@entry
 %result =l alloc8 8
 call ${symbol}(l 0, l 0, l %result)
 %answer =l loadl %result
 ret %answer
}}
"""
        ir = translate_text(unit, "host")
        self.assertIn(f"declare void @{symbol}(ptr, ptr, ptr)", ir)
        self.assertEqual(self.compile_units({"host": unit},
            '#include <stdio.h>\nextern long test(void);\n'
            f'void {symbol}(void *ctx,void *args,long *out){{*out=42;}}\n'
            'int main(void){printf("%ld\\n",test());}\n'), "42\n")

    #: A unit whose object pointer arrives through memory, so nothing but the
    #: frontend's `# myl-obj` marker can place the header load it then does.
    OBJECT_PROBE = """export function l $test(l %ctx, l %handle) {
@entry
 %scratch =l alloc8 8
 %obj =l loadl %handle
MARKER
 %len =l loadl %obj
 storel %len, %scratch
 %answer =l loadl %scratch
 ret %answer
}
"""

    def test_marked_object_address_is_not_this_frame(self):
        ir = translate_text(self.OBJECT_PROBE.replace("MARKER", " # myl-obj %obj"), "obj")
        # Both the parameter-derived load and the marked header load are foreign;
        # the scratch slot's store and load are frame.
        self.assertEqual(2, ir.count("!alias.scope !4, !noalias !3"))
        self.assertIn("!alias.scope !3, !noalias !4", ir)
        self.assertIn('!0 = distinct !{!0, !"mylang memory classes"}', ir)
        self.assertEqual(1, ir.count('!1 = distinct !{!1, !0, !"frame"}'))
        self.assertEqual(self.compile_units({"obj": self.OBJECT_PROBE.replace("MARKER", " # myl-obj %obj")},
            '#include <stdio.h>\nextern long test(void *, void *);\n'
            'int main(void){long v=77;long *p=&v;printf("%ld\\n",test(0,&p));}\n'), "77\n")

    def test_unmarked_address_from_memory_carries_no_class(self):
        ir = translate_text(self.OBJECT_PROBE.replace("MARKER\n", ""), "obj")
        # `%obj` came out of memory, so the load through it is left unplaced and
        # only the load of `%handle`, which the parameter itself places, is foreign.
        self.assertEqual(1, ir.count("!alias.scope !4, !noalias !3"))
        self.assertIn("!alias.scope !3, !noalias !4", ir)

    def test_alias_metadata_is_switched_off_by_environment(self):
        with patch.dict(os.environ, {"MYLANG_QBE_LLVM_ALIAS": "0"}):
            ir = translate_text(self.OBJECT_PROBE.replace("MARKER", " # myl-obj %obj"), "obj")
        self.assertNotIn("alias.scope", ir)
        self.assertNotIn("noalias", ir)

    def test_helper_results_carry_the_class_their_definition_fixes(self):
        # A unit whose frame is too large for the stack keeps its slots in a
        # block `myl_qbe_frame_allocate` obtained on entry: that block is this
        # activation's own, while `myl_qbe_heap` answers the caller's context.
        unit = """export function l $test(l %ctx) {
@entry
 %frame_memory =l call $myl_qbe_frame_allocate(l %ctx, l 64)
 %heap =l call $myl_qbe_heap(l %ctx)
 %l0 =l add %frame_memory, 24
 storel 7, %l0
 %roots =l add %heap, 16
 %held =l loadl %roots
 %answer =l loadl %l0
 ret %answer
}
"""
        ir = translate_text(unit, "frames")
        self.assertIn("store i64 7, ptr %p", ir.split("!alias.scope !3, !noalias !4")[0])
        self.assertEqual(1, ir.count("!alias.scope !4, !noalias !3"))
        self.assertEqual(2, ir.count("!alias.scope !3, !noalias !4"))

    def test_a_slot_no_store_dominates_is_left_unplaced(self):
        # `%slot` is written only on one arm, so a load that runs on the other
        # answers whatever the frame held: nothing about it may be claimed.
        unit = """export function l $test(l %ctx, l %flag, l %obj) {
@entry
 %slot =l alloc8 8
 jnz %flag, @set, @read
@set
 storel %obj, %slot
 jmp @read
@read
 %held =l loadl %slot
 %value =l loadl %held
 ret %value
}
"""
        ir = translate_text(unit, "partial")
        self.assertNotIn("!alias.scope !4", ir)

    def test_heap_getter_has_only_proven_memory_effects(self):
        unit = """export function l $test(l %ctx) {
@entry
 %heap =l call $myl_qbe_heap(l %ctx)
 ret %heap
}
"""
        ir = translate_text(unit, "heap")
        self.assertIn("declare ptr @myl_qbe_heap(ptr) memory(none) nounwind willreturn", ir)
        self.assertEqual(set(ATTRIBUTES), {"myl_qbe_heap"})
        self.assertEqual(self.compile_units({"heap": unit},
            '#include <stdio.h>\nextern long test(void *);\n'
            'void *myl_qbe_heap(void *ctx){return ctx;}\n'
            'int main(void){int x;printf("%d\\n",test(&x)==(long)&x);}\n'), "1\n")

    HALTING_UNIT = """export function l $grow(l %ctx, l %a, l %b) {
@entry
 %sum =l add %a, %b
 %x =l xor %a, %sum
 %y =l xor %b, %sum
 %both =l and %x, %y
 %over =l csltl %both, 0
 jnz %over, @overflow, @checked
@overflow
 call $myl_qbe_fail_overflow_op(l %ctx, l 0, l %a, l %b, l 64)
 hlt
@checked
 ret %sum
@failure
 ret 0
}
"""

    def test_halted_failure_path_is_unreachable_and_its_helper_noreturn(self):
        # QBE-NORETURN-1: the fast protocol ends a fail helper's path in `hlt`.
        ir = translate_text(self.HALTING_UNIT, "halting")
        self.assertIn("call void @myl_qbe_fail_overflow_op(", ir)
        self.assertIn("  unreachable", ir)
        self.assertIn("declare void @myl_qbe_fail_overflow_op(ptr, i64, i64, i64, i64) noreturn cold", ir)
        # A unit that keeps the sticky return after any call to the helper says
        # it may return, so its declaration is only `cold`.
        sticky = self.HALTING_UNIT.replace(" hlt\n", " jmp @failure\n")
        ir = translate_text(sticky, "sticky")
        self.assertNotIn("unreachable", ir)
        self.assertIn("declare void @myl_qbe_fail_overflow_op(ptr, i64, i64, i64, i64) cold\n", ir)
        mixed = self.HALTING_UNIT.replace(
            "@checked\n ret %sum\n",
            "@checked\n %again =l csltl %sum, 0\n jnz %again, @late, @done\n"
            "@late\n call $myl_qbe_fail_overflow_op(l %ctx, l 0, l %a, l %b, l 64)\n"
            " jmp @failure\n@done\n ret %sum\n")
        self.assertIn("@myl_qbe_fail_overflow_op(ptr, i64, i64, i64, i64) cold\n",
                      translate_text(mixed, "mixed"))
        with self.assertRaisesRegex(Exception, "hlt takes no operands"):
            translate_text(self.HALTING_UNIT.replace(" hlt\n", " hlt %sum\n"), "operand")

    def test_halted_failure_path_leaves_through_the_helper(self):
        # The helper leaves through a non-local exit, the way the runtime's
        # `fail` does once the entry trampoline armed it.
        main = ('#include <setjmp.h>\n#include <stdio.h>\n#include <stdint.h>\n'
                'extern long grow(void *, long, long);\nstatic jmp_buf out;\n'
                'void myl_qbe_fail_overflow_op(void *c, int64_t op, int64_t l, int64_t r, int64_t w)'
                '{(void)c;(void)op;(void)w;printf("trap %lld %lld\\n",(long long)l,(long long)r);longjmp(out,1);}\n'
                'int main(void){int ctx;if(setjmp(out)==0){printf("%ld\\n",grow(&ctx,2,3));'
                'grow(&ctx,INT64_MAX,1);puts("fell through");}return 0;}\n')
        self.assertEqual(self.compile_units({"halting": self.HALTING_UNIT}, main),
                         "5\ntrap 9223372036854775807 1\n")

    def test_installed_registry_reads_materialized_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "helper.h").write_text(
                "int myl_native_test_materialized(void *value, int64_t start);\n")
            environment = dict(os.environ, MYLANG_QBE_LLVM_RUNTIME_SOURCES=directory)
            result = subprocess.run([sys.executable, "-c",
                "from runtime_signatures import signature; "
                "print(signature('myl_native_test_materialized'))"],
                cwd=HERE, env=environment, check=True, capture_output=True, text=True)
            self.assertEqual(result.stdout.strip(), "(('ptr', 'i64'), 'i32')")

    def test_benchmark_runtime_registry_is_complete(self):
        evidence = json.loads((HERE / "evidence" / "runtime-symbols.json").read_text())
        missing = []
        for name, entry in evidence["symbols"].items():
            if not entry.get("il_call_shapes"):
                continue
            if name.startswith(("myl_native_", "myl_qbe_", "myl_r_")):
                if runtime_signature(name) is None:
                    missing.append(name)
        self.assertEqual(missing, [])


if __name__ == "__main__":
    unittest.main()
