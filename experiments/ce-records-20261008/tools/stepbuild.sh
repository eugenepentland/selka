#!/usr/bin/env bash
# Build a development compiler with only the CE-A steps up to $1 enabled (1 = shared homes:
# phis and records updated in place, 2 = + views, 3 = + write-backs built in their field,
# 4 = + in-out `mut` records and results built in the caller's destination), saved as
# compilers/step$1.
set -eu
WT=/home/epentland/ai/canopy/mylang-worktrees/claude-ce-records
f=$WT/src/core/emit_homes.zig
cp $f $WT/.tmp/emit_homes.zig.keep
on() { [ "$1" -le "$2" ] && echo true || echo false; }
k=$1
sed -i "s/^pub const steps: .*/pub const steps: struct { homes: bool, views: bool, write_backs: bool, in_out: bool } = .{ .homes = $(on 1 $k), .views = $(on 2 $k), .write_backs = $(on 3 $k), .in_out = $(on 4 $k) };/" $f
grep "^pub const steps" $f
$WT/experiments/ce-records-20261008/tools/devbuild.sh step$k
cp $WT/.tmp/emit_homes.zig.keep $f
