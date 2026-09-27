export function l $myl_f_1c0bd1b7bb117cc78f49bded6cea445b0f0085cd72c106cf259efd77a43b555f(l %ctx, l %a0, l %a1, l %a2, l %a3, l %a4) {
@entry
 %trap =l add %ctx, 32
 %l0 =l alloc8 8
 %l1 =l alloc8 8
 %l2 =l alloc8 8
 %l3 =l alloc8 8
 %l4 =l alloc8 8
 %l5 =l alloc8 8
 %l7 =l alloc8 8
 %s0 =l alloc8 8
 %s1 =l alloc8 8
 %s2 =l alloc8 8
 %s3 =l alloc8 8
 %s4 =l alloc8 8
 %root0 =l alloc8 32
 %root1 =l alloc8 32
 %root2 =l alloc8 32
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
 storel 0, %l7
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
 %v9 =l add %v8, 0
 %v10 =l loadl %v9
 storel %v10, %s0
 %v11 =l loadl %s0
 storel %v11, %l5
 %v13 =l loadl %l5
 dbgloc 5
 call $myl_native_cow_tally(w 1)
 %v14 =l sub %v13, 16
 %v15 =l loadl %v14
 %v16 =l shr %v15, 61
 %v16 =l and %v16, 1
 jnz %v16, @cowcopy12, @cowkeep12
@cowcopy12
 %v17 =l add %heap, 16
 %v18 =l loadl %v17
 %v19 =l loadl %l0
 storel %v18, %root0
 %v20 =l add %root0, 8
 storel %v19, %v20
 %v21 =l add %root0, 16
 storel extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, %v21
 storel %root0, %v17
 storel %root0, %root1
 %v22 =l add %root1, 8
 %v24 =l loadl %l5
 %v25 =l add %root1, 24
 storel %v24, %v25
 storel %v25, %v22
 %v23 =l add %root1, 16
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v23
 storel %root1, %v17
 dbgloc 5
 %v26 =l call $myl_native_cow_unique(l %heap, l %v13)
 %v27 =l add %heap, 16
 storel %root_mark, %v27
 jnz %v26, @success28, @failed28
@failed28
 dbgloc 5
 call $myl_qbe_fail_allocation(l %ctx)
 hlt
@success28
 storel %v26, %l5
@cowkeep12
 %v29 =l loadl %l5
 storel %v29, %s0
 %v30 =l loadl %l1
 storel %v30, %s1
 %v31 =l loadl %l2
 storel %v31, %s2
 %v32 =l loadl %l3
 storel %v32, %s3
 %v33 =l loadl %l4
 storel %v33, %s4
 %v54 =l add %heap, 16
 %v55 =l loadl %v54
 %v56 =l loadl %l0
 storel %v55, %root0
 %v57 =l add %root0, 8
 storel %v56, %v57
 %v58 =l add %root0, 16
 storel extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, %v58
 storel %root0, %v54
 storel %root0, %root1
 %v59 =l add %root1, 8
 %v61 =l loadl %l5
 %v62 =l add %root1, 24
 storel %v61, %v62
 storel %v62, %v59
 %v60 =l add %root1, 16
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v60
 storel %root1, %v54
 storel %root1, %root2
 %v63 =l add %root2, 8
 %v65 =l loadl %s0
 %v66 =l add %root2, 24
 storel %v65, %v66
 storel %v66, %v63
 %v64 =l add %root2, 16
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v64
 storel %root2, %v54
 %v34 =l loadl %s0
 %v35 =l loadl %s1
 %v36 =l loadl %s2
 %v37 =l loadl %s3
 %v38 =l loadl %s4
 dbgloc 10
 call $myl_native_cow_tally(w 1)
 %v40 =l sub %v34, 16
 %v41 =l loadl %v40
 %v42 =l shr %v41, 61
 %v42 =l and %v42, 1
 jnz %v42, @cowcopy39, @cowkeep39
@cowcopy39
 dbgloc 10
 %v43 =l call $myl_native_cow_unique(l %heap, l %v34)
 jnz %v43, @success44, @failed44
@failed44
 dbgloc 10
 call $myl_qbe_fail_allocation(l %ctx)
 hlt
@success44
 storel %v43, %l5
 storel %v43, %s0
@cowkeep39
 %v45 =l loadl %s0
 dbgloc 10
 call $myl_native_cow_tally(w 3)
 %v46 =l sub %v45, 16
 %v47 =l loadl %v46
 %v48 =l and %v47, 1152921504606846976
 %v49 =l or %v47, 1152921504606846976
 storel %v49, %v46
 %v48 =l cnel %v48, 0
 dbgloc 10
 %v50 =l call $myl_f_0b5b0c24ddddb193a115c6cacf83410e46d60453431effc245241a64d30eed3b(l %ctx, l %v45, l %v35, l %v36, l %v37, l %v38)
 jnz %v48, @pinned51, @unpin51
@unpin51
 %v52 =l loadl %v46
 %v53 =l and %v52, -1152921504606846977
 storel %v53, %v46
@pinned51
 storel %v50, %s0
 %v67 =l add %heap, 16
 storel %root_mark, %v67
 %v68 =l loadl %l5
 storel %v68, %s0
 %v69 =l loadl %s0
 storel %v69, %l7
 %v70 =l loadl %l0
 storel %v70, %s0
 %v71 =l loadl %l0
 storel %v71, %s0
 %v72 =l loadl %l0
 storel %v72, %s0
 %v73 =l loadl %l7
 storel %v73, %s1
 %v74 =l loadl %s0
 %v75 =l add %v74, 0
 %v76 =l loadl %s1
 storel %v76, %v75
 storel %v74, %s0
 storel 0, %s0
 storel 0, %s0
 %v77 =l loadl %s0
 ret %v77
@failure
 %v78 =l add %heap, 16
 storel %root_mark, %v78
 ret 0
@entry_failure
 ret 0
}