#!/usr/bin/env python3
"""A valid scalar find return: detach once in an inlined wrapper, then mutate.

This experiment changes no retained runtime ABI. find never changes list length,
allocates a new list, or shares its parent. Its private scalar implementation can
therefore update the wrapper's uniquely owned list and return only the root.
The public-to-generated-caller wrapper returns the original mut aggregate shape.
"""
from pathlib import Path
import re
root = Path(__file__).resolve().parent
text = (root / 'union-find-baseline.ll').read_text()
name = '@"my.row_union_find::find"'
start = text.index('define internal { i64, ptr } '+name)
end = text.index('\n}\n', start)+3
original = text[start:end]
body = original.replace('define internal { i64, ptr } '+name, 'define internal i64 @"my.row_union_find::find_scalar"')
body = re.sub(r'  %rm\.9 = insertvalue.*\n  %v70 = insertvalue.*\n  ret \{ i64, ptr \} %v70', '  ret i64 %v4', body)
body = re.sub(r'  %rc\.27 = load.*\n  %v72 = icmp.*\n  br i1 %v72, label %b15, label %b16', '  br label %b15', body)
body = body.replace('  %v78 = phi ptr [ %v3, %b12 ], [ %v75, %b16.46 ]', '  %v78 = getelementptr inbounds i8, ptr %v3, i64 0')
body = body[:body.index('\nb16:')]+'\n}'
wrapper = '''
define internal { i64, ptr } @"my.row_union_find::find"(ptr %input, i64 %x) alwaysinline nounwind {
entry:
  %count = load i32, ptr %input, align 8
  %unique = icmp eq i32 %count, 1
  br i1 %unique, label %ready, label %detach
detach:
  %copied = call ptr @myl_core_list_copy(ptr %input, i64 8)
  call void @myl_core_release(ptr %input)
  br label %ready
ready:
  %parent = phi ptr [ %input, %entry ], [ %copied, %detach ]
  %root = call i64 @"my.row_union_find::find_scalar"(ptr %parent, i64 %x)
  %one = insertvalue { i64, ptr } poison, i64 %root, 0
  %both = insertvalue { i64, ptr } %one, ptr %parent, 1
  ret { i64, ptr } %both
}
'''
(root/'union-find-cheaper-return.ll').write_text(text[:start]+body+'\n'+wrapper+text[end:])
