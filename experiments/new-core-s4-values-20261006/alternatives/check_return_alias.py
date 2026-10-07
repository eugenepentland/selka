#!/usr/bin/env python3
"""Exercise the experimental scalar return's mandatory shared-input detach."""
from pathlib import Path
root=Path(__file__).resolve().parent
text=(root/'union-find-cheaper-return.ll').read_text()
a=text.index('define i32 @main(');b=text.index('\n}\n',a)+3
main='''define i32 @main() {
entry:
  %old = call ptr @myl_core_list_new_slow(i64 3, i64 8)
  %length = getelementptr i8, ptr %old, i64 8
  store i64 3, ptr %length, align 8
  %data = getelementptr i8, ptr %old, i64 32
  %one = getelementptr i64, ptr %data, i64 1
  %two = getelementptr i64, ptr %data, i64 2
  store i64 0, ptr %data, align 8
  store i64 0, ptr %one, align 8
  store i64 1, ptr %two, align 8
  store i32 2, ptr %old, align 8
  %result = call { i64, ptr } @"my.row_union_find::find"(ptr %old, i64 2)
  %root = extractvalue { i64, ptr } %result, 0
  %changed = extractvalue { i64, ptr } %result, 1
  %changed_data = getelementptr i8, ptr %changed, i64 48
  %before = load i64, ptr %two, align 8
  %after = load i64, ptr %changed_data, align 8
  %root_ok = icmp eq i64 %root, 0
  %before_ok = icmp eq i64 %before, 1
  %after_ok = icmp eq i64 %after, 0
  %separate = icmp ne ptr %old, %changed
  %a = and i1 %root_ok, %before_ok
  %b = and i1 %after_ok, %separate
  %ok = and i1 %a, %b
  %status = select i1 %ok, i64 0, i64 1
  call void @myl_core_release(ptr %old)
  call void @myl_core_release(ptr %changed)
  %exit = call i32 @myl_core_exit(i64 %status)
  ret i32 %exit
}'''
(root/'union-find-cheaper-return-alias.ll').write_text(text[:a]+main+text[b:])
