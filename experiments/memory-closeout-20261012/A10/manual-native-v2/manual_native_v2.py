#!/usr/bin/env python3
"""Counter-only native replay from exact release LLVM and compiler-embedded inputs.

Call under one existing shared build admission. This never changes/adopts a
compiler cache receipt or claims the original compiler's failed build succeeded.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess

METHOD = "counted-release-native-replay-v2"
TARGET = "x86_64-linux-gnu.2.31"
CPU = ["-march=native", "-mllvm", "-x86-experimental-pref-innermost-loop-alignment=6"]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def digest(path):
    with Path(path).open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + "\n")


class Embedded:
    """Read named immutable ELF64 data without loading/executing the compiler."""
    def __init__(self, path, number_object=None):
        self.number_object = number_object
        self.provenance = {}
        self.file_segments = []
        self.data = Path(path).read_bytes()
        if self.data[:6] != b"\x7fELF\x02\x01":
            raise ValueError("requires an unstripped little-endian ELF64 compiler")
        offset = struct.unpack_from("<Q", self.data, 32)[0]
        width, count = struct.unpack_from("<HH", self.data, 54)
        self.segments = []
        for index in range(count):
            kind, flags, start, address, _, size, _, _ = struct.unpack_from("<IIQQQQQQ", self.data, offset + index * width)
            if kind == 1:
                self.segments.append((address, size, start))
                self.file_segments.append((start, size, flags))
        lines = subprocess.check_output(["nm", "-S", str(path)], text=True).splitlines()
        self.symbols = {}
        for line in lines:
            parts = line.split()
            if len(parts) == 4 and parts[3] in ("driver.runtime_source", "number_runtime.prebuilt"):
                if parts[3] in self.symbols:
                    raise ValueError("ambiguous embedded input symbol")
                self.symbols[parts[3]] = (int(parts[0], 16), int(parts[1], 16))

    def read(self, address, size):
        for begin, length, offset in self.segments:
            if begin <= address and address + size <= begin + length:
                return self.data[offset + address - begin:offset + address - begin + size]
        raise ValueError("embedded range is outside file-backed ELF segments")

    def complete_input(self, blob, kind):
        if self.data.count(blob) != 1:
            raise ValueError(kind + " must occur uniquely and completely in compiler ELF")
        offset = self.data.find(blob)
        if not any(start <= offset and offset + len(blob) <= start + size and flags & 2 == 0
                   for start, size, flags in self.file_segments):
            raise ValueError(kind + " is outside a read-only file-backed ELF segment")
        return dict(selection="unique-complete-input-v1", offset=offset, size=len(blob), sha256=sha(blob))

    def runtime(self, expected):
        if self.number_object is not None:
            self.provenance["runtime"] = self.complete_input(expected, "runtime")
            return
        address, size = self.symbols["driver.runtime_source"]
        if size != 8:
            raise ValueError("unexpected runtime array pointer layout")
        pointer, = struct.unpack("<Q", self.read(address, 8))
        if self.read(pointer, len(expected)) != expected:
            raise ValueError("Git runtime differs from compiler-embedded runtime")
        self.provenance["runtime"] = dict(selection="named-symbol-v1", size=len(expected), sha256=sha(expected))

    @staticmethod
    def relocatable_extent(blob):
        if len(blob) < 64 or blob[:6] != b"\x7fELF\x02\x01":
            raise ValueError("number object must be complete little-endian ELF64")
        kind, machine = struct.unpack_from("<HH", blob, 16)
        header, _, programs, width, count, strings = struct.unpack_from("<HHHHHH", blob, 52)
        table = struct.unpack_from("<Q", blob, 40)[0]
        if (kind != 1 or machine != 62 or header != 64 or programs or width != 64
                or not count or strings >= count or table < 64 or table + width * count > len(blob)):
            raise ValueError("number object has unsupported ET_REL header or section table")
        extent = table + width * count
        for index in range(count):
            _, section_kind, _, _, offset, size, _, _, _, _ = struct.unpack_from(
                "<IIQQQQIIQQ", blob, table + index * width)
            if section_kind != 8:
                if offset + size > len(blob):
                    raise ValueError("number object section extends beyond its input")
                extent = max(extent, offset + size)
        if extent != len(blob):
            raise ValueError("number object input has bytes beyond exact ELF extent")
        return extent

    def number(self):
        if self.number_object is not None:
            blob = Path(self.number_object).read_bytes()
            extent = self.relocatable_extent(blob)
            self.provenance["number"] = dict(self.complete_input(blob, "number object"),
                source=str(self.number_object), exact_elf_extent=extent)
            return blob
        address, size = self.symbols["number_runtime.prebuilt"]
        if size != 16:
            raise ValueError("unexpected embedded object slice layout")
        pointer, length = struct.unpack("<QQ", self.read(address, 16))
        blob = self.read(pointer, length)
        if blob[:4] != b"\x7fELF":
            raise ValueError("embedded number object is not ELF")
        self.relocatable_extent(blob)
        self.provenance["number"] = dict(selection="named-symbol-v1", size=len(blob), sha256=sha(blob))
        return blob


def environment(directory):
    forbidden = [key for key in ("MYLANG_CORE_LAYOUT", "MYLANG_CORE_SANITIZE", "ZIG_LIB_DIR", "LD_PRELOAD") if os.environ.get(key)]
    if forbidden:
        raise ValueError("unsupported nondefault build environment: " + ", ".join(forbidden))
    env = dict(os.environ)
    for key in ("MYLANG_COUNTERS", "MYLANG_OPTIONS", "MYL_CORE_LEAKCHECK"):
        env.pop(key, None)
    env["ZIG_LOCAL_CACHE_DIR"] = str(directory / "zig-local")
    env["ZIG_GLOBAL_CACHE_DIR"] = str(directory / "zig-global")
    return env


def run(command, directory, env, label):
    argv = list(map(str, command))
    result = subprocess.run(argv, cwd=directory, env=env, capture_output=True)
    (directory / (label + ".stdout")).write_bytes(result.stdout)
    (directory / (label + ".stderr")).write_bytes(result.stderr)
    save(directory / (label + ".json"), dict(argv=argv, cwd=str(directory), status=result.returncode,
         stdout_sha256=sha(result.stdout), stderr_sha256=sha(result.stderr)))
    if result.returncode:
        raise RuntimeError(f"{label}: status {result.returncode}: {result.stderr.decode(errors='replace')}")
    return result.stdout


def prepare(repository, revision, compiler, zig, directory, number_object=None):
    directory = Path(directory).resolve()
    method_hash = digest(__file__)
    identity = dict(method=METHOD, adapter_sha256=method_hash, compiler=str(compiler), compiler_sha256=digest(compiler),
                    source_revision=revision, zig=str(zig), zig_sha256=digest(zig))
    if number_object is not None:
        identity["number_object_input"] = dict(path=str(number_object), sha256=digest(number_object))
    receipt = directory / "runtime.json"
    if receipt.exists():
        found = json.loads(receipt.read_text())
        if any(found[key] != value for key, value in identity.items()):
            raise ValueError("refusing to reuse another adapter/compiler/runtime identity")
        for name, expected in found["files_sha256"].items():
            if digest(directory / name) != expected:
                raise ValueError("manual runtime artifact changed: " + name)
        return found
    directory.mkdir(parents=True, exist_ok=False)
    env = environment(directory)
    inputs = {}

    def source(name):
        data = subprocess.check_output(["git", "-C", str(repository), "show", f"{revision}:{name}"])
        inputs[name] = sha(data)
        return data

    driver = source("src/core/driver.zig").decode()
    runtime_declaration = re.search(r"pub const runtime_source = (.*?);\n", driver, re.S).group(1)
    fragments = re.findall(r'@embedFile\("([^\"]+)"\)', runtime_declaration)
    if not fragments or re.sub(r'@embedFile\("[^\"]+"\)|\+\+|"\\n"|\s+', '', runtime_declaration):
        raise ValueError("unrecognized runtime concatenation recipe")
    base = b"\n".join(source("src/core/" + name) for name in fragments)
    embedded = Embedded(compiler, number_object)
    embedded.runtime(base)
    (directory / "base.c").write_bytes(base)
    (directory / "number.o").write_bytes(embedded.number())
    for name in ("count_runtime.zig", "runtime/core_count.h", "runtime/core_count.c"):
        target = directory / name
        target.parent.mkdir(exist_ok=True)
        target.write_bytes(source("src/core/" + name))
    target = source("src/core/target.zig").decode()
    if f'pub const native_link_target = "{TARGET}";' not in target or '.cpu_flags = &.{ "-march=native", "-mllvm", "-x86-experimental-pref-innermost-loop-alignment=6" }' not in target:
        raise ValueError("native target policy changed; adapter review required")
    number = source("src/core/number_runtime.zig").decode()
    names = re.search(r"const names = \[_\]\[\]const u8\{(.*?)\};", number, re.S).group(1)
    flags = source("src/core/flags.zig").decode()
    buffer_symbol = re.search(r'pub const buffer_float_symbol = "([^"]+)";', flags).group(1)
    names = names.replace('@import("flags.zig").buffer_float_symbol', json.dumps(buffer_symbol))
    number_symbols = re.findall(r'"([^"]+)"', names)
    if not number_symbols or re.sub(r'"[^"]+"|,|\s+', "", names):
        raise ValueError("number-runtime dependency contract changed")
    exported = subprocess.check_output(["nm", "-g", "--defined-only", str(directory / "number.o")], text=True)
    if {line.split()[-1] for line in exported.splitlines() if line.split()} != set(number_symbols):
        raise ValueError("embedded number object exports differ from exact compiler helper contract")
    source("src/core/build_mode.zig")
    source("src/core/emit_units.zig")
    source("src/core/pipeline.zig")
    exporter = '''const std = @import("std");
const count = @import("count_runtime.zig");
pub fn main(init: std.process.Init) !void {
    const text = try count.source(init.arena.allocator(), @embedFile("base.c"));
    try std.Io.File.stdout().writeStreamingAll(init.io, "#define MYL_ZERO_RC 1\\n");
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
}
'''
    (directory / "export.zig").write_text(exporter)
    run([zig, "version"], directory, env, "zig-version")
    run([zig, "env"], directory, env, "zig-env")
    run([zig, "build-exe", directory / "export.zig", "-O", "ReleaseFast", "-femit-bin=" + str(directory / "export")], directory, env, "export-build")
    counted = run([directory / "export"], directory, env, "export-runtime")
    (directory / "counted.c").write_bytes(counted)
    common = ["-target", TARGET, *CPU]
    run([zig, "cc", "-c", "-O2", "-g0", "-falign-functions=64", *common, "-std=c11", "-pthread", "-o", directory / "runtime.o", directory / "counted.c"], directory, env, "runtime-build")
    files = ["base.c", "count_runtime.zig", "runtime/core_count.h", "runtime/core_count.c", "number.o", "export.zig", "export", "counted.c", "runtime.o"]
    identity.update(source_inputs_sha256=inputs, runtime_fragment_order=fragments, target=TARGET, cpu_flags=CPU,
                    embedded_runtime_matches_git=True, embedded_number_extracted=True, number_symbols=number_symbols,
                    embedded_input_provenance=embedded.provenance,
                    files_sha256={name:digest(directory/name) for name in files},
                    environment={key:env[key] for key in ("ZIG_LOCAL_CACHE_DIR", "ZIG_GLOBAL_CACHE_DIR")})
    if digest(compiler) != identity["compiler_sha256"] or digest(zig) != identity["zig_sha256"]:
        raise ValueError("compiler or Zig changed during runtime export")
    if number_object is not None and digest(number_object) != identity["number_object_input"]["sha256"]:
        raise ValueError("exact build number object changed during runtime export")
    save(receipt, identity)
    return identity


def link(runtime_dir, llvm, output, directory):
    runtime_dir, llvm, output, directory = (Path(p).resolve() for p in (runtime_dir, llvm, output, directory))
    receipt = json.loads((runtime_dir / "runtime.json").read_text())
    if receipt["adapter_sha256"] != digest(__file__):
        raise ValueError("adapter changed since runtime preparation")
    for name, expected in receipt["files_sha256"].items():
        if digest(runtime_dir/name) != expected:
            raise ValueError("manual runtime artifact changed: " + name)
    zig=Path(receipt["zig"])
    if digest(zig) != receipt["zig_sha256"]:
        raise ValueError("Zig identity changed")
    text=llvm.read_text()
    if "; mylang-zero-rc-v2\n" not in text or "@myl_count_current" not in text:
        raise ValueError("requires compiler-emitted owned counted LLVM")
    directory.mkdir(parents=True, exist_ok=False)
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise ValueError("refusing to replace an existing binary")
    env=environment(directory)
    common=["-target", TARGET, *CPU]
    program=directory/"program.o"
    llvm_hash=digest(llvm)
    run([zig,"cc","-c","-O3",*common,"-Wno-override-module","-o",program,llvm],directory,env,"program-build")
    number=any(name in text for name in receipt["number_symbols"])
    math="llvm.sin.f64" in text or "llvm.cos.f64" in text
    objects=[runtime_dir/"runtime.o",program]
    if number:objects.append(runtime_dir/"number.o")
    command=[zig,"cc","-O3",*common,"-pthread","-Wno-override-module","-o",output,*objects]
    if math:command.append("-lm")
    run(command,directory,env,"link")
    if digest(llvm)!=llvm_hash:raise ValueError("LLVM changed during compilation")
    result=dict(method=METHOD,adapter_sha256=digest(__file__),runtime_receipt=str(runtime_dir/"runtime.json"),
                runtime_receipt_sha256=digest(runtime_dir/"runtime.json"),llvm=str(llvm),llvm_sha256=llvm_hash,
                binary=str(output),binary_sha256=digest(output),objects_sha256={str(p):digest(p) for p in objects},
                number=number,math=math,source_revision=receipt["source_revision"],compiler_sha256=receipt["compiler_sha256"],
                scope="manual native counter supplement; original compiler build status remains separate; no timing/RSS claim")
    save(directory/"artifact.json",result)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    sub=parser.add_subparsers(dest="command",required=True)
    p=sub.add_parser("prepare")
    for name in ("repository","compiler","zig","directory"):p.add_argument("--"+name,type=lambda value:Path(value).resolve(),required=True)
    p.add_argument("--revision",required=True)
    p.add_argument("--number-object",type=lambda value:Path(value).resolve(),help="Exact object from frozen compiler build; requires complete unique embedded match")
    p=sub.add_parser("link")
    for name in ("runtime-dir","llvm","output","directory"):p.add_argument("--"+name,type=lambda value:Path(value).resolve(),required=True)
    args=parser.parse_args()
    if os.environ.get("MYLANG_ADMISSION_KIND")!="build":parser.error("run inside shared build admission; this adapter does not acquire nested admission")
    if args.command=="prepare":result=prepare(args.repository,args.revision,args.compiler,args.zig,args.directory,args.number_object)
    else:result=link(args.runtime_dir,args.llvm,args.output,args.directory)
    print(json.dumps(result,indent=2))


if __name__=="__main__":main()
