export function l $myl_f_0b5b0c24ddddb193a115c6cacf83410e46d60453431effc245241a64d30eed3b(l %ctx, l %a0, l %a1, l %a2, l %a3, l %a4) {
@entry
 %trap =l add %ctx, 32
 %l0 =l alloc8 8
 %l1 =l alloc8 8
 %l2 =l alloc8 8
 %l3 =l alloc8 8
 %l4 =l alloc8 8
 %l5 =l alloc8 8
 %l6 =l alloc8 8
 %l7 =l alloc8 24
 %l8 =l alloc8 8
 %l9 =l alloc8 16
 %l10 =l alloc8 8
 %l11 =l alloc8 56
 %l12 =l alloc8 8
 %s0 =l alloc8 8
 %s1 =l alloc8 8
 %s2 =l alloc8 8
 %s3 =l alloc8 8
 %root0 =l alloc8 32
 %root1 =l alloc8 32
 %root2 =l alloc8 32
 %agg33 =l alloc8 16
 %agg35 =l alloc8 24
 %agg36 =l alloc8 56
 %agg52 =l alloc8 56
 jmp @frameadmit0
@frameadmit0
 %v3 =l alloc8 8
 %v4 =l add %ctx, 64
 %v5 =l loadl %v4
 %v6 =l cultl %v3, %v5
 jnz %v6, @floorfail2, @stackadmit1
@floorfail2
 dbgloc 1, 1
 call $myl_qbe_fail_frame(l %ctx)
 hlt
@stackadmit1
 storel 0, %l5
 dbgloc 1
 call $memset(l %l7, w 0, l 24)
 dbgloc 1
 call $memset(l %l9, w 0, l 16)
 storel 0, %l10
 dbgloc 1
 call $memset(l %l11, w 0, l 56)
 storel %a0, %l0
 storel %a1, %l1
 storel %a2, %l2
 storel %a3, %l3
 storel %a4, %l4
 dbgloc 1
 %heap =l call $myl_qbe_heap(l %ctx)
 dbgloc 1
 %root_mark =l call $myl_qbe_root_mark(l %ctx)
 jmp @i0
@i0
 %v7 =l loadl %l0
 storel %v7, %s0
 %v8 =l loadl %s0
 storel %v8, %l5
 %v9 =l loadl %l1
 storel %v9, %s0
 %v10 =l loadl %s0
 storel %v10, %l6
 %v11 =l loadl %l6
 storel %v11, %s0
 storel 0, %s1
 %v12 =l loadl %s1
 %v13 =l loadl %s0
 %v14 =l csltl %v13, %v12
 storel %v14, %s0
 %v15 =l loadl %s0
 jnz %v15, @next16, @i13
@next16
 %v16 =l loadl %l5
 # myl-obj %v16
 %v18 =l add %v16, 0
 %v17 =l loadl %v18
 storel %v17, %s0
 %v19 =l loadl %s0
 %v20 =l cugtl %v19, 9223372036854775807
 jnz %v20, @cast_overflow21, @cast_ok21
@cast_overflow21
 dbgloc 10
 call $myl_qbe_fail_cast(l %ctx, l %v19, l 320)
 hlt
@cast_ok21
 storel %v19, %s0
 %v22 =l loadl %l6
 storel %v22, %s1
 %v23 =l loadl %s1
 %v24 =l loadl %s0
 %v25 =l add %v24, %v23
 %v27 =l xor %v24, %v25
 %v28 =l xor %v23, %v25
 %v29 =l and %v27, %v28
 %v26 =l csltl %v29, 0
 jnz %v26, @overflow25, @checked25
@overflow25
 dbgloc 12
 call $myl_qbe_fail_overflow_op(l %ctx, l 0, l %v24, l %v23, l 64)
 hlt
@checked25
 storel %v25, %s0
 %v30 =l loadl %s0
 storel %v30, %l6
@i13
 %v31 =l loadl %l6
 storel %v31, %s0
 %v32 =l loadl %l5
 # myl-obj %v32
 %v34 =l loadl %s0
 # myl-obj %v32
 %v35 =l loadl %v32
 %v36 =l cultl %v34, %v35
 jnz %v36, @success37, @failed37
@failed37
 dbgloc 15
 call $myl_qbe_fail_normalized_index_bounds(l %ctx, l %v34, l %v35)
 hlt
@success37
 # myl-obj %v32
 %v40 =l add %v32, 32
 %v41 =l loadl %v40
 # myl-elem %v41 56v
 %v38 =l mul %v34, 56
 %v39 =l add %v41, %v38
 storel %v39, %s0
 %v42 =l loadl %s0
 %v43 =l loaduw %v42
 %v44 =l ceql %v43, 0
 jnz %v44, @arm44, @armnext44
@arm44
 jmp @i58
@armnext44
 %v45 =l ceql %v43, 1
 jnz %v45, @arm45, @armnext45
@arm45
 jmp @i61
@armnext45
 %v46 =l ceql %v43, 2
 jnz %v46, @arm46, @armnext46
@arm46
 jmp @i64
@armnext46
 %v47 =l ceql %v43, 3
 jnz %v47, @arm47, @armnext47
@arm47
 jmp @i67
@armnext47
 %v48 =l ceql %v43, 4
 jnz %v48, @arm48, @armnext48
@arm48
 jmp @i70
@armnext48
 %v49 =l ceql %v43, 5
 jnz %v49, @arm49, @armnext49
@arm49
 jmp @i73
@armnext49
 %v50 =l ceql %v43, 6
 jnz %v50, @arm50, @armnext50
@arm50
 jmp @i76
@armnext50
 %v51 =l ceql %v43, 7
 jnz %v51, @arm51, @armnext51
@arm51
 %v52 =l add %v42, 8
 blit %v52, %l7, 24
 jmp @i16
@armnext51
 %v53 =l ceql %v43, 8
 jnz %v53, @arm53, @armnext53
@arm53
 jmp @i79
@armnext53
 %v54 =l ceql %v43, 9
 jnz %v54, @arm54, @armnext54
@arm54
 jmp @i82
@armnext54
 %v55 =l ceql %v43, 10
 jnz %v55, @arm55, @armnext55
@arm55
 jmp @i85
@armnext55
 jmp @failure
@i16
 storel %l7, %s0
 storel %l7, %s0
 %v56 =l loadl %s0
 %v57 =l add %v56, 0
 %v58 =l loadl %v57
 storel %v58, %s0
 %v59 =l loadl %s0
 storel %v59, %l8
 storel %l7, %s0
 %v60 =l loadl %s0
 %v61 =l add %v60, 8
 storel %v61, %s0
 %v62 =l loadl %s0
 blit %v62, %l9, 16
 storel %l9, %s0
 %v63 =l loadl %l2
 storel %v63, %s1
 %v64 =l loadl %l3
 storel %v64, %s2
 %v65 =l loadl %l4
 storel %v65, %s3
 %v71 =l add %heap, 16
 %v72 =l loadl %v71
 storel %v72, %root0
 %v73 =l add %root0, 8
 %v75 =l loadl %l0
 %v76 =l add %root0, 24
 storel %v75, %v76
 storel %v76, %v73
 %v74 =l add %root0, 16
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v74
 storel %root0, %v71
 storel %root0, %root1
 %v77 =l add %root1, 8
 storel %l9, %v77
 %v78 =l add %root1, 16
 storel extern $myl_t_81d71c98b196ce876b8748e8f5e1c439a764a7854aeb5e4ef7865d0716f2ecef, %v78
 storel %root1, %v71
 %v79 =l loadl %s0
 storel %root1, %root2
 %v80 =l add %root2, 8
 storel %v79, %v80
 %v81 =l add %root2, 16
 storel extern $myl_t_81d71c98b196ce876b8748e8f5e1c439a764a7854aeb5e4ef7865d0716f2ecef, %v81
 storel %root2, %v71
 %v66 =l loadl %s0
 %v67 =l loadl %s1
 %v68 =l loadl %s2
 %v69 =l loadl %s3
 dbgloc 31
 %v70 =l call $myl_f_72cbd8b3ebb02b19d0384fb691061873bba08de6d559f9babec1767adabac444(l %ctx, l %v66, l %v67, l %v68, l %v69)
 storel %v70, %s0
 %v82 =l add %heap, 16
 storel %root_mark, %v82
 %v83 =l loadl %l8
 storel %v83, %s0
 blit %l9, %agg33, 16
 storel %agg33, %s1
 %v84 =l copy %agg35
 %v85 =l add %v84, 0
 %v86 =l loadl %s0
 storel %v86, %v85
 %v87 =l add %v84, 8
 %v88 =l loadl %s1
 blit %v88, %v87, 16
 storel %v84, %s0
 %v89 =l copy %agg36
 storew 7, %v89
 %v90 =l add %v89, 8
 %v91 =l loadl %s0
 blit %v91, %v90, 24
 storel %v89, %s0
 %v92 =l loadl %s0
 blit %v92, %l11, 56
 %v93 =l loadl %l0
 storel %v93, %s0
 %v94 =l loadl %s0
 storel %v94, %l10
 %v95 =l loadl %l1
 storel %v95, %s0
 %v96 =l loadl %s0
 storel %v96, %l12
 %v97 =l loadl %l12
 storel %v97, %s0
 storel 0, %s1
 %v98 =l loadl %s1
 %v99 =l loadl %s0
 %v100 =l csltl %v99, %v98
 storel %v100, %s0
 %v101 =l loadl %s0
 jnz %v101, @next102, @i51
@next102
 %v102 =l loadl %l10
 # myl-obj %v102
 %v104 =l add %v102, 0
 %v103 =l loadl %v104
 storel %v103, %s0
 %v105 =l loadl %s0
 %v106 =l cugtl %v105, 9223372036854775807
 jnz %v106, @cast_overflow107, @cast_ok107
@cast_overflow107
 dbgloc 48
 call $myl_qbe_fail_cast(l %ctx, l %v105, l 320)
 hlt
@cast_ok107
 storel %v105, %s0
 %v108 =l loadl %l12
 storel %v108, %s1
 %v109 =l loadl %s1
 %v110 =l loadl %s0
 %v111 =l add %v110, %v109
 %v113 =l xor %v110, %v111
 %v114 =l xor %v109, %v111
 %v115 =l and %v113, %v114
 %v112 =l csltl %v115, 0
 jnz %v112, @overflow111, @checked111
@overflow111
 dbgloc 50
 call $myl_qbe_fail_overflow_op(l %ctx, l 0, l %v110, l %v109, l 64)
 hlt
@checked111
 storel %v111, %s0
 %v116 =l loadl %s0
 storel %v116, %l12
@i51
 %v117 =l loadl %l12
 storel %v117, %s0
 blit %l11, %agg52, 56
 storel %agg52, %s1
 %v118 =l loadl %l10
 # myl-obj %v118
 %v120 =l loadl %s1
 %v121 =l loadl %s0
 # myl-obj %v118
 %v122 =l loadl %v118
 %v123 =l cultl %v121, %v122
 jnz %v123, @success124, @failed124
@failed124
 dbgloc 55
 call $myl_qbe_fail_normalized_index_bounds(l %ctx, l %v121, l %v122)
 hlt
@success124
 # myl-obj %v118
 %v127 =l add %v118, 32
 %v128 =l loadl %v127
 # myl-elem %v128 56v
 %v125 =l mul %v121, 56
 %v126 =l add %v128, %v125
 %v129 =l loadl %s1
 blit %v129, %v126, 56
 storel 0, %s0
 dbgloc 57
 call $memset(l %l7, w 0, l 24)
 jmp @i88
@i58
 storel 0, %s0
 %v130 =l loadl %s0
 jnz %v130, @success131, @failed131
@failed131
 dbgloc 60
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success131
 jmp @i88
@i61
 storel 0, %s0
 %v132 =l loadl %s0
 jnz %v132, @success133, @failed133
@failed133
 dbgloc 63
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success133
 jmp @i88
@i64
 storel 0, %s0
 %v134 =l loadl %s0
 jnz %v134, @success135, @failed135
@failed135
 dbgloc 66
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success135
 jmp @i88
@i67
 storel 0, %s0
 %v136 =l loadl %s0
 jnz %v136, @success137, @failed137
@failed137
 dbgloc 69
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success137
 jmp @i88
@i70
 storel 0, %s0
 %v138 =l loadl %s0
 jnz %v138, @success139, @failed139
@failed139
 dbgloc 72
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success139
 jmp @i88
@i73
 storel 0, %s0
 %v140 =l loadl %s0
 jnz %v140, @success141, @failed141
@failed141
 dbgloc 75
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success141
 jmp @i88
@i76
 storel 0, %s0
 %v142 =l loadl %s0
 jnz %v142, @success143, @failed143
@failed143
 dbgloc 78
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success143
 jmp @i88
@i79
 storel 0, %s0
 %v144 =l loadl %s0
 jnz %v144, @success145, @failed145
@failed145
 dbgloc 81
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success145
 jmp @i88
@i82
 storel 0, %s0
 %v146 =l loadl %s0
 jnz %v146, @success147, @failed147
@failed147
 dbgloc 84
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success147
 jmp @i88
@i85
 storel 0, %s0
 %v148 =l loadl %s0
 jnz %v148, @success149, @failed149
@failed149
 dbgloc 87
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success149
 jmp @i88
@i88
 storel 0, %s0
 %v150 =l loadl %s0
 ret %v150
@failure
 %v151 =l add %heap, 16
 storel %root_mark, %v151
 ret 0
@entry_failure
 ret 0
}