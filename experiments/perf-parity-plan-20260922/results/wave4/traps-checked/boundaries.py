#!/usr/bin/env python3
"""Run every boundary case of cases2.my through several binaries; require identical results."""
import subprocess, sys
CASES = [
    ("i64", "add", "9223372036854775806", "1", "2"), ("i64", "add", "-9223372036854775807", "-1", "-2"),
    ("i64", "sub", "-9223372036854775807", "1", "2"), ("i64", "sub", "9223372036854775806", "-1", "-2"),
    ("i64", "mul", "3037000499", "3037000499", "3037000500"), ("i64", "mul", "-4611686018427387904", "2", "3"),
    ("i64", "mul", "-1", "-9223372036854775807", "-9223372036854775808"),
    ("u64", "add", "-2", "1", "2"), ("u64", "sub", "5", "5", "6"),
    ("u64", "mul", "4294967296", "4294967295", "4294967296"),
    ("i32", "add", "2147483646", "1", "2"), ("i32", "sub", "-2147483647", "1", "2"), ("i32", "mul", "46341", "46340", "46341"),
    ("u32", "add", "4294967294", "1", "2"), ("u32", "sub", "5", "5", "6"), ("u32", "mul", "65536", "65535", "65536"),
    ("i16", "add", "32766", "1", "2"), ("i16", "sub", "-32767", "1", "2"), ("i16", "mul", "182", "180", "181"),
    ("u16", "add", "65534", "1", "2"), ("u16", "sub", "5", "5", "6"), ("u16", "mul", "256", "255", "256"),
    ("i8", "add", "126", "1", "2"), ("i8", "sub", "-127", "1", "2"), ("i8", "mul", "11", "11", "12"),
    ("u8", "add", "254", "1", "2"), ("u8", "sub", "5", "5", "6"), ("u8", "mul", "16", "15", "16"),
]
bins = sys.argv[1:]
same = differ = 0
for width, op, x, ok, bad in CASES:
    for y in (ok, bad):
        args = [width, op, x, y]
        runs = [subprocess.run([b, *args], capture_output=True, text=True) for b in bins]
        sig = [(r.returncode, r.stdout, r.stderr) for r in runs]
        if all(s == sig[0] for s in sig):
            same += 1
        else:
            differ += 1
            print("DIFF", args, sig)
        r = runs[0]
        print(" ".join(args), r.returncode, r.stdout.strip(), r.stderr.split("\n")[0].split("error")[-1])
print(f"{same} identical, {differ} different, over {2 * len(CASES)} runs x {len(bins)} binaries")
