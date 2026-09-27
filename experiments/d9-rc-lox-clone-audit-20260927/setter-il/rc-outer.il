export function l $myl_f_1c0bd1b7bb117cc78f49bded6cea445b0f0085cd72c106cf259efd77a43b555f(l %ctx, l %a0, l %a1, l %a2, l %a3, l %a4) {
@entry
 %trap =l add %ctx, 32
 %rcframe =l alloc8 32
 %rcentries =l alloc8 256
 %rcguards =l alloc8 64
 %rcs0 =l alloc8 208
 %rcs1 =l alloc8 8
 %rcwork =l alloc8 208
 %rcinternal =l alloc8 8
 %rccall =l alloc8 32
 %rcborrow7 =l alloc8 32
 dbgloc 1
 call $memset(l %rcborrow7, w 0, l 32)
 %l0 =l alloc8 8
 %l1 =l alloc8 8
 %l2 =l alloc8 8
 %l3 =l alloc8 8
 %l4 =l alloc8 8
 %l5 =l alloc8 8
 %l6 =l alloc8 208
 %l7 =l alloc8 8
 %s0 =l alloc8 8
 %s1 =l alloc8 8
 %s2 =l alloc8 8
 %s3 =l alloc8 8
 %s4 =l alloc8 8
 %agg20 =l alloc8 208
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
 storel 0, %l7
 storel %a0, %l0
 storel %a1, %l1
 storel %a2, %l2
 storel %a3, %l3
 storel %a4, %l4
 dbgloc 1
 %heap =l call $myl_qbe_heap(l %ctx)
 dbgloc 1
 %rcregion =l call $myl_qbe_region_mark(l %ctx)
 dbgloc 1
 call $memset(l %rcguards, w 0, l 64)
 %v7 =l loadl %l0
 %v8 =l add %rcentries, 0
 storel extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, %v8
 %v9 =l add %v8, 24
 storew 2, %v9
 %v10 =l add %v8, 8
 storel %v7, %v10
 %v11 =l add %v8, 16
 %v12 =l add %rcguards, 0
 storel %v12, %v11
 %v13 =l copy %l5
 %v14 =l add %rcentries, 32
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v14
 %v15 =l add %v14, 24
 storew 2, %v15
 %v16 =l add %v14, 8
 storel %v13, %v16
 %v17 =l add %v14, 16
 %v18 =l add %rcguards, 8
 storel %v18, %v17
 %v19 =l copy %l6
 %v20 =l add %rcentries, 64
 storel extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, %v20
 %v21 =l add %v20, 24
 storew 2, %v21
 %v22 =l add %v20, 8
 storel %v19, %v22
 %v23 =l add %v20, 16
 %v24 =l add %rcguards, 16
 storel %v24, %v23
 %v25 =l copy %l7
 %v26 =l add %rcentries, 96
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v26
 %v27 =l add %v26, 24
 storew 2, %v27
 %v28 =l add %v26, 8
 storel %v25, %v28
 %v29 =l add %v26, 16
 %v30 =l add %rcguards, 24
 storel %v30, %v29
 %v31 =l copy %rcs0
 %v32 =l add %rcentries, 128
 storel extern $myl_t_385cfdbc00ec32031699460779c15099b2bba3cad0e440fffb08e10df0acb9e1, %v32
 %v33 =l add %v32, 24
 storew 0, %v33
 %v34 =l add %v32, 8
 storel %v31, %v34
 %v35 =l add %v32, 16
 %v36 =l add %rcguards, 32
 storel %v36, %v35
 %v37 =l copy %rcs1
 %v38 =l add %rcentries, 160
 storel extern $myl_t_385cfdbc00ec32031699460779c15099b2bba3cad0e440fffb08e10df0acb9e1, %v38
 %v39 =l add %v38, 24
 storew 0, %v39
 %v40 =l add %v38, 8
 storel %v37, %v40
 %v41 =l add %v38, 16
 %v42 =l add %rcguards, 40
 storel %v42, %v41
 %v43 =l copy %rcwork
 %v44 =l add %rcentries, 192
 storel extern $myl_t_385cfdbc00ec32031699460779c15099b2bba3cad0e440fffb08e10df0acb9e1, %v44
 %v45 =l add %v44, 24
 storew 0, %v45
 %v46 =l add %v44, 8
 storel %v43, %v46
 %v47 =l add %v44, 16
 %v48 =l add %rcguards, 48
 storel %v48, %v47
 %v49 =l copy %rcinternal
 %v50 =l add %rcentries, 224
 storel extern $myl_t_385cfdbc00ec32031699460779c15099b2bba3cad0e440fffb08e10df0acb9e1, %v50
 %v51 =l add %v50, 24
 storew 0, %v51
 %v52 =l add %v50, 8
 storel %v49, %v52
 %v53 =l add %v50, 16
 %v54 =l add %rcguards, 56
 storel %v54, %v53
 dbgloc 1
 call $myl_qbe_rc_frame_enter(l %ctx, l %rcframe, l %rcentries, l 8)
 jmp @i0
@i0
 %v55 =l loadl %l0
 storel %v55, %s0
 %v56 =l loadl %s0
 %v57 =l add %v56, 0
 %v58 =l loadl %v57
 storel %v58, %s0
 %v59 =l copy %s0
 dbgloc 2
 %v60 =w call $myl_rc_native_loan(l %heap, l extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, l %rcwork, l %v59)
 jnz %v60, @rcsuccess61, @rcfailure61
@rcfailure61
 dbgloc 2
 %v62 =w call $myl_rc_take_failure(l %heap)
 dbgloc 2
 %v63 =w call $myl_qbe_rc_status(l %ctx, w %v62)
 jmp @failure
@rcsuccess61
 %v64 =l add %rcentries, 192
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v64
 %v65 =l add %v64, 24
 storew 2, %v65
 %v66 =l add %rcentries, 216
 storew 16, %v66
 %v67 =l add %rcguards, 48
 storew 1, %v67
 %v70 =l add %rcguards, 32
 %v68 =w loaduw %v70
 jnz %v68, @rcslotdrop69, @rcslotdone69
@rcslotdrop69
 %v71 =l add %rcentries, 128
 dbgloc 2
 call $myl_qbe_rc_slot_drop(l %ctx, l %v71)
@rcslotdone69
 %v72 =l copy %rcs0
 %v73 =l copy %rcwork
 blit %v73, %v72, 8
 %v74 =l add %rcentries, 128
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v74
 %v75 =l add %v74, 24
 storew 2, %v75
 %v77 =l add %rcentries, 216
 %v78 =l add %rcentries, 152
 %v76 =w loaduw %v77
 storew %v76, %v78
 %v79 =l add %rcguards, 48
 storew 0, %v79
 %v80 =l add %rcguards, 32
 storew 1, %v80
 %v81 =l loadl %v72
 storel %v81, %s0
 %v82 =l copy %s0
 %v88 =l add %rcguards, 32
 %v89 =l add %rcentries, 152
 %v84 =w loaduw %v88
 %v85 =w loaduw %v89
 %v85 =w and %v85, 24
 %v86 =w ceqw %v85, 0
 %v87 =w and %v84, %v86
 jnz %v87, @rctake83, @rccopy83
@rctake83
 %v90 =l copy %rcwork
 %v91 =l copy %rcregion
 %v93 =l sub %v82, %v90
 %v94 =l sub %v90, %v82
 %v95 =w cultl %v93, 8
 %v96 =w cultl %v94, 8
 %v97 =w or %v95, %v96
 jnz %v97, @rcmoveslow92, @rcmovecheck92
@rcmovecheck92
 %v101 =l add %v82, 0
 %v98 =l loadl %v101
 %v99 =w cnel %v98, 0
 jnz %v99, @rcmoveheader100, @rcmovenext100
@rcmoveheader100
 %v102 =l sub %v98, 16
 %v103 =l loadl %v102
 %v104 =l and %v103, 5764607523034234881
 %v105 =w cnel %v104, 0
 jnz %v105, @rcmoveslow92, @rcmovenext100
@rcmovenext100
 blit %v82, %v90, 8
 dbgloc 4
 call $memset(l %v82, w 0, l 8)
 jmp @rcmoved92
@rcmoveslow92
 dbgloc 4
 %v106 =w call $myl_rc_native_take(l %heap, l extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, l %v90, l %v82, w %v91)
 jnz %v106, @rcsuccess107, @rcfailure107
@rcfailure107
 dbgloc 4
 %v108 =w call $myl_rc_take_failure(l %heap)
 dbgloc 4
 %v109 =w call $myl_qbe_rc_status(l %ctx, w %v108)
 jmp @failure
@rcsuccess107
@rcmoved92
 %v110 =l add %rcguards, 32
 storew 0, %v110
 %v111 =l add %rcentries, 192
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v111
 %v112 =l add %v111, 24
 storew 2, %v112
 %v113 =l add %rcguards, 48
 storew 1, %v113
 jmp @rcprepared83
@rccopy83
 %v114 =l copy %rcwork
 %v115 =l copy %rcregion
 dbgloc 4
 %v116 =w call $myl_rc_native_retain(l %heap, l extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, l %v114, l %v82, w %v115)
 jnz %v116, @rcsuccess117, @rcfailure117
@rcfailure117
 dbgloc 4
 %v118 =w call $myl_rc_take_failure(l %heap)
 dbgloc 4
 %v119 =w call $myl_qbe_rc_status(l %ctx, w %v118)
 jmp @failure
@rcsuccess117
 %v120 =l add %rcentries, 192
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v120
 %v121 =l add %v120, 24
 storew 2, %v121
 %v122 =l add %rcguards, 48
 storew 1, %v122
 %v125 =l add %rcguards, 32
 %v123 =w loaduw %v125
 jnz %v123, @rcslotdrop124, @rcslotdone124
@rcslotdrop124
 %v126 =l add %rcentries, 128
 dbgloc 4
 call $myl_qbe_rc_slot_drop(l %ctx, l %v126)
@rcslotdone124
@rcprepared83
 %v130 =l add %rcguards, 8
 %v128 =w loaduw %v130
 jnz %v128, @rcslotdrop129, @rcslotdone129
@rcslotdrop129
 %v131 =l add %rcentries, 32
 dbgloc 4
 call $myl_qbe_rc_slot_drop(l %ctx, l %v131)
@rcslotdone129
 %v127 =l copy %l5
 %v132 =l copy %rcwork
 blit %v132, %v127, 8
 %v133 =l add %rcguards, 48
 storew 0, %v133
 %v134 =l add %rcentries, 32
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v134
 %v135 =l add %v134, 24
 storew 2, %v135
 %v136 =l add %v134, 8
 storel %v127, %v136
 %v137 =l add %v134, 16
 %v138 =l add %rcguards, 8
 storel %v138, %v137
 %v140 =l add %rcentries, 216
 %v141 =l add %rcentries, 56
 %v139 =w loaduw %v140
 storew %v139, %v141
 %v142 =l add %rcguards, 8
 storew 1, %v142
 %v144 =l add %rcguards, 8
 %v143 =l copy %l5
 %v147 =l add %rcentries, 32
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v147
 %v148 =l add %v147, 24
 storew 2, %v148
 %v149 =l add %v147, 8
 storel %v143, %v149
 %v150 =l add %v147, 16
 %v151 =l add %rcguards, 8
 storel %v151, %v150
 dbgloc 5
 %v146 =w call $myl_qbe_rc_unique_local(l %ctx, l extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, l %v143, l %v144)
 jnz %v146, @rcunique152, @failure
@rcunique152
 %v153 =l loadl %l5
 storel %v153, %s0
 %v154 =l loadl %l1
 storel %v154, %s1
 %v155 =l loadl %l2
 storel %v155, %s2
 %v156 =l loadl %l3
 storel %v156, %s3
 %v157 =l loadl %l4
 storel %v157, %s4
 %v158 =l loadl %s0
 %v159 =l loadl %s1
 %v160 =l loadl %s2
 %v161 =l loadl %s3
 %v162 =l loadl %s4
 %v163 =l copy %rccall
 dbgloc 10
 call $myl_qbe_rc_scope_begin(l %ctx, l %v163)
 %v166 =l add %rcguards, 32
 %v164 =w loaduw %v166
 jnz %v164, @rcslotdrop165, @rcslotdone165
@rcslotdrop165
 %v167 =l add %rcentries, 128
 dbgloc 10
 call $myl_qbe_rc_slot_drop(l %ctx, l %v167)
@rcslotdone165
 %v169 =l add %rcguards, 8
 %v168 =l copy %l5
 %v172 =l add %rcentries, 32
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v172
 %v173 =l add %v172, 24
 storew 2, %v173
 %v174 =l add %v172, 8
 storel %v168, %v174
 %v175 =l add %v172, 16
 %v176 =l add %rcguards, 8
 storel %v176, %v175
 dbgloc 10
 %v171 =w call $myl_qbe_rc_unique_local(l %ctx, l extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, l %v168, l %v169)
 jnz %v171, @rcunique177, @failure
@rcunique177
 %v178 =l loadl %l5
 storel %v178, %s0
 %v179 =l loadl %s0
 dbgloc 10
 %v180 =w call $myl_qbe_rc_scope_pin(l %ctx, l %v163, l %v179)
 jnz %v180, @rcunique181, @failure
@rcunique181
 dbgloc 10
 %v182 =l call $myl_f_0b5b0c24ddddb193a115c6cacf83410e46d60453431effc245241a64d30eed3b(l %ctx, l %v179, l %v159, l %v160, l %v161, l %v162)
 dbgloc 10
 call $myl_qbe_rc_scope_end(l %ctx, l %v163)
 storel %v182, %s0
 %v185 =l add %rcguards, 32
 %v183 =w loaduw %v185
 jnz %v183, @rcslotdrop184, @rcslotdone184
@rcslotdrop184
 %v186 =l add %rcentries, 128
 dbgloc 10
 call $myl_qbe_rc_slot_drop(l %ctx, l %v186)
@rcslotdone184
 %v187 =l loadl %l5
 storel %v187, %s0
 %v188 =l copy %s0
 %v193 =l add %rcguards, 32
 %v194 =l add %rcentries, 152
 %v189 =w loaduw %v193
 %v190 =w loaduw %v194
 %v190 =w and %v190, 24
 %v191 =w ceqw %v190, 0
 %v192 =w and %v189, %v191
 jnz %v192, @rcprivateown195, @rcprivateloan195
@rcprivateown195
 %v196 =l copy %rcwork
 %v197 =l copy %rcregion
 %v199 =l sub %v188, %v196
 %v200 =l sub %v196, %v188
 %v201 =w cultl %v199, 8
 %v202 =w cultl %v200, 8
 %v203 =w or %v201, %v202
 jnz %v203, @rcmoveslow198, @rcmovecheck198
@rcmovecheck198
 %v207 =l add %v188, 0
 %v204 =l loadl %v207
 %v205 =w cnel %v204, 0
 jnz %v205, @rcmoveheader206, @rcmovenext206
@rcmoveheader206
 %v208 =l sub %v204, 16
 %v209 =l loadl %v208
 %v210 =l and %v209, 5764607523034234881
 %v211 =w cnel %v210, 0
 jnz %v211, @rcmoveslow198, @rcmovenext206
@rcmovenext206
 blit %v188, %v196, 8
 dbgloc 13
 call $memset(l %v188, w 0, l 8)
 jmp @rcmoved198
@rcmoveslow198
 dbgloc 13
 %v212 =w call $myl_rc_native_take(l %heap, l extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, l %v196, l %v188, w %v197)
 jnz %v212, @rcsuccess213, @rcfailure213
@rcfailure213
 dbgloc 13
 %v214 =w call $myl_rc_take_failure(l %heap)
 dbgloc 13
 %v215 =w call $myl_qbe_rc_status(l %ctx, w %v214)
 jmp @failure
@rcsuccess213
@rcmoved198
 %v216 =l add %rcguards, 32
 storew 0, %v216
 %v217 =l add %rcentries, 192
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v217
 %v218 =l add %v217, 24
 storew 2, %v218
 %v219 =l add %rcguards, 48
 storew 1, %v219
 jmp @rcprivateprepared195
@rcprivateloan195
 dbgloc 13
 %v220 =w call $myl_rc_native_loan(l %heap, l extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, l %rcwork, l %v188)
 jnz %v220, @rcsuccess221, @rcfailure221
@rcfailure221
 dbgloc 13
 %v222 =w call $myl_rc_take_failure(l %heap)
 dbgloc 13
 %v223 =w call $myl_qbe_rc_status(l %ctx, w %v222)
 jmp @failure
@rcsuccess221
 %v224 =l add %rcentries, 192
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v224
 %v225 =l add %v224, 24
 storew 2, %v225
 %v226 =l add %rcentries, 216
 storew 16, %v226
 %v227 =l add %rcguards, 48
 storew 1, %v227
 %v230 =l add %rcguards, 32
 %v228 =w loaduw %v230
 jnz %v228, @rcslotdrop229, @rcslotdone229
@rcslotdrop229
 %v231 =l add %rcentries, 128
 dbgloc 13
 call $myl_qbe_rc_slot_drop(l %ctx, l %v231)
@rcslotdone229
@rcprivateprepared195
 %v235 =l add %rcguards, 24
 %v233 =w loaduw %v235
 jnz %v233, @rcslotdrop234, @rcslotdone234
@rcslotdrop234
 %v236 =l add %rcentries, 96
 dbgloc 13
 call $myl_qbe_rc_slot_drop(l %ctx, l %v236)
@rcslotdone234
 %v232 =l copy %l7
 %v237 =l copy %rcwork
 blit %v237, %v232, 8
 %v238 =l add %rcguards, 48
 storew 0, %v238
 %v239 =l add %rcentries, 96
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v239
 %v240 =l add %v239, 24
 storew 2, %v240
 %v241 =l add %v239, 8
 storel %v232, %v241
 %v242 =l add %v239, 16
 %v243 =l add %rcguards, 24
 storel %v243, %v242
 %v245 =l add %rcentries, 216
 %v246 =l add %rcentries, 120
 %v244 =w loaduw %v245
 storew %v244, %v246
 %v247 =l add %rcguards, 24
 storew 1, %v247
 %v248 =l loadl %l0
 storel %v248, %s0
 %v249 =l loadl %s0
 %v254 =l add %rcguards, 32
 %v255 =l add %rcentries, 152
 %v250 =w loaduw %v254
 %v251 =w loaduw %v255
 %v251 =w and %v251, 24
 %v252 =w ceqw %v251, 0
 %v253 =w and %v250, %v252
 jnz %v253, @rcprivateown256, @rcprivateloan256
@rcprivateown256
 %v257 =l copy %rcwork
 %v258 =l copy %rcregion
 dbgloc 15
 %v259 =w call $myl_rc_native_take(l %heap, l extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, l %v257, l %v249, w %v258)
 jnz %v259, @rcsuccess260, @rcfailure260
@rcfailure260
 dbgloc 15
 %v261 =w call $myl_rc_take_failure(l %heap)
 dbgloc 15
 %v262 =w call $myl_qbe_rc_status(l %ctx, w %v261)
 jmp @failure
@rcsuccess260
 %v263 =l add %rcguards, 32
 storew 0, %v263
 %v264 =l add %rcentries, 192
 storel extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, %v264
 %v265 =l add %v264, 24
 storew 2, %v265
 %v266 =l add %rcguards, 48
 storew 1, %v266
 jmp @rcprivateprepared256
@rcprivateloan256
 dbgloc 15
 %v267 =w call $myl_rc_native_loan(l %heap, l extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, l %rcwork, l %v249)
 jnz %v267, @rcsuccess268, @rcfailure268
@rcfailure268
 dbgloc 15
 %v269 =w call $myl_rc_take_failure(l %heap)
 dbgloc 15
 %v270 =w call $myl_qbe_rc_status(l %ctx, w %v269)
 jmp @failure
@rcsuccess268
 %v271 =l add %rcentries, 192
 storel extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, %v271
 %v272 =l add %v271, 24
 storew 2, %v272
 %v273 =l add %rcentries, 216
 storew 16, %v273
 %v274 =l add %rcguards, 48
 storew 1, %v274
 %v277 =l add %rcguards, 32
 %v275 =w loaduw %v277
 jnz %v275, @rcslotdrop276, @rcslotdone276
@rcslotdrop276
 %v278 =l add %rcentries, 128
 dbgloc 15
 call $myl_qbe_rc_slot_drop(l %ctx, l %v278)
@rcslotdone276
@rcprivateprepared256
 %v282 =l add %rcguards, 16
 %v280 =w loaduw %v282
 jnz %v280, @rcslotdrop281, @rcslotdone281
@rcslotdrop281
 %v283 =l add %rcentries, 64
 dbgloc 15
 call $myl_qbe_rc_slot_drop(l %ctx, l %v283)
@rcslotdone281
 %v279 =l copy %l6
 %v284 =l copy %rcwork
 blit %v284, %v279, 208
 %v285 =l add %rcguards, 48
 storew 0, %v285
 %v286 =l add %rcentries, 64
 storel extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, %v286
 %v287 =l add %v286, 24
 storew 2, %v287
 %v288 =l add %v286, 8
 storel %v279, %v288
 %v289 =l add %v286, 16
 %v290 =l add %rcguards, 16
 storel %v290, %v289
 %v292 =l add %rcentries, 216
 %v293 =l add %rcentries, 88
 %v291 =w loaduw %v292
 storew %v291, %v293
 %v294 =l add %rcguards, 16
 storew 1, %v294
 %v295 =l loadl %l0
 storel %v295, %s0
 %v296 =l loadl %s0
 %v301 =l add %rcguards, 32
 %v302 =l add %rcentries, 152
 %v297 =w loaduw %v301
 %v298 =w loaduw %v302
 %v298 =w and %v298, 24
 %v299 =w ceqw %v298, 0
 %v300 =w and %v297, %v299
 jnz %v300, @rcprivateown303, @rcprivateloan303
@rcprivateown303
 %v304 =l copy %rcwork
 %v305 =l copy %rcregion
 dbgloc 17
 %v306 =w call $myl_rc_native_take(l %heap, l extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, l %v304, l %v296, w %v305)
 jnz %v306, @rcsuccess307, @rcfailure307
@rcfailure307
 dbgloc 17
 %v308 =w call $myl_rc_take_failure(l %heap)
 dbgloc 17
 %v309 =w call $myl_qbe_rc_status(l %ctx, w %v308)
 jmp @failure
@rcsuccess307
 %v310 =l add %rcguards, 32
 storew 0, %v310
 %v311 =l add %rcentries, 192
 storel extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, %v311
 %v312 =l add %v311, 24
 storew 2, %v312
 %v313 =l add %rcguards, 48
 storew 1, %v313
 jmp @rcprivateprepared303
@rcprivateloan303
 dbgloc 17
 %v314 =w call $myl_rc_native_loan(l %heap, l extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, l %rcwork, l %v296)
 jnz %v314, @rcsuccess315, @rcfailure315
@rcfailure315
 dbgloc 17
 %v316 =w call $myl_rc_take_failure(l %heap)
 dbgloc 17
 %v317 =w call $myl_qbe_rc_status(l %ctx, w %v316)
 jmp @failure
@rcsuccess315
 %v318 =l add %rcentries, 192
 storel extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, %v318
 %v319 =l add %v318, 24
 storew 2, %v319
 %v320 =l add %rcentries, 216
 storew 16, %v320
 %v321 =l add %rcguards, 48
 storew 1, %v321
 %v324 =l add %rcguards, 32
 %v322 =w loaduw %v324
 jnz %v322, @rcslotdrop323, @rcslotdone323
@rcslotdrop323
 %v325 =l add %rcentries, 128
 dbgloc 17
 call $myl_qbe_rc_slot_drop(l %ctx, l %v325)
@rcslotdone323
@rcprivateprepared303
 %v329 =l add %rcguards, 16
 %v327 =w loaduw %v329
 jnz %v327, @rcslotdrop328, @rcslotdone328
@rcslotdrop328
 %v330 =l add %rcentries, 64
 dbgloc 17
 call $myl_qbe_rc_slot_drop(l %ctx, l %v330)
@rcslotdone328
 %v326 =l copy %l6
 %v331 =l copy %rcwork
 blit %v331, %v326, 208
 %v332 =l add %rcguards, 48
 storew 0, %v332
 %v333 =l add %rcentries, 64
 storel extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, %v333
 %v334 =l add %v333, 24
 storew 2, %v334
 %v335 =l add %v333, 8
 storel %v326, %v335
 %v336 =l add %v333, 16
 %v337 =l add %rcguards, 16
 storel %v337, %v336
 %v339 =l add %rcentries, 216
 %v340 =l add %rcentries, 88
 %v338 =w loaduw %v339
 storew %v338, %v340
 %v341 =l add %rcguards, 16
 storew 1, %v341
 storel %l6, %s0
 %v342 =l loadl %l7
 storel %v342, %s1
 %v343 =l loadl %s0
 %v349 =l add %rcguards, 32
 %v350 =l add %rcentries, 152
 %v345 =w loaduw %v349
 %v346 =w loaduw %v350
 %v346 =w and %v346, 24
 %v347 =w ceqw %v346, 0
 %v348 =w and %v345, %v347
 jnz %v348, @rctake344, @rccopy344
@rctake344
 %v351 =l copy %rcwork
 %v352 =l copy %rcregion
 dbgloc 21
 %v353 =w call $myl_rc_native_take(l %heap, l extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, l %v351, l %v343, w %v352)
 jnz %v353, @rcsuccess354, @rcfailure354
@rcfailure354
 dbgloc 21
 %v355 =w call $myl_rc_take_failure(l %heap)
 dbgloc 21
 %v356 =w call $myl_qbe_rc_status(l %ctx, w %v355)
 jmp @failure
@rcsuccess354
 %v357 =l add %rcguards, 32
 storew 0, %v357
 %v358 =l add %rcentries, 192
 storel extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, %v358
 %v359 =l add %v358, 24
 storew 2, %v359
 %v360 =l add %rcguards, 48
 storew 1, %v360
 jmp @rcprepared344
@rccopy344
 %v361 =l copy %rcwork
 %v362 =l copy %rcregion
 dbgloc 21
 %v363 =w call $myl_rc_native_retain(l %heap, l extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, l %v361, l %v343, w %v362)
 jnz %v363, @rcsuccess364, @rcfailure364
@rcfailure364
 dbgloc 21
 %v365 =w call $myl_rc_take_failure(l %heap)
 dbgloc 21
 %v366 =w call $myl_qbe_rc_status(l %ctx, w %v365)
 jmp @failure
@rcsuccess364
 %v367 =l add %rcentries, 192
 storel extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, %v367
 %v368 =l add %v367, 24
 storew 2, %v368
 %v369 =l add %rcguards, 48
 storew 1, %v369
 %v372 =l add %rcguards, 32
 %v370 =w loaduw %v372
 jnz %v370, @rcslotdrop371, @rcslotdone371
@rcslotdrop371
 %v373 =l add %rcentries, 128
 dbgloc 21
 call $myl_qbe_rc_slot_drop(l %ctx, l %v373)
@rcslotdone371
@rcprepared344
 %v374 =l copy %rcwork
 %v375 =l copy %agg20
 blit %v374, %v375, 208
 %v376 =l add %rcguards, 48
 storew 0, %v376
 %v377 =l add %rcentries, 224
 storel extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, %v377
 %v378 =l add %v377, 24
 storew 2, %v378
 %v379 =l add %v377, 8
 storel %v375, %v379
 %v380 =l add %v377, 16
 %v381 =l add %rcguards, 56
 storel %v381, %v380
 %v382 =l add %rcguards, 56
 storew 1, %v382
 %v383 =l copy %rcregion
 %v384 =l copy %s1
 %v385 =l add %v375, 0
 %v386 =l copy %rcwork
 %v387 =l copy %s1
 %v393 =l add %rcguards, 40
 %v394 =l add %rcentries, 184
 %v389 =w loaduw %v393
 %v390 =w loaduw %v394
 %v390 =w and %v390, 24
 %v391 =w ceqw %v390, 0
 %v392 =w and %v389, %v391
 jnz %v392, @rctake388, @rccopy388
@rctake388
 %v395 =l copy %rcwork
 %v396 =l copy %rcregion
 %v398 =l sub %v387, %v395
 %v399 =l sub %v395, %v387
 %v400 =w cultl %v398, 8
 %v401 =w cultl %v399, 8
 %v402 =w or %v400, %v401
 jnz %v402, @rcmoveslow397, @rcmovecheck397
@rcmovecheck397
 %v406 =l add %v387, 0
 %v403 =l loadl %v406
 %v404 =w cnel %v403, 0
 jnz %v404, @rcmoveheader405, @rcmovenext405
@rcmoveheader405
 %v407 =l sub %v403, 16
 %v408 =l loadl %v407
 %v409 =l and %v408, 5764607523034234881
 %v410 =w cnel %v409, 0
 jnz %v410, @rcmoveslow397, @rcmovenext405
@rcmovenext405
 blit %v387, %v395, 8
 dbgloc 21
 call $memset(l %v387, w 0, l 8)
 jmp @rcmoved397
@rcmoveslow397
 dbgloc 21
 %v411 =w call $myl_rc_native_take(l %heap, l extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, l %v395, l %v387, w %v396)
 jnz %v411, @rcsuccess412, @rcfailure412
@rcfailure412
 dbgloc 21
 %v413 =w call $myl_rc_take_failure(l %heap)
 dbgloc 21
 %v414 =w call $myl_qbe_rc_status(l %ctx, w %v413)
 jmp @failure
@rcsuccess412
@rcmoved397
 %v415 =l add %rcguards, 40
 storew 0, %v415
 %v416 =l add %rcentries, 192
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v416
 %v417 =l add %v416, 24
 storew 2, %v417
 %v418 =l add %rcguards, 48
 storew 1, %v418
 jmp @rcprepared388
@rccopy388
 %v419 =l copy %rcwork
 %v420 =l copy %rcregion
 dbgloc 21
 %v421 =w call $myl_rc_native_retain(l %heap, l extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, l %v419, l %v387, w %v420)
 jnz %v421, @rcsuccess422, @rcfailure422
@rcfailure422
 dbgloc 21
 %v423 =w call $myl_rc_take_failure(l %heap)
 dbgloc 21
 %v424 =w call $myl_qbe_rc_status(l %ctx, w %v423)
 jmp @failure
@rcsuccess422
 %v425 =l add %rcentries, 192
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v425
 %v426 =l add %v425, 24
 storew 2, %v426
 %v427 =l add %rcguards, 48
 storew 1, %v427
 %v430 =l add %rcguards, 40
 %v428 =w loaduw %v430
 jnz %v428, @rcslotdrop429, @rcslotdone429
@rcslotdrop429
 %v431 =l add %rcentries, 160
 dbgloc 21
 call $myl_qbe_rc_slot_drop(l %ctx, l %v431)
@rcslotdone429
@rcprepared388
 %v432 =l copy %rcwork
 blit %v432, %v386, 8
 %v433 =l add %rcguards, 48
 storew 0, %v433
 %v434 =l add %rcentries, 192
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v434
 %v435 =l add %v434, 24
 storew 2, %v435
 %v436 =l add %v434, 8
 storel %v386, %v436
 %v437 =l add %v434, 16
 %v438 =l add %rcguards, 48
 storel %v438, %v437
 %v439 =l add %rcguards, 48
 storew 1, %v439
 dbgloc 21
 call $myl_rc_native_drop(l %heap, l extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, l %v385)
 blit %v386, %v385, 8
 %v440 =l add %rcguards, 48
 storew 0, %v440
 storel %v375, %s0
 %v441 =l add %rcguards, 56
 storew 0, %v441
 %v442 =l loadl %s0
 %v443 =l copy %rcwork
 blit %v442, %v443, 208
 %v444 =l add %rcentries, 192
 storel extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, %v444
 %v445 =l add %v444, 24
 storew 2, %v445
 %v446 =l add %rcguards, 48
 storew 1, %v446
 %v449 =l add %rcguards, 32
 %v447 =w loaduw %v449
 jnz %v447, @rcslotdrop448, @rcslotdone448
@rcslotdrop448
 %v450 =l add %rcentries, 128
 dbgloc 21
 call $myl_qbe_rc_slot_drop(l %ctx, l %v450)
@rcslotdone448
 %v453 =l add %rcguards, 40
 %v451 =w loaduw %v453
 jnz %v451, @rcslotdrop452, @rcslotdone452
@rcslotdrop452
 %v454 =l add %rcentries, 160
 dbgloc 21
 call $myl_qbe_rc_slot_drop(l %ctx, l %v454)
@rcslotdone452
 %v455 =l copy %rcs0
 %v456 =l copy %rcwork
 blit %v456, %v455, 208
 %v457 =l add %rcentries, 128
 storel extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, %v457
 %v458 =l add %v457, 24
 storew 2, %v458
 %v460 =l add %rcentries, 216
 %v461 =l add %rcentries, 152
 %v459 =w loaduw %v460
 storew %v459, %v461
 %v462 =l add %rcguards, 48
 storew 0, %v462
 %v463 =l add %rcguards, 32
 storew 1, %v463
 storel %v455, %s0
 %v464 =l loadl %s0
 %v470 =l add %rcguards, 32
 %v471 =l add %rcentries, 152
 %v466 =w loaduw %v470
 %v467 =w loaduw %v471
 %v467 =w and %v467, 24
 %v468 =w ceqw %v467, 0
 %v469 =w and %v466, %v468
 jnz %v469, @rctake465, @rccopy465
@rctake465
 %v472 =l copy %rcwork
 %v473 =l copy %rcregion
 dbgloc 22
 %v474 =w call $myl_rc_native_take(l %heap, l extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, l %v472, l %v464, w %v473)
 jnz %v474, @rcsuccess475, @rcfailure475
@rcfailure475
 dbgloc 22
 %v476 =w call $myl_rc_take_failure(l %heap)
 dbgloc 22
 %v477 =w call $myl_qbe_rc_status(l %ctx, w %v476)
 jmp @failure
@rcsuccess475
 %v478 =l add %rcguards, 32
 storew 0, %v478
 %v479 =l add %rcentries, 192
 storel extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, %v479
 %v480 =l add %v479, 24
 storew 2, %v480
 %v481 =l add %rcguards, 48
 storew 1, %v481
 jmp @rcprepared465
@rccopy465
 %v482 =l copy %rcwork
 %v483 =l copy %rcregion
 dbgloc 22
 %v484 =w call $myl_rc_native_retain(l %heap, l extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, l %v482, l %v464, w %v483)
 jnz %v484, @rcsuccess485, @rcfailure485
@rcfailure485
 dbgloc 22
 %v486 =w call $myl_rc_take_failure(l %heap)
 dbgloc 22
 %v487 =w call $myl_qbe_rc_status(l %ctx, w %v486)
 jmp @failure
@rcsuccess485
 %v488 =l add %rcentries, 192
 storel extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, %v488
 %v489 =l add %v488, 24
 storew 2, %v489
 %v490 =l add %rcguards, 48
 storew 1, %v490
 %v493 =l add %rcguards, 32
 %v491 =w loaduw %v493
 jnz %v491, @rcslotdrop492, @rcslotdone492
@rcslotdrop492
 %v494 =l add %rcentries, 128
 dbgloc 22
 call $myl_qbe_rc_slot_drop(l %ctx, l %v494)
@rcslotdone492
@rcprepared465
 %v495 =l loadl %l0
 dbgloc 22
 call $myl_rc_native_drop(l %heap, l extern $myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28, l %v495)
 %v496 =l copy %rcwork
 blit %v496, %v495, 208
 %v497 =l add %rcguards, 48
 storew 0, %v497
 %v500 =l add %rcguards, 24
 %v498 =w loaduw %v500
 jnz %v498, @rcslotdrop499, @rcslotdone499
@rcslotdrop499
 %v501 =l add %rcentries, 96
 dbgloc 22
 call $myl_qbe_rc_slot_drop(l %ctx, l %v501)
@rcslotdone499
 storel 0, %s0
 storel 0, %s0
 %v502 =l loadl %s0
 dbgloc 26
 call $myl_qbe_rc_frame_cleanup(l %ctx, l %rcframe)
 dbgloc 26
 call $myl_qbe_rc_frame_leave(l %ctx, l %rcframe)
 ret %v502
@failure
 dbgloc 26
 call $myl_qbe_rc_frame_cleanup(l %ctx, l %rcframe)
 dbgloc 26
 call $myl_qbe_rc_frame_leave(l %ctx, l %rcframe)
 ret 0
@entry_failure
 ret 0
}