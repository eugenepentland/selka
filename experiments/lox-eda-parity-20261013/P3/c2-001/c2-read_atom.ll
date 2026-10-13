define internal fastcc void @"my.sexpr_tokenizer::read_atom"(ptr noalias sret([96 x i8]) align 8 %ret, ptr %p0, ptr noalias align 8 %p1, { i64, i64, i64 } %p2) nounwind uwtable !dbg !1014261 {
entry:
  %slot = alloca i64, align 8
  %v6 = getelementptr inbounds i8, ptr %p1, i64 0
  %v10 = getelementptr inbounds i8, ptr %p1, i64 0
  br label %b0
b0:
  %v3 = load i64, ptr %p1, align 8, !tbaa !7
  br label %b1
b1:
  %v7 = notail call fastcc i64 @"my.sexpr_tokenizer::peek"(ptr %p0, ptr %v6), !dbg !1014263
  %v8 = notail call fastcc i1 @"my.sexpr_tokenizer::is_atom_continue"(i64 %v7), !dbg !1014265
  br i1 %v8, label %b2, label %b4
b2:
  notail call fastcc void @"my.sexpr_tokenizer::advance"(ptr %p0, ptr %v10), !dbg !1014267
  br label %b3
b3:
  br label %b1
b4:
  %v15 = load i64, ptr %v6, align 8, !tbaa !7
  store i64 2, ptr %ret, align 8, !tbaa !7
  %fp.1 = getelementptr inbounds i8, ptr %ret, i64 8
  store i64 %v3, ptr %fp.1, align 8, !tbaa !7
  %fp.2 = getelementptr inbounds i8, ptr %ret, i64 16
  store i64 %v15, ptr %fp.2, align 8, !tbaa !7
  %fp.3 = getelementptr inbounds i8, ptr %ret, i64 24
  %sf.4 = extractvalue { i64, i64, i64 } %p2, 0
  store i64 %sf.4, ptr %fp.3, align 8, !tbaa !7
  %sf.5 = extractvalue { i64, i64, i64 } %p2, 1
  %fp.6 = getelementptr inbounds i8, ptr %fp.3, i64 8
  store i64 %sf.5, ptr %fp.6, align 8, !tbaa !7
  %sf.7 = extractvalue { i64, i64, i64 } %p2, 2
  %fp.8 = getelementptr inbounds i8, ptr %fp.3, i64 16
  store i64 %sf.7, ptr %fp.8, align 8, !tbaa !7
  ret void
}
