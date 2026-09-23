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
from runtime_signatures import ATTRIBUTES  # noqa: E402


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

    #: An element read the way the frontend lowers `xs[i]`: the header's
    #: storage word, then storage plus the scaled index.
    ELEMENT_PROBE = """export function l $test(l %ctx, l %handle, l %index) {
@entry
 %obj =l loadl %handle
 # myl-obj %obj
 %field =l add %obj, 32
 %storage =l loadl %field
STORAGE
 %offset =l mul %index, 8
 %address =l add %storage, %offset
 %value =l loadl %address
 ret %value
}
"""

    def test_marked_element_address_is_a_getelementptr(self):
        # LLVM-OBJECT-GEP-1: storage marked as a managed object is a base the
        # element address is derived from with `getelementptr`, so a loop
        # vectorizer sees it advance with the index.
        ir = translate_text(self.ELEMENT_PROBE.replace("STORAGE", " # myl-obj %storage"), "element")
        self.assertEqual(2, ir.count("getelementptr i8"))
        self.assertEqual(self.compile_units({"element": self.ELEMENT_PROBE.replace("STORAGE", " # myl-obj %storage")},
            '#include <stdio.h>\nextern long test(void *, void *, long);\n'
            'int main(void){long data[3]={5,6,7};long header[5]={0,0,0,0,(long)data};'
            'long *p=header;printf("%ld\\n",test(0,&p,2));}\n'), "7\n")
        # An unmarked storage word keeps integer arithmetic for the element.
        plain = translate_text(self.ELEMENT_PROBE.replace("STORAGE\n", ""), "element")
        self.assertEqual(1, plain.count("getelementptr i8"))

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

    FRAME_MAP_UNIT = """dbgfile "myl_f_0123456789abcdef"
export function l $myl_f_0123456789abcdef(l %ctx, l %a) {
@entry
 jmp @frameadmit1
@frameadmit1
 %probe =l alloc8 8
 %slot =l add %ctx, 64
 %floor =l loadl %slot
 %below =l cultl %probe, %floor
 jnz %below, @floorfail2, @stackadmit2
@floorfail2
 dbgloc 1, 1
 call $myl_qbe_fail_frame(l %ctx)
 hlt
@stackadmit2
 dbgloc 5
 %r =l call $myl_f_fedcba9876543210(l %ctx, l %a)
 dbgloc 70000
 %s =l call $myl_f_fedcba9876543210(l %ctx, l %r)
 ret %s
}
"""

    def test_frame_map_calls_carry_probe_positions(self):
        # QBE-FRAMEMAP-1: every call carries its position as a debug location
        # whose discriminator is a pseudo-probe call index, so LLVM prints the
        # position (and any inline stack) before the call.
        ir = translate_text(self.FRAME_MAP_UNIT, "framemap")
        self.assertIn("!llvm.pseudo_probe_desc", ir)
        self.assertIn('linkageName: "myl_f_0123456789abcdef"', ir)
        self.assertIn("emissionKind: DebugDirectivesOnly", ir)
        self.assertIn("uwtable", ir.split("attributes #0 = {")[1].split("}")[0])
        self.assertNotIn('"frame-pointer"', ir)
        self.assertIn('"disable-tail-calls"="true"', ir)
        # Position 5 is probe 5; the guard's column-1 call is probe 0.
        self.assertIn(f"discriminator: {(5 << 3) | (100 << 19) | (2 << 26) | 7})", ir)
        self.assertIn(f"discriminator: {(100 << 19) | (2 << 26) | 7})", ir)
        self.assertRegex(ir, r"call i64 @myl_f_fedcba9876543210\([^)]*\) nomerge, !dbg !\d+")
        # A position past the probe range is `noinline` at its call and on the
        # function, and its location carries no discriminator.
        self.assertRegex(ir, r"nomerge noinline, !dbg !\d+")
        self.assertIn("noinline", ir.split("attributes #0 = {")[1].split("}")[0])
        self.assertIn("!DILocation(line: 70000, column: 0, scope: !101)", ir)
        # A frame-map unit that makes no call carries no debug information and
        # stays inlinable.
        leaf = ('dbgfile "myl_f_1111111111111111"\nexport function l $myl_f_1111111111111111(l %ctx, l %a) {\n'
                '@entry\n %b =l add %a, 1\n ret %b\n}\n')
        leaf_ir = translate_text(leaf, "leaf")
        self.assertNotIn("DISubprogram", leaf_ir)
        self.assertNotIn("noinline", leaf_ir)
        with self.assertRaisesRegex(Exception, "dbgloc takes a line"):
            translate_text(self.FRAME_MAP_UNIT.replace("dbgloc 5\n", "dbgloc x\n"), "bad")

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

    def test_dominators_match_the_set_definition_and_scale_linearly(self):
        # The immediate-dominator tree answers exactly what per-block dominator
        # sets answered, on hand graphs and random ones, including unreachable
        # blocks and loops, and a 60 000-block function no longer exhausts memory.
        import random
        from llvm_emit import Dominators

        def by_sets(entry, edges):
            reachable, pending = {entry}, [entry]
            while pending:
                for successor in edges[pending.pop()]:
                    if successor not in reachable:
                        reachable.add(successor)
                        pending.append(successor)
            predecessors = {label: [] for label in edges}
            for label, successors in edges.items():
                for successor in successors:
                    predecessors[successor].append(label)
            sets = {label: ({entry} if label == entry else set(reachable)) for label in reachable}
            changed = True
            while changed:
                changed = False
                for label in reachable - {entry}:
                    incoming = [sets[p] for p in predecessors[label] if p in reachable]
                    merged = set.intersection(*incoming) | {label}
                    if merged != sets[label]:
                        sets[label], changed = merged, True
            return sets

        rng = random.Random(7)
        graphs = [
            ("a", {"a": ["b", "c"], "b": ["d"], "c": ["d"], "d": [], "dead": ["d"]}),
            ("a", {"a": ["b"], "b": ["c", "e"], "c": ["b"], "e": []}),
        ]
        for _ in range(200):
            count = rng.randint(1, 12)
            labels = [f"n{i}" for i in range(count)]
            graphs.append(("n0", {label: rng.sample(labels, rng.randint(0, min(3, count))) for label in labels}))
        for entry, edges in graphs:
            expected = by_sets(entry, edges)
            relation = Dominators(entry, edges)
            for a in edges:
                for b in edges:
                    self.assertEqual(relation.dominates(a, b), a in expected.get(b, ()), (edges, a, b))
        chain = {f"b{i}": [f"b{i + 1}", f"x{i}"] for i in range(30000)}
        chain.update({f"x{i}": [f"b{i + 1}"] for i in range(30000)})
        chain["b30000"] = []
        relation = Dominators("b0", chain)
        self.assertTrue(relation.dominates("b0", "b30000"))
        self.assertTrue(relation.dominates("b29999", "x29999"))
        self.assertFalse(relation.dominates("x5", "b6"))

    def test_benchmark_runtime_registry_is_complete(self):
        evidence = json.loads((HERE / "evidence" / "runtime-symbols.json").read_text())
        # The evidence is a 2026-09-19 snapshot; a helper the runtime has since
        # removed (myl_native_text_points went with the UTF-8 text rewrite) is
        # no longer something the adapter can be asked to declare.
        runtime = "".join(p.read_text(errors="replace") for p in (HERE.parents[1] / "src").glob("*.[ch]"))
        missing = []
        for name, entry in evidence["symbols"].items():
            if not entry.get("il_call_shapes") or name not in runtime:
                continue
            if name.startswith(("myl_native_", "myl_qbe_", "myl_r_")):
                if runtime_signature(name) is None:
                    missing.append(name)
        self.assertEqual(missing, [])


#: The checked 64-bit shapes `src/qbe_scalar.zig` emits, verbatim in form: the
#: operation, the flag formula and the cold block with its fail call.  `OP` is
#: the operation's `typed.BinaryOp` code as the fail call passes it.
CHECK_BODIES = {
    ("add", True): """ %r =l add %a, %b
 %x =l xor %a, %r
 %y =l xor %b, %r
 %both =l and %x, %y
 %flag =l csltl %both, 0
""",
    ("sub", True): """ %r =l sub %a, %b
 %x =l xor %a, %b
 %y =l xor %a, %r
 %both =l and %x, %y
 %flag =l csltl %both, 0
""",
    ("add", False): """ %r =l add %a, %b
 %flag =l cultl %r, %a
""",
    ("sub", False): """ %r =l sub %a, %b
 %flag =l cultl %a, %b
""",
}
_HIGH = """ %al =l and %a, 4294967295
 %ah =l shr %a, 32
 %bl =l and %b, 4294967295
 %bh =l shr %b, 32
 %base =l mul %al, %bl
 %carry =l shr %base, 32
 %cross =l mul %ah, %bl
 %middle =l add %cross, %carry
 %lm =l and %middle, 4294967295
 %hm =l shr %middle, 32
 %other =l mul %al, %bh
 %sum =l add %other, %lm
 %c2 =l shr %sum, 32
 %top =l mul %ah, %bh
 %partial =l add %top, %hm
 %high =l add %partial, %c2
"""
CHECK_BODIES[("mul", False)] = " %r =l mul %a, %b\n" + _HIGH + " %flag =l cnel %high, 0\n"
CHECK_BODIES[("mul", True)] = (" %r =l mul %a, %b\n" + _HIGH + """ %ln =l csltl %a, 0
 %rn =l csltl %b, 0
 %lmask =l neg %ln
 %rmask =l neg %rn
 %lt =l and %b, %lmask
 %rt =l and %a, %rmask
 %adj =l sub %high, %lt
 %adj =l sub %adj, %rt
 %sign =l sar %r, 63
 %flag =l cnel %adj, %sign
""")
STEMS = {("add", True): "sadd", ("sub", True): "ssub", ("mul", True): "smul",
         ("add", False): "uadd", ("sub", False): "usub", ("mul", False): "umul"}
OPCODES = {"add": 0, "sub": 1, "mul": 2}


def checked_unit(op, signed, body=None, ending=" hlt\n"):
    """One unit `$f_<op>(ctx, a, b)` returning `a <op> b` or calling the fail helper."""
    name = f"f_{op}_{'s' if signed else 'u'}"
    return (f"export function l ${name}(l %ctx, l %a, l %b) {{\n@start\n"
            + (body if body is not None else CHECK_BODIES[(op, signed)])
            + " jnz %flag, @overflow, @checked\n@overflow\n"
            f" call $myl_qbe_fail_overflow_op(l %ctx, l {OPCODES[op]}, l %a, l %b, l 64)\n"
            + ending + "@checked\n ret %r\n}\n")


class CheckedArithmeticTests(unittest.TestCase):
    """LLVM-OVERFLOW-INTRINSIC-1: checked `+ - *` reach LLVM as overflow intrinsics."""

    compile_units = AdapterTests.compile_units

    def test_each_shape_lowers_to_its_intrinsic(self):
        for (op, signed), stem in STEMS.items():
            with self.subTest(op=op, signed=signed):
                ir = translate_text(checked_unit(op, signed), f"{op}{signed}")
                self.assertIn(f"call {{ i64, i1 }} @llvm.{stem}.with.overflow.i64(", ir)
                self.assertIn(f"declare {{ i64, i1 }} @llvm.{stem}.with.overflow.i64(i64, i64)", ir)
                self.assertEqual(ir.count(".with.overflow.i64("), 2)
                # The flag is the intrinsic's bit; the fail call is untouched.
                self.assertRegex(ir, r"zext i1 %ov\d+ to i64")
                self.assertIn(f"call void @myl_qbe_fail_overflow_op(ptr %", ir)
                self.assertIn(f", i64 {OPCODES[op]}, i64 %", ir)

    def test_each_shape_compiles_to_the_flag_branch(self):
        # The machine code is the operation and one flag branch.
        for (op, signed), jump in {("add", True): "jo", ("sub", True): "jo",
                                   ("mul", True): "jo", ("add", False): "jb",
                                   ("sub", False): "jb", ("mul", False): "jo"}.items():
            with self.subTest(op=op, signed=signed):
                ir = translate_text(checked_unit(op, signed), "shape")
                with tempfile.TemporaryDirectory() as directory:
                    ll = Path(directory, "u.ll")
                    ll.write_text(ir)
                    asm = Path(directory, "u.s")
                    subprocess.run(["zig", "cc", "-S", "-O2", "-fPIC", "-g0", str(ll), "-o",
                                    str(asm)], check=True, capture_output=True, text=True)
                    code = asm.read_text().split(f"f_{op}_{'s' if signed else 'u'}:")[1]
                self.assertRegex(code, rf"\n\s+{jump}\s")
                self.assertNotIn("shrq", code)
                self.assertNotIn("sarq", code)

    def test_results_and_traps_match_the_exact_operation(self):
        # Every shape against the compiler's own overflow builtins, on the
        # boundaries of both signed and unsigned 64-bit ranges.
        units = {f"{op}{signed}": checked_unit(op, signed) for op, signed in STEMS}
        edges = [0, 1, 2, 3, -1, -2, -3, 2**31 - 1, 2**31, -2**31, 2**32 - 1, 2**32,
                 3037000499, 3037000500, -3037000499, -3037000500, 4294967296 + 7,
                 2**62, -2**62, 2**63 - 1, 2**63 - 2, -2**63, -2**63 + 1]
        table = ", ".join(f"{e}LL" if e != -2**63 else "INT64_MIN" for e in edges)
        calls = []
        for op, signed in STEMS:
            name = f"f_{op}_{'s' if signed else 'u'}"
            builtin = f"__builtin_{op}_overflow"
            kind = "int64_t" if signed else "uint64_t"
            calls.append(
                f'for(int i=0;i<N;i++)for(int j=0;j<N;j++){{{kind} want;int64_t got;'
                f'int over={builtin}(({kind})V[i],({kind})V[j],&want);'
                f'trapped=0;if(setjmp(out)==0)got={name}(&ctx,V[i],V[j]);'
                f'if(over!=trapped||(!over&&got!=(int64_t)want)){{printf("{name} %lld %lld\\n",'
                f'(long long)V[i],(long long)V[j]);bad++;}}'
                f'if(over&&(seen_l!=V[i]||seen_r!=V[j]||seen_op!={OPCODES[op]}))bad++;count++;}}')
        declarations = "".join(f"extern int64_t f_{op}_{'s' if s else 'u'}(void*,int64_t,int64_t);"
                               for op, s in STEMS)
        main = ('#include <setjmp.h>\n#include <stdio.h>\n#include <stdint.h>\n'
                + declarations + '\nstatic jmp_buf out;static volatile int trapped;'
                'static int64_t seen_op,seen_l,seen_r;\n'
                'void myl_qbe_fail_overflow_op(void *c,int64_t op,int64_t l,int64_t r,int64_t w)'
                '{(void)c;(void)w;seen_op=op;seen_l=l;seen_r=r;trapped=1;longjmp(out,1);}\n'
                f'static const int64_t V[]={{{table}}};\n'
                'int main(void){int ctx;int bad=0,count=0;const int N=sizeof V/sizeof V[0];'
                + "".join(calls) + 'printf("%d %d\\n",bad,count);return 0;}\n')
        self.assertEqual(self.compile_units(units, main), f"0 {len(edges) ** 2 * 6}\n")

    def test_only_the_exact_formula_is_rewritten(self):
        near_misses = {
            # the formula over a different operation's result
            "operands swapped in the flag": CHECK_BODIES[("add", True)].replace(
                "xor %b, %r", "xor %r, %b"),
            "a reassigned between the operation and the flag": CHECK_BODIES[("add", True)].replace(
                " %x =l", " %a =l add %a, 1\n %x =l"),
            "the wrong compare": CHECK_BODIES[("add", True)].replace("csltl %both, 0",
                                                                    "cslel %both, 0"),
            "a 32-bit flag": CHECK_BODIES[("add", False)].replace("cultl %r, %a", "cultw %r, %a"),
            "a word operation": CHECK_BODIES[("add", True)].replace("%r =l add", "%r =w add"),
            "a range test": " %r =l add %a, %b\n %lo =l csltl %r, -2147483648\n"
                            " %hi =l csgtl %r, 2147483647\n %flag =l or %lo, %hi\n",
            "the signed product off by one limb": CHECK_BODIES[("mul", True)].replace(
                "%sign =l sar %r, 63", "%sign =l sar %r, 62"),
        }
        for label, body in near_misses.items():
            with self.subTest(label):
                op = "mul" if "product" in label else "add"
                ir = translate_text(checked_unit(op, True, body), "miss")
                self.assertNotIn("with.overflow", ir)
        # A redefinition of the result's name after the flag does not matter,
        # and one before the flag does.
        late = CHECK_BODIES[("add", True)] + " %a =l copy 0\n"
        self.assertIn("sadd.with.overflow", translate_text(checked_unit("add", True, late), "late"))
        # The sticky protocol is matched the same way.
        sticky = translate_text(checked_unit("sub", True, ending=" jmp @failure\n@failure\n ret 0\n"), "sticky")
        self.assertIn("ssub.with.overflow", sticky)

    def test_the_formulas_are_identities_on_every_input(self):
        # The rewrite needs no fact about the operands: each formula the
        # matcher accepts equals the intrinsic's overflow bit for all inputs.
        import random
        from llvm_emit import overflow_formulas
        mask = (1 << 64) - 1

        def signed(v):
            return v - (1 << 64) if v >> 63 else v

        def evaluate(node, env):
            head = node[0]
            if head == "const":
                return node[1]
            if head == "entry":
                return env[node[1]]
            args = [evaluate(child, env) for child in node[1:]]
            if head == "neg":
                return (-args[0]) & mask
            a, b = args
            return {"add": (a + b) & mask, "sub": (a - b) & mask, "mul": (a * b) & mask,
                    "and": a & b, "xor": a ^ b, "shr": a >> (b & 63),
                    "sar": (signed(a) >> (b & 63)) & mask,
                    "csltl": int(signed(a) < signed(b)), "cultl": int(a < b),
                    "cnel": int(a != b)}[head]

        exact = {"sadd": lambda a, b: not -2**63 <= signed(a) + signed(b) < 2**63,
                 "ssub": lambda a, b: not -2**63 <= signed(a) - signed(b) < 2**63,
                 "smul": lambda a, b: not -2**63 <= signed(a) * signed(b) < 2**63,
                 "uadd": lambda a, b: a + b > mask, "usub": lambda a, b: a < b,
                 "umul": lambda a, b: a * b > mask}
        edges = [0, 1, 2, 3, 2**31, 2**32 - 1, 2**32, 2**32 + 1, 3037000499, 3037000500,
                 2**62, 2**63 - 1, 2**63, 2**63 + 1, 2**64 - 1, 2**64 - 2, 2**64 - 2**32]
        edges += [(-e) & mask for e in edges]
        generator = random.Random(20260923)
        pairs = [(a, b) for a in edges for b in edges]
        pairs += [(generator.getrandbits(generator.choice((8, 32, 33, 63, 64))),
                   generator.getrandbits(generator.choice((8, 32, 33, 63, 64))))
                  for _ in range(20000)]
        a_leaf, b_leaf = ("entry", "a"), ("entry", "b")
        for op in ("add", "sub", "mul"):
            for stem, flag in overflow_formulas((op, a_leaf, b_leaf)):
                with self.subTest(stem=stem):
                    for a, b in pairs:
                        self.assertEqual(bool(evaluate(flag, {"a": a, "b": b})),
                                         exact[stem](a, b), (stem, a, b))


if __name__ == "__main__":
    unittest.main()
