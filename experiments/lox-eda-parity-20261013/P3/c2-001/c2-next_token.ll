define internal fastcc void @"my.sexpr_parser::next_token"(ptr noalias sret([136 x i8]) align 8 %ret, ptr %p0, ptr noalias align 8 %p1, { { i64, i64, i64 }, ptr } %p2) nounwind uwtable !dbg !1010104 {
entry:
  %slot = alloca i64, align 8
  %stack.1 = alloca [104 x i8], align 8
  %home.2 = getelementptr inbounds i8, ptr %ret, i64 8
  %v3 = getelementptr inbounds i8, ptr %stack.1, i64 0
  %v5 = getelementptr inbounds i8, ptr %p1, i64 0
  %v10 = getelementptr inbounds i8, ptr %home.2, i64 0
  br label %b0
b0:
  notail call fastcc void @"my.sexpr_tokenizer::next_offset"(ptr sret([104 x i8]) align 8 %v3, ptr %p0, ptr %v5), !dbg !1010106
  %v4 = getelementptr inbounds i8, ptr %v3, i64 0
  %t.3 = load i64, ptr %v4, align 8, !tbaa !7
  %v6 = trunc i64 %t.3 to i32
  %v8 = icmp eq i32 %v6, 0
  br i1 %v8, label %b2, label %b3
b2:
  %fp.4 = getelementptr inbounds i8, ptr %v4, i64 8
  call void @llvm.memcpy.p0.p0.i64(ptr %v10, ptr %fp.4, i64 48, i1 false)
  store i64 0, ptr %ret, align 8, !tbaa !7
  %fp.5 = getelementptr inbounds i8, ptr %ret, i64 104
  %sf.6 = extractvalue { { i64, i64, i64 }, ptr } %p2, 0
  %sf.7 = extractvalue { i64, i64, i64 } %sf.6, 0
  store i64 %sf.7, ptr %fp.5, align 8, !tbaa !7
  %sf.8 = extractvalue { i64, i64, i64 } %sf.6, 1
  %fp.9 = getelementptr inbounds i8, ptr %fp.5, i64 8
  store i64 %sf.8, ptr %fp.9, align 8, !tbaa !7
  %sf.10 = extractvalue { i64, i64, i64 } %sf.6, 2
  %fp.11 = getelementptr inbounds i8, ptr %fp.5, i64 16
  store i64 %sf.10, ptr %fp.11, align 8, !tbaa !7
  %sf.12 = extractvalue { { i64, i64, i64 }, ptr } %p2, 1
  %fp.13 = getelementptr inbounds i8, ptr %fp.5, i64 24
  store ptr %sf.12, ptr %fp.13, align 8, !tbaa !7
  ret void
b3:
  br label %b4
b4:
  %fp.14 = getelementptr inbounds i8, ptr %v4, i64 8
  %lt.15 = load i64, ptr %fp.14, align 8, !tbaa !7
  %lt.16 = trunc i64 %lt.15 to i8
  %v15 = insertvalue { i8, [0 x i64] } poison, i8 %lt.16, 0
  %fp.17 = getelementptr inbounds i8, ptr %fp.14, i64 8
  %v16 = notail call fastcc { i8, [0 x i64] } @"my.sexpr_parser::lex_error_to_parse"({ i8, [0 x i64] } %v15), !dbg !1010108
  %fp.18 = getelementptr inbounds i8, ptr %v5, i64 24
  %lf.19 = load i64, ptr %fp.18, align 8, !tbaa !7
  %lr.20 = insertvalue { i64, i64, i64 } poison, i64 %lf.19, 0
  %fp.22 = getelementptr inbounds i8, ptr %fp.18, i64 8
  %lf.21 = load i64, ptr %fp.22, align 8, !tbaa !7
  %lr.23 = insertvalue { i64, i64, i64 } %lr.20, i64 %lf.21, 1
  %fp.25 = getelementptr inbounds i8, ptr %fp.18, i64 16
  %lf.24 = load i64, ptr %fp.25, align 8, !tbaa !7
  %v17 = insertvalue { i64, i64, i64 } %lr.23, i64 %lf.24, 2
  %v18 = insertvalue { { i64, i64, i64 }, ptr } %p2, { i64, i64, i64 } %v17, 0
  %v19 = notail call fastcc ptr @"my.sexpr_parser::error_message"({ i8, [0 x i64] } %v16), !dbg !1010110
  %v25 = extractvalue { { i64, i64, i64 }, ptr } %v18, 1
  %v20 = insertvalue { { i64, i64, i64 }, ptr } %v18, ptr %v19, 1
  call void @myl_core_drop_owned(ptr %v25)
  call preserve_mostcc void @myl_core_err_trace_origin_preserve_most(ptr @myl.site.4414) #1
  store i64 1, ptr %ret, align 8, !tbaa !7
  %fp.26 = getelementptr inbounds i8, ptr %ret, i64 8
  %st.27 = extractvalue { i8, [0 x i64] } %v16, 0
  %st.28 = zext i8 %st.27 to i64
  store i64 %st.28, ptr %fp.26, align 8, !tbaa !7
  %fp.29 = getelementptr inbounds i8, ptr %fp.26, i64 8
  %fp.30 = getelementptr inbounds i8, ptr %ret, i64 104
  %sf.31 = extractvalue { { i64, i64, i64 }, ptr } %v20, 0
  %sf.32 = extractvalue { i64, i64, i64 } %sf.31, 0
  store i64 %sf.32, ptr %fp.30, align 8, !tbaa !7
  %sf.33 = extractvalue { i64, i64, i64 } %sf.31, 1
  %fp.34 = getelementptr inbounds i8, ptr %fp.30, i64 8
  store i64 %sf.33, ptr %fp.34, align 8, !tbaa !7
  %sf.35 = extractvalue { i64, i64, i64 } %sf.31, 2
  %fp.36 = getelementptr inbounds i8, ptr %fp.30, i64 16
  store i64 %sf.35, ptr %fp.36, align 8, !tbaa !7
  %sf.37 = extractvalue { { i64, i64, i64 }, ptr } %v20, 1
  %fp.38 = getelementptr inbounds i8, ptr %fp.30, i64 24
  store ptr %sf.37, ptr %fp.38, align 8, !tbaa !7
  ret void
}
