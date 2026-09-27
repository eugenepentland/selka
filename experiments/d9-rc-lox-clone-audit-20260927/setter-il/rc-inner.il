export function l $myl_f_0b5b0c24ddddb193a115c6cacf83410e46d60453431effc245241a64d30eed3b(l %ctx, l %a0, l %a1, l %a2, l %a3, l %a4) {
@entry
 %trap =l add %ctx, 32
 %rcframe =l alloc8 32
 %rcentries =l alloc8 320
 %rcguards =l alloc8 80
 %rcs0 =l alloc8 56
 %rcs1 =l alloc8 56
 %rcwork =l alloc8 56
 %rcinternal =l alloc8 8
 %rcborrow5 =l alloc8 32
 dbgloc 1
 call $memset(l %rcborrow5, w 0, l 32)
 %rcborrow10 =l alloc8 32
 dbgloc 1
 call $memset(l %rcborrow10, w 0, l 32)
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
 dbgloc 1
 storel 0, %l10
 dbgloc 1
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
 call $memset(l %rcguards, w 0, l 80)
 %v7 =l copy %l0
 %v8 =l add %rcentries, 0
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v8
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
 %v19 =l copy %l7
 %v20 =l add %rcentries, 64
 storel extern $myl_t_f90b2531fe2edebbb3538bc221997b8a6ecd53794bf2c8b61b30685c25382939, %v20
 %v21 =l add %v20, 24
 storew 2, %v21
 %v22 =l add %v20, 8
 storel %v19, %v22
 %v23 =l add %v20, 16
 %v24 =l add %rcguards, 16
 storel %v24, %v23
 %v25 =l copy %l9
 %v26 =l add %rcentries, 96
 storel extern $myl_t_81d71c98b196ce876b8748e8f5e1c439a764a7854aeb5e4ef7865d0716f2ecef, %v26
 %v27 =l add %v26, 24
 storew 2, %v27
 %v28 =l add %v26, 8
 storel %v25, %v28
 %v29 =l add %v26, 16
 %v30 =l add %rcguards, 24
 storel %v30, %v29
 %v31 =l copy %l10
 %v32 =l add %rcentries, 128
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v32
 %v33 =l add %v32, 24
 storew 2, %v33
 %v34 =l add %v32, 8
 storel %v31, %v34
 %v35 =l add %v32, 16
 %v36 =l add %rcguards, 32
 storel %v36, %v35
 %v37 =l copy %l11
 %v38 =l add %rcentries, 160
 storel extern $myl_t_a83873657e77deb1bf51281383ae925ccb1b4b6510284b93a36500031c0efc14, %v38
 %v39 =l add %v38, 24
 storew 2, %v39
 %v40 =l add %v38, 8
 storel %v37, %v40
 %v41 =l add %v38, 16
 %v42 =l add %rcguards, 40
 storel %v42, %v41
 %v43 =l copy %rcs0
 %v44 =l add %rcentries, 192
 storel extern $myl_t_385cfdbc00ec32031699460779c15099b2bba3cad0e440fffb08e10df0acb9e1, %v44
 %v45 =l add %v44, 24
 storew 0, %v45
 %v46 =l add %v44, 8
 storel %v43, %v46
 %v47 =l add %v44, 16
 %v48 =l add %rcguards, 48
 storel %v48, %v47
 %v49 =l copy %rcs1
 %v50 =l add %rcentries, 224
 storel extern $myl_t_385cfdbc00ec32031699460779c15099b2bba3cad0e440fffb08e10df0acb9e1, %v50
 %v51 =l add %v50, 24
 storew 0, %v51
 %v52 =l add %v50, 8
 storel %v49, %v52
 %v53 =l add %v50, 16
 %v54 =l add %rcguards, 56
 storel %v54, %v53
 %v55 =l copy %rcwork
 %v56 =l add %rcentries, 256
 storel extern $myl_t_385cfdbc00ec32031699460779c15099b2bba3cad0e440fffb08e10df0acb9e1, %v56
 %v57 =l add %v56, 24
 storew 0, %v57
 %v58 =l add %v56, 8
 storel %v55, %v58
 %v59 =l add %v56, 16
 %v60 =l add %rcguards, 64
 storel %v60, %v59
 %v61 =l copy %rcinternal
 %v62 =l add %rcentries, 288
 storel extern $myl_t_385cfdbc00ec32031699460779c15099b2bba3cad0e440fffb08e10df0acb9e1, %v62
 %v63 =l add %v62, 24
 storew 0, %v63
 %v64 =l add %v62, 8
 storel %v61, %v64
 %v65 =l add %v62, 16
 %v66 =l add %rcguards, 72
 storel %v66, %v65
 dbgloc 1
 call $myl_qbe_rc_frame_enter(l %ctx, l %rcframe, l %rcentries, l 10)
 jmp @i0
@i0
 %v67 =l loadl %l0
 storel %v67, %s0
 %v68 =l copy %s0
 %v73 =l add %rcguards, 48
 %v74 =l add %rcentries, 216
 %v69 =w loaduw %v73
 %v70 =w loaduw %v74
 %v70 =w and %v70, 24
 %v71 =w ceqw %v70, 0
 %v72 =w and %v69, %v71
 jnz %v72, @rcprivateown75, @rcprivateloan75
@rcprivateown75
 %v76 =l copy %rcwork
 %v77 =l copy %rcregion
 %v79 =l sub %v68, %v76
 %v80 =l sub %v76, %v68
 %v81 =w cultl %v79, 8
 %v82 =w cultl %v80, 8
 %v83 =w or %v81, %v82
 jnz %v83, @rcmoveslow78, @rcmovecheck78
@rcmovecheck78
 %v87 =l add %v68, 0
 %v84 =l loadl %v87
 %v85 =w cnel %v84, 0
 jnz %v85, @rcmoveheader86, @rcmovenext86
@rcmoveheader86
 %v88 =l sub %v84, 16
 %v89 =l loadl %v88
 %v90 =l and %v89, 5764607523034234881
 %v91 =w cnel %v90, 0
 jnz %v91, @rcmoveslow78, @rcmovenext86
@rcmovenext86
 blit %v68, %v76, 8
 dbgloc 2
 call $memset(l %v68, w 0, l 8)
 jmp @rcmoved78
@rcmoveslow78
 dbgloc 2
 %v92 =w call $myl_rc_native_take(l %heap, l extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, l %v76, l %v68, w %v77)
 jnz %v92, @rcsuccess93, @rcfailure93
@rcfailure93
 dbgloc 2
 %v94 =w call $myl_rc_take_failure(l %heap)
 dbgloc 2
 %v95 =w call $myl_qbe_rc_status(l %ctx, w %v94)
 jmp @failure
@rcsuccess93
@rcmoved78
 %v96 =l add %rcguards, 48
 storew 0, %v96
 %v97 =l add %rcentries, 256
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v97
 %v98 =l add %v97, 24
 storew 2, %v98
 %v99 =l add %rcguards, 64
 storew 1, %v99
 jmp @rcprivateprepared75
@rcprivateloan75
 dbgloc 2
 %v100 =w call $myl_rc_native_loan(l %heap, l extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, l %rcwork, l %v68)
 jnz %v100, @rcsuccess101, @rcfailure101
@rcfailure101
 dbgloc 2
 %v102 =w call $myl_rc_take_failure(l %heap)
 dbgloc 2
 %v103 =w call $myl_qbe_rc_status(l %ctx, w %v102)
 jmp @failure
@rcsuccess101
 %v104 =l add %rcentries, 256
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v104
 %v105 =l add %v104, 24
 storew 2, %v105
 %v106 =l add %rcentries, 280
 storew 16, %v106
 %v107 =l add %rcguards, 64
 storew 1, %v107
 %v110 =l add %rcguards, 48
 %v108 =w loaduw %v110
 jnz %v108, @rcslotdrop109, @rcslotdone109
@rcslotdrop109
 %v111 =l add %rcentries, 192
 dbgloc 2
 call $myl_qbe_rc_slot_drop(l %ctx, l %v111)
@rcslotdone109
@rcprivateprepared75
 %v115 =l add %rcguards, 8
 %v113 =w loaduw %v115
 jnz %v113, @rcslotdrop114, @rcslotdone114
@rcslotdrop114
 %v116 =l add %rcentries, 32
 dbgloc 2
 call $myl_qbe_rc_slot_drop(l %ctx, l %v116)
@rcslotdone114
 %v112 =l copy %l5
 %v117 =l copy %rcwork
 blit %v117, %v112, 8
 %v118 =l add %rcguards, 64
 storew 0, %v118
 %v119 =l add %rcentries, 32
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v119
 %v120 =l add %v119, 24
 storew 2, %v120
 %v121 =l add %v119, 8
 storel %v112, %v121
 %v122 =l add %v119, 16
 %v123 =l add %rcguards, 8
 storel %v123, %v122
 %v125 =l add %rcentries, 280
 %v126 =l add %rcentries, 56
 %v124 =w loaduw %v125
 storew %v124, %v126
 %v127 =l add %rcguards, 8
 storew 1, %v127
 %v128 =l loadl %l1
 storel %v128, %s0
 %v129 =l loadl %s0
 storel %v129, %l6
 %v130 =l loadl %l6
 storel %v130, %s0
 storel 0, %s1
 %v131 =l loadl %s1
 %v132 =l loadl %s0
 %v133 =l csltl %v132, %v131
 storel %v133, %s0
 %v134 =l loadl %s0
 jnz %v134, @next135, @i13
@next135
 %v135 =l loadl %l5
 # myl-obj %v135
 %v137 =l add %v135, 0
 %v136 =l loadl %v137
 storel %v136, %s0
 %v138 =l loadl %s0
 %v139 =l cugtl %v138, 9223372036854775807
 jnz %v139, @cast_overflow140, @cast_ok140
@cast_overflow140
 dbgloc 10
 call $myl_qbe_fail_cast(l %ctx, l %v138, l 320)
 hlt
@cast_ok140
 storel %v138, %s0
 %v141 =l loadl %l6
 storel %v141, %s1
 %v142 =l loadl %s1
 %v143 =l loadl %s0
 %v144 =l add %v143, %v142
 %v146 =l xor %v143, %v144
 %v147 =l xor %v142, %v144
 %v148 =l and %v146, %v147
 %v145 =l csltl %v148, 0
 jnz %v145, @overflow144, @checked144
@overflow144
 dbgloc 12
 call $myl_qbe_fail_overflow_op(l %ctx, l 0, l %v143, l %v142, l 64)
 hlt
@checked144
 storel %v144, %s0
 %v149 =l loadl %s0
 storel %v149, %l6
@i13
 %v150 =l loadl %l6
 storel %v150, %s0
 %v151 =l loadl %l5
 # myl-obj %v151
 %v153 =l loadl %s0
 # myl-obj %v151
 %v154 =l loadl %v151
 %v155 =l cultl %v153, %v154
 jnz %v155, @success156, @failed156
@failed156
 dbgloc 15
 call $myl_qbe_fail_normalized_index_bounds(l %ctx, l %v153, l %v154)
 hlt
@success156
 # myl-obj %v151
 %v159 =l add %v151, 32
 %v160 =l loadl %v159
 # myl-elem %v160 56v
 %v157 =l mul %v153, 56
 %v158 =l add %v160, %v157
 storel %v158, %s0
 %v161 =l loadl %s0
 dbgloc 15
 %v162 =w call $myl_rc_native_loan(l %heap, l extern $myl_t_a83873657e77deb1bf51281383ae925ccb1b4b6510284b93a36500031c0efc14, l %rcwork, l %v161)
 jnz %v162, @rcsuccess163, @rcfailure163
@rcfailure163
 dbgloc 15
 %v164 =w call $myl_rc_take_failure(l %heap)
 dbgloc 15
 %v165 =w call $myl_qbe_rc_status(l %ctx, w %v164)
 jmp @failure
@rcsuccess163
 %v166 =l add %rcentries, 256
 storel extern $myl_t_a83873657e77deb1bf51281383ae925ccb1b4b6510284b93a36500031c0efc14, %v166
 %v167 =l add %v166, 24
 storew 2, %v167
 %v168 =l add %rcentries, 280
 storew 16, %v168
 %v169 =l add %rcguards, 64
 storew 1, %v169
 %v170 =l copy %rcs0
 %v171 =l copy %rcwork
 blit %v171, %v170, 56
 %v172 =l add %rcentries, 192
 storel extern $myl_t_a83873657e77deb1bf51281383ae925ccb1b4b6510284b93a36500031c0efc14, %v172
 %v173 =l add %v172, 24
 storew 2, %v173
 %v175 =l add %rcentries, 280
 %v176 =l add %rcentries, 216
 %v174 =w loaduw %v175
 storew %v174, %v176
 %v177 =l add %rcguards, 64
 storew 0, %v177
 %v178 =l add %rcguards, 48
 storew 1, %v178
 storel %v170, %s0
 %v179 =l loadl %s0
 %v180 =l loaduw %v179
 %v181 =l ceql %v180, 0
 jnz %v181, @rcarm181, @rcarmnext181
@rcarm181
 %v184 =l add %rcguards, 48
 %v182 =w loaduw %v184
 jnz %v182, @rcslotdrop183, @rcslotdone183
@rcslotdrop183
 %v185 =l add %rcentries, 192
 dbgloc 16
 call $myl_qbe_rc_slot_drop(l %ctx, l %v185)
@rcslotdone183
 jmp @i58
@rcarmnext181
 %v186 =l ceql %v180, 1
 jnz %v186, @rcarm186, @rcarmnext186
@rcarm186
 %v189 =l add %rcguards, 48
 %v187 =w loaduw %v189
 jnz %v187, @rcslotdrop188, @rcslotdone188
@rcslotdrop188
 %v190 =l add %rcentries, 192
 dbgloc 16
 call $myl_qbe_rc_slot_drop(l %ctx, l %v190)
@rcslotdone188
 jmp @i61
@rcarmnext186
 %v191 =l ceql %v180, 2
 jnz %v191, @rcarm191, @rcarmnext191
@rcarm191
 %v194 =l add %rcguards, 48
 %v192 =w loaduw %v194
 jnz %v192, @rcslotdrop193, @rcslotdone193
@rcslotdrop193
 %v195 =l add %rcentries, 192
 dbgloc 16
 call $myl_qbe_rc_slot_drop(l %ctx, l %v195)
@rcslotdone193
 jmp @i64
@rcarmnext191
 %v196 =l ceql %v180, 3
 jnz %v196, @rcarm196, @rcarmnext196
@rcarm196
 %v199 =l add %rcguards, 48
 %v197 =w loaduw %v199
 jnz %v197, @rcslotdrop198, @rcslotdone198
@rcslotdrop198
 %v200 =l add %rcentries, 192
 dbgloc 16
 call $myl_qbe_rc_slot_drop(l %ctx, l %v200)
@rcslotdone198
 jmp @i67
@rcarmnext196
 %v201 =l ceql %v180, 4
 jnz %v201, @rcarm201, @rcarmnext201
@rcarm201
 %v204 =l add %rcguards, 48
 %v202 =w loaduw %v204
 jnz %v202, @rcslotdrop203, @rcslotdone203
@rcslotdrop203
 %v205 =l add %rcentries, 192
 dbgloc 16
 call $myl_qbe_rc_slot_drop(l %ctx, l %v205)
@rcslotdone203
 jmp @i70
@rcarmnext201
 %v206 =l ceql %v180, 5
 jnz %v206, @rcarm206, @rcarmnext206
@rcarm206
 %v209 =l add %rcguards, 48
 %v207 =w loaduw %v209
 jnz %v207, @rcslotdrop208, @rcslotdone208
@rcslotdrop208
 %v210 =l add %rcentries, 192
 dbgloc 16
 call $myl_qbe_rc_slot_drop(l %ctx, l %v210)
@rcslotdone208
 jmp @i73
@rcarmnext206
 %v211 =l ceql %v180, 6
 jnz %v211, @rcarm211, @rcarmnext211
@rcarm211
 %v214 =l add %rcguards, 48
 %v212 =w loaduw %v214
 jnz %v212, @rcslotdrop213, @rcslotdone213
@rcslotdrop213
 %v215 =l add %rcentries, 192
 dbgloc 16
 call $myl_qbe_rc_slot_drop(l %ctx, l %v215)
@rcslotdone213
 jmp @i76
@rcarmnext211
 %v216 =l ceql %v180, 7
 jnz %v216, @rcarm216, @rcarmnext216
@rcarm216
 %v217 =l copy %rcwork
 %v218 =l add %v179, 8
 %v219 =l copy %rcregion
 dbgloc 16
 %v220 =w call $myl_rc_native_retain(l %heap, l extern $myl_t_f90b2531fe2edebbb3538bc221997b8a6ecd53794bf2c8b61b30685c25382939, l %v217, l %v218, w %v219)
 jnz %v220, @rcsuccess221, @rcfailure221
@rcfailure221
 dbgloc 16
 %v222 =w call $myl_rc_take_failure(l %heap)
 dbgloc 16
 %v223 =w call $myl_qbe_rc_status(l %ctx, w %v222)
 jmp @failure
@rcsuccess221
 %v224 =l add %rcentries, 256
 storel extern $myl_t_f90b2531fe2edebbb3538bc221997b8a6ecd53794bf2c8b61b30685c25382939, %v224
 %v225 =l add %v224, 24
 storew 2, %v225
 %v226 =l add %v224, 8
 storel %v217, %v226
 %v227 =l add %v224, 16
 %v228 =l add %rcguards, 64
 storel %v228, %v227
 %v229 =l add %rcguards, 64
 storew 1, %v229
 %v232 =l add %rcguards, 16
 %v230 =w loaduw %v232
 jnz %v230, @rcslotdrop231, @rcslotdone231
@rcslotdrop231
 %v233 =l add %rcentries, 64
 dbgloc 16
 call $myl_qbe_rc_slot_drop(l %ctx, l %v233)
@rcslotdone231
 blit %v217, %l7, 24
 %v234 =l add %rcguards, 64
 storew 0, %v234
 %v235 =l copy %l7
 %v236 =l add %rcentries, 64
 storel extern $myl_t_f90b2531fe2edebbb3538bc221997b8a6ecd53794bf2c8b61b30685c25382939, %v236
 %v237 =l add %v236, 24
 storew 2, %v237
 %v238 =l add %v236, 8
 storel %v235, %v238
 %v239 =l add %v236, 16
 %v240 =l add %rcguards, 16
 storel %v240, %v239
 %v241 =l add %rcguards, 16
 storew 1, %v241
 %v244 =l add %rcguards, 48
 %v242 =w loaduw %v244
 jnz %v242, @rcslotdrop243, @rcslotdone243
@rcslotdrop243
 %v245 =l add %rcentries, 192
 dbgloc 16
 call $myl_qbe_rc_slot_drop(l %ctx, l %v245)
@rcslotdone243
 jmp @i16
@rcarmnext216
 %v246 =l ceql %v180, 8
 jnz %v246, @rcarm246, @rcarmnext246
@rcarm246
 %v249 =l add %rcguards, 48
 %v247 =w loaduw %v249
 jnz %v247, @rcslotdrop248, @rcslotdone248
@rcslotdrop248
 %v250 =l add %rcentries, 192
 dbgloc 16
 call $myl_qbe_rc_slot_drop(l %ctx, l %v250)
@rcslotdone248
 jmp @i79
@rcarmnext246
 %v251 =l ceql %v180, 9
 jnz %v251, @rcarm251, @rcarmnext251
@rcarm251
 %v254 =l add %rcguards, 48
 %v252 =w loaduw %v254
 jnz %v252, @rcslotdrop253, @rcslotdone253
@rcslotdrop253
 %v255 =l add %rcentries, 192
 dbgloc 16
 call $myl_qbe_rc_slot_drop(l %ctx, l %v255)
@rcslotdone253
 jmp @i82
@rcarmnext251
 %v256 =l ceql %v180, 10
 jnz %v256, @rcarm256, @rcarmnext256
@rcarm256
 %v259 =l add %rcguards, 48
 %v257 =w loaduw %v259
 jnz %v257, @rcslotdrop258, @rcslotdone258
@rcslotdrop258
 %v260 =l add %rcentries, 192
 dbgloc 16
 call $myl_qbe_rc_slot_drop(l %ctx, l %v260)
@rcslotdone258
 jmp @i85
@rcarmnext256
 jmp @failure
@i16
 storel %l7, %s0
 %v261 =l loadl %s0
 %v267 =l add %rcguards, 48
 %v268 =l add %rcentries, 216
 %v263 =w loaduw %v267
 %v264 =w loaduw %v268
 %v264 =w and %v264, 24
 %v265 =w ceqw %v264, 0
 %v266 =w and %v263, %v265
 jnz %v266, @rctake262, @rccopy262
@rctake262
 %v269 =l copy %rcwork
 %v270 =l copy %rcregion
 %v272 =l sub %v261, %v269
 %v273 =l sub %v269, %v261
 %v274 =w cultl %v272, 24
 %v275 =w cultl %v273, 24
 %v276 =w or %v274, %v275
 jnz %v276, @rcmoveslow271, @rcmovecheck271
@rcmovecheck271
 %v280 =l add %v261, 8
 %v277 =l loadl %v280
 %v278 =w cnel %v277, 0
 jnz %v278, @rcmoveheader279, @rcmovenext279
@rcmoveheader279
 %v281 =l sub %v277, 16
 %v282 =l loadl %v281
 %v283 =l and %v282, 5764607523034234881
 %v284 =w cnel %v283, 0
 jnz %v284, @rcmoveslow271, @rcmovenext279
@rcmovenext279
 blit %v261, %v269, 24
 dbgloc 19
 call $memset(l %v261, w 0, l 24)
 jmp @rcmoved271
@rcmoveslow271
 dbgloc 19
 %v285 =w call $myl_rc_native_take(l %heap, l extern $myl_t_f90b2531fe2edebbb3538bc221997b8a6ecd53794bf2c8b61b30685c25382939, l %v269, l %v261, w %v270)
 jnz %v285, @rcsuccess286, @rcfailure286
@rcfailure286
 dbgloc 19
 %v287 =w call $myl_rc_take_failure(l %heap)
 dbgloc 19
 %v288 =w call $myl_qbe_rc_status(l %ctx, w %v287)
 jmp @failure
@rcsuccess286
@rcmoved271
 %v289 =l add %rcguards, 48
 storew 0, %v289
 %v290 =l add %rcentries, 256
 storel extern $myl_t_f90b2531fe2edebbb3538bc221997b8a6ecd53794bf2c8b61b30685c25382939, %v290
 %v291 =l add %v290, 24
 storew 2, %v291
 %v292 =l add %rcguards, 64
 storew 1, %v292
 jmp @rcprepared262
@rccopy262
 %v293 =l copy %rcwork
 %v294 =l copy %rcregion
 dbgloc 19
 %v295 =w call $myl_rc_native_retain(l %heap, l extern $myl_t_f90b2531fe2edebbb3538bc221997b8a6ecd53794bf2c8b61b30685c25382939, l %v293, l %v261, w %v294)
 jnz %v295, @rcsuccess296, @rcfailure296
@rcfailure296
 dbgloc 19
 %v297 =w call $myl_rc_take_failure(l %heap)
 dbgloc 19
 %v298 =w call $myl_qbe_rc_status(l %ctx, w %v297)
 jmp @failure
@rcsuccess296
 %v299 =l add %rcentries, 256
 storel extern $myl_t_f90b2531fe2edebbb3538bc221997b8a6ecd53794bf2c8b61b30685c25382939, %v299
 %v300 =l add %v299, 24
 storew 2, %v300
 %v301 =l add %rcguards, 64
 storew 1, %v301
 %v304 =l add %rcguards, 48
 %v302 =w loaduw %v304
 jnz %v302, @rcslotdrop303, @rcslotdone303
@rcslotdrop303
 %v305 =l add %rcentries, 192
 dbgloc 19
 call $myl_qbe_rc_slot_drop(l %ctx, l %v305)
@rcslotdone303
@rcprepared262
 %v309 =l add %rcguards, 16
 %v307 =w loaduw %v309
 jnz %v307, @rcslotdrop308, @rcslotdone308
@rcslotdrop308
 %v310 =l add %rcentries, 64
 dbgloc 19
 call $myl_qbe_rc_slot_drop(l %ctx, l %v310)
@rcslotdone308
 %v306 =l copy %l7
 %v311 =l copy %rcwork
 blit %v311, %v306, 24
 %v312 =l add %rcguards, 64
 storew 0, %v312
 %v313 =l add %rcentries, 64
 storel extern $myl_t_f90b2531fe2edebbb3538bc221997b8a6ecd53794bf2c8b61b30685c25382939, %v313
 %v314 =l add %v313, 24
 storew 2, %v314
 %v315 =l add %v313, 8
 storel %v306, %v315
 %v316 =l add %v313, 16
 %v317 =l add %rcguards, 16
 storel %v317, %v316
 %v319 =l add %rcentries, 280
 %v320 =l add %rcentries, 88
 %v318 =w loaduw %v319
 storew %v318, %v320
 %v321 =l add %rcguards, 16
 storew 1, %v321
 storel %l7, %s0
 %v322 =l loadl %s0
 %v323 =l add %v322, 0
 %v324 =l loadl %v323
 storel %v324, %s0
 %v327 =l add %rcguards, 48
 %v325 =w loaduw %v327
 jnz %v325, @rcslotdrop326, @rcslotdone326
@rcslotdrop326
 %v328 =l add %rcentries, 192
 dbgloc 21
 call $myl_qbe_rc_slot_drop(l %ctx, l %v328)
@rcslotdone326
 %v329 =l loadl %s0
 storel %v329, %l8
 storel %l7, %s0
 %v330 =l loadl %s0
 %v331 =l add %v330, 8
 storel %v331, %s0
 %v332 =l loadl %s0
 dbgloc 24
 %v333 =w call $myl_rc_native_loan(l %heap, l extern $myl_t_81d71c98b196ce876b8748e8f5e1c439a764a7854aeb5e4ef7865d0716f2ecef, l %rcwork, l %v332)
 jnz %v333, @rcsuccess334, @rcfailure334
@rcfailure334
 dbgloc 24
 %v335 =w call $myl_rc_take_failure(l %heap)
 dbgloc 24
 %v336 =w call $myl_qbe_rc_status(l %ctx, w %v335)
 jmp @failure
@rcsuccess334
 %v337 =l add %rcentries, 256
 storel extern $myl_t_81d71c98b196ce876b8748e8f5e1c439a764a7854aeb5e4ef7865d0716f2ecef, %v337
 %v338 =l add %v337, 24
 storew 2, %v338
 %v339 =l add %rcentries, 280
 storew 16, %v339
 %v340 =l add %rcguards, 64
 storew 1, %v340
 %v343 =l add %rcguards, 48
 %v341 =w loaduw %v343
 jnz %v341, @rcslotdrop342, @rcslotdone342
@rcslotdrop342
 %v344 =l add %rcentries, 192
 dbgloc 24
 call $myl_qbe_rc_slot_drop(l %ctx, l %v344)
@rcslotdone342
 %v345 =l copy %rcs0
 %v346 =l copy %rcwork
 blit %v346, %v345, 16
 %v347 =l add %rcentries, 192
 storel extern $myl_t_81d71c98b196ce876b8748e8f5e1c439a764a7854aeb5e4ef7865d0716f2ecef, %v347
 %v348 =l add %v347, 24
 storew 2, %v348
 %v350 =l add %rcentries, 280
 %v351 =l add %rcentries, 216
 %v349 =w loaduw %v350
 storew %v349, %v351
 %v352 =l add %rcguards, 64
 storew 0, %v352
 %v353 =l add %rcguards, 48
 storew 1, %v353
 storel %v345, %s0
 %v354 =l loadl %s0
 %v360 =l add %rcguards, 48
 %v361 =l add %rcentries, 216
 %v356 =w loaduw %v360
 %v357 =w loaduw %v361
 %v357 =w and %v357, 24
 %v358 =w ceqw %v357, 0
 %v359 =w and %v356, %v358
 jnz %v359, @rctake355, @rccopy355
@rctake355
 %v362 =l copy %rcwork
 %v363 =l copy %rcregion
 %v365 =l sub %v354, %v362
 %v366 =l sub %v362, %v354
 %v367 =w cultl %v365, 16
 %v368 =w cultl %v366, 16
 %v369 =w or %v367, %v368
 jnz %v369, @rcmoveslow364, @rcmovecheck364
@rcmovecheck364
 %v373 =l add %v354, 0
 %v370 =l loadl %v373
 %v371 =w cnel %v370, 0
 jnz %v371, @rcmoveheader372, @rcmovenext372
@rcmoveheader372
 %v374 =l sub %v370, 16
 %v375 =l loadl %v374
 %v376 =l and %v375, 5764607523034234881
 %v377 =w cnel %v376, 0
 jnz %v377, @rcmoveslow364, @rcmovenext372
@rcmovenext372
 blit %v354, %v362, 16
 dbgloc 26
 call $memset(l %v354, w 0, l 16)
 jmp @rcmoved364
@rcmoveslow364
 dbgloc 26
 %v378 =w call $myl_rc_native_take(l %heap, l extern $myl_t_81d71c98b196ce876b8748e8f5e1c439a764a7854aeb5e4ef7865d0716f2ecef, l %v362, l %v354, w %v363)
 jnz %v378, @rcsuccess379, @rcfailure379
@rcfailure379
 dbgloc 26
 %v380 =w call $myl_rc_take_failure(l %heap)
 dbgloc 26
 %v381 =w call $myl_qbe_rc_status(l %ctx, w %v380)
 jmp @failure
@rcsuccess379
@rcmoved364
 %v382 =l add %rcguards, 48
 storew 0, %v382
 %v383 =l add %rcentries, 256
 storel extern $myl_t_81d71c98b196ce876b8748e8f5e1c439a764a7854aeb5e4ef7865d0716f2ecef, %v383
 %v384 =l add %v383, 24
 storew 2, %v384
 %v385 =l add %rcguards, 64
 storew 1, %v385
 jmp @rcprepared355
@rccopy355
 %v386 =l copy %rcwork
 %v387 =l copy %rcregion
 dbgloc 26
 %v388 =w call $myl_rc_native_retain(l %heap, l extern $myl_t_81d71c98b196ce876b8748e8f5e1c439a764a7854aeb5e4ef7865d0716f2ecef, l %v386, l %v354, w %v387)
 jnz %v388, @rcsuccess389, @rcfailure389
@rcfailure389
 dbgloc 26
 %v390 =w call $myl_rc_take_failure(l %heap)
 dbgloc 26
 %v391 =w call $myl_qbe_rc_status(l %ctx, w %v390)
 jmp @failure
@rcsuccess389
 %v392 =l add %rcentries, 256
 storel extern $myl_t_81d71c98b196ce876b8748e8f5e1c439a764a7854aeb5e4ef7865d0716f2ecef, %v392
 %v393 =l add %v392, 24
 storew 2, %v393
 %v394 =l add %rcguards, 64
 storew 1, %v394
 %v397 =l add %rcguards, 48
 %v395 =w loaduw %v397
 jnz %v395, @rcslotdrop396, @rcslotdone396
@rcslotdrop396
 %v398 =l add %rcentries, 192
 dbgloc 26
 call $myl_qbe_rc_slot_drop(l %ctx, l %v398)
@rcslotdone396
@rcprepared355
 %v402 =l add %rcguards, 24
 %v400 =w loaduw %v402
 jnz %v400, @rcslotdrop401, @rcslotdone401
@rcslotdrop401
 %v403 =l add %rcentries, 96
 dbgloc 26
 call $myl_qbe_rc_slot_drop(l %ctx, l %v403)
@rcslotdone401
 %v399 =l copy %l9
 %v404 =l copy %rcwork
 blit %v404, %v399, 16
 %v405 =l add %rcguards, 64
 storew 0, %v405
 %v406 =l add %rcentries, 96
 storel extern $myl_t_81d71c98b196ce876b8748e8f5e1c439a764a7854aeb5e4ef7865d0716f2ecef, %v406
 %v407 =l add %v406, 24
 storew 2, %v407
 %v408 =l add %v406, 8
 storel %v399, %v408
 %v409 =l add %v406, 16
 %v410 =l add %rcguards, 24
 storel %v410, %v409
 %v412 =l add %rcentries, 280
 %v413 =l add %rcentries, 120
 %v411 =w loaduw %v412
 storew %v411, %v413
 %v414 =l add %rcguards, 24
 storew 1, %v414
 storel %l9, %s0
 %v415 =l loadl %l2
 storel %v415, %s1
 %v416 =l loadl %l3
 storel %v416, %s2
 %v417 =l loadl %l4
 storel %v417, %s3
 %v418 =l loadl %s0
 %v419 =l loadl %s1
 %v420 =l loadl %s2
 %v421 =l loadl %s3
 dbgloc 31
 %v422 =l call $myl_f_72cbd8b3ebb02b19d0384fb691061873bba08de6d559f9babec1767adabac444(l %ctx, l %v418, l %v419, l %v420, l %v421)
 storel %v422, %s0
 %v425 =l add %rcguards, 48
 %v423 =w loaduw %v425
 jnz %v423, @rcslotdrop424, @rcslotdone424
@rcslotdrop424
 %v426 =l add %rcentries, 192
 dbgloc 31
 call $myl_qbe_rc_slot_drop(l %ctx, l %v426)
@rcslotdone424
 %v427 =l loadl %l8
 storel %v427, %s0
 blit %l9, %agg33, 16
 storel %agg33, %s1
 %v428 =l copy %agg35
 dbgloc 36
 call $memset(l %v428, w 0, l 24)
 %v429 =l add %rcentries, 288
 storel extern $myl_t_f90b2531fe2edebbb3538bc221997b8a6ecd53794bf2c8b61b30685c25382939, %v429
 %v430 =l add %v429, 24
 storew 2, %v430
 %v431 =l add %v429, 8
 storel %v428, %v431
 %v432 =l add %v429, 16
 %v433 =l add %rcguards, 72
 storel %v433, %v432
 %v434 =l add %rcguards, 72
 storew 1, %v434
 %v435 =l copy %rcregion
 %v436 =l copy %s0
 %v437 =l add %v428, 0
 %v438 =l loadl %v436
 storel %v438, %v437
 %v439 =l loadl %s1
 %v440 =l add %v428, 8
 %v441 =l loadl %s1
 %v447 =l add %rcguards, 56
 %v448 =l add %rcentries, 248
 %v443 =w loaduw %v447
 %v444 =w loaduw %v448
 %v444 =w and %v444, 24
 %v445 =w ceqw %v444, 0
 %v446 =w and %v443, %v445
 jnz %v446, @rctake442, @rccopy442
@rctake442
 %v449 =l copy %rcwork
 %v450 =l copy %rcregion
 %v452 =l sub %v441, %v449
 %v453 =l sub %v449, %v441
 %v454 =w cultl %v452, 16
 %v455 =w cultl %v453, 16
 %v456 =w or %v454, %v455
 jnz %v456, @rcmoveslow451, @rcmovecheck451
@rcmovecheck451
 %v460 =l add %v441, 0
 %v457 =l loadl %v460
 %v458 =w cnel %v457, 0
 jnz %v458, @rcmoveheader459, @rcmovenext459
@rcmoveheader459
 %v461 =l sub %v457, 16
 %v462 =l loadl %v461
 %v463 =l and %v462, 5764607523034234881
 %v464 =w cnel %v463, 0
 jnz %v464, @rcmoveslow451, @rcmovenext459
@rcmovenext459
 blit %v441, %v449, 16
 dbgloc 36
 call $memset(l %v441, w 0, l 16)
 jmp @rcmoved451
@rcmoveslow451
 dbgloc 36
 %v465 =w call $myl_rc_native_take(l %heap, l extern $myl_t_81d71c98b196ce876b8748e8f5e1c439a764a7854aeb5e4ef7865d0716f2ecef, l %v449, l %v441, w %v450)
 jnz %v465, @rcsuccess466, @rcfailure466
@rcfailure466
 dbgloc 36
 %v467 =w call $myl_rc_take_failure(l %heap)
 dbgloc 36
 %v468 =w call $myl_qbe_rc_status(l %ctx, w %v467)
 jmp @failure
@rcsuccess466
@rcmoved451
 %v469 =l add %rcguards, 56
 storew 0, %v469
 %v470 =l add %rcentries, 256
 storel extern $myl_t_81d71c98b196ce876b8748e8f5e1c439a764a7854aeb5e4ef7865d0716f2ecef, %v470
 %v471 =l add %v470, 24
 storew 2, %v471
 %v472 =l add %rcguards, 64
 storew 1, %v472
 jmp @rcprepared442
@rccopy442
 %v473 =l copy %rcwork
 %v474 =l copy %rcregion
 dbgloc 36
 %v475 =w call $myl_rc_native_retain(l %heap, l extern $myl_t_81d71c98b196ce876b8748e8f5e1c439a764a7854aeb5e4ef7865d0716f2ecef, l %v473, l %v441, w %v474)
 jnz %v475, @rcsuccess476, @rcfailure476
@rcfailure476
 dbgloc 36
 %v477 =w call $myl_rc_take_failure(l %heap)
 dbgloc 36
 %v478 =w call $myl_qbe_rc_status(l %ctx, w %v477)
 jmp @failure
@rcsuccess476
 %v479 =l add %rcentries, 256
 storel extern $myl_t_81d71c98b196ce876b8748e8f5e1c439a764a7854aeb5e4ef7865d0716f2ecef, %v479
 %v480 =l add %v479, 24
 storew 2, %v480
 %v481 =l add %rcguards, 64
 storew 1, %v481
 %v484 =l add %rcguards, 56
 %v482 =w loaduw %v484
 jnz %v482, @rcslotdrop483, @rcslotdone483
@rcslotdrop483
 %v485 =l add %rcentries, 224
 dbgloc 36
 call $myl_qbe_rc_slot_drop(l %ctx, l %v485)
@rcslotdone483
@rcprepared442
 %v486 =l copy %rcwork
 blit %v486, %v440, 16
 %v487 =l add %rcguards, 64
 storew 0, %v487
 storel %v428, %s0
 %v488 =l loadl %s0
 %v489 =l copy %rcs0
 blit %v488, %v489, 24
 %v490 =l add %rcentries, 192
 storel extern $myl_t_f90b2531fe2edebbb3538bc221997b8a6ecd53794bf2c8b61b30685c25382939, %v490
 %v491 =l add %v490, 24
 storew 2, %v491
 %v492 =l add %rcguards, 48
 storew 1, %v492
 storel %v489, %s0
 %v493 =l add %rcguards, 72
 storew 0, %v493
 %v494 =l copy %agg36
 dbgloc 37
 call $memset(l %v494, w 0, l 56)
 storew 7, %v494
 %v495 =l add %rcentries, 288
 storel extern $myl_t_a83873657e77deb1bf51281383ae925ccb1b4b6510284b93a36500031c0efc14, %v495
 %v496 =l add %v495, 24
 storew 2, %v496
 %v497 =l add %v495, 8
 storel %v494, %v497
 %v498 =l add %v495, 16
 %v499 =l add %rcguards, 72
 storel %v499, %v498
 %v500 =l add %rcguards, 72
 storew 1, %v500
 %v501 =l loadl %s0
 %v502 =l add %v494, 8
 %v503 =l copy %rcregion
 %v504 =l loadl %s0
 %v505 =l copy %rcwork
 %v506 =l copy %rcregion
 %v511 =l add %v504, 8
 %v508 =l loadl %v511
 %v509 =w cnel %v508, 0
 jnz %v509, @rcmoveheader510, @rcmovenext510
@rcmoveheader510
 %v512 =l sub %v508, 16
 %v513 =l loadl %v512
 %v514 =l and %v513, 5764607523034234881
 %v515 =w cnel %v514, 0
 jnz %v515, @rcmoveslow507, @rcmovenext510
@rcmovenext510
 blit %v504, %v505, 24
 dbgloc 37
 call $memset(l %v504, w 0, l 24)
 jmp @rcmoved507
@rcmoveslow507
 dbgloc 37
 %v516 =w call $myl_rc_native_take(l %heap, l extern $myl_t_f90b2531fe2edebbb3538bc221997b8a6ecd53794bf2c8b61b30685c25382939, l %v505, l %v504, w %v506)
 jnz %v516, @rcsuccess517, @rcfailure517
@rcfailure517
 dbgloc 37
 %v518 =w call $myl_rc_take_failure(l %heap)
 dbgloc 37
 %v519 =w call $myl_qbe_rc_status(l %ctx, w %v518)
 jmp @failure
@rcsuccess517
@rcmoved507
 %v520 =l add %rcguards, 48
 storew 0, %v520
 %v521 =l add %rcentries, 256
 storel extern $myl_t_f90b2531fe2edebbb3538bc221997b8a6ecd53794bf2c8b61b30685c25382939, %v521
 %v522 =l add %v521, 24
 storew 2, %v522
 %v523 =l add %rcguards, 64
 storew 1, %v523
 %v524 =l copy %rcwork
 blit %v524, %v502, 24
 %v525 =l add %rcguards, 64
 storew 0, %v525
 storel %v494, %s0
 %v526 =l loadl %s0
 %v527 =l copy %rcs0
 blit %v526, %v527, 56
 %v528 =l add %rcentries, 192
 storel extern $myl_t_a83873657e77deb1bf51281383ae925ccb1b4b6510284b93a36500031c0efc14, %v528
 %v529 =l add %v528, 24
 storew 2, %v529
 %v530 =l add %rcguards, 48
 storew 1, %v530
 storel %v527, %s0
 %v531 =l add %rcguards, 72
 storew 0, %v531
 %v532 =l loadl %s0
 %v537 =l add %rcguards, 48
 %v538 =l add %rcentries, 216
 %v533 =w loaduw %v537
 %v534 =w loaduw %v538
 %v534 =w and %v534, 24
 %v535 =w ceqw %v534, 0
 %v536 =w and %v533, %v535
 jnz %v536, @rcprivateown539, @rcprivateloan539
@rcprivateown539
 %v540 =l copy %rcwork
 %v541 =l copy %rcregion
 dbgloc 38
 %v542 =w call $myl_rc_native_take(l %heap, l extern $myl_t_a83873657e77deb1bf51281383ae925ccb1b4b6510284b93a36500031c0efc14, l %v540, l %v532, w %v541)
 jnz %v542, @rcsuccess543, @rcfailure543
@rcfailure543
 dbgloc 38
 %v544 =w call $myl_rc_take_failure(l %heap)
 dbgloc 38
 %v545 =w call $myl_qbe_rc_status(l %ctx, w %v544)
 jmp @failure
@rcsuccess543
 %v546 =l add %rcguards, 48
 storew 0, %v546
 %v547 =l add %rcentries, 256
 storel extern $myl_t_a83873657e77deb1bf51281383ae925ccb1b4b6510284b93a36500031c0efc14, %v547
 %v548 =l add %v547, 24
 storew 2, %v548
 %v549 =l add %rcguards, 64
 storew 1, %v549
 jmp @rcprivateprepared539
@rcprivateloan539
 dbgloc 38
 %v550 =w call $myl_rc_native_loan(l %heap, l extern $myl_t_a83873657e77deb1bf51281383ae925ccb1b4b6510284b93a36500031c0efc14, l %rcwork, l %v532)
 jnz %v550, @rcsuccess551, @rcfailure551
@rcfailure551
 dbgloc 38
 %v552 =w call $myl_rc_take_failure(l %heap)
 dbgloc 38
 %v553 =w call $myl_qbe_rc_status(l %ctx, w %v552)
 jmp @failure
@rcsuccess551
 %v554 =l add %rcentries, 256
 storel extern $myl_t_a83873657e77deb1bf51281383ae925ccb1b4b6510284b93a36500031c0efc14, %v554
 %v555 =l add %v554, 24
 storew 2, %v555
 %v556 =l add %rcentries, 280
 storew 16, %v556
 %v557 =l add %rcguards, 64
 storew 1, %v557
 %v560 =l add %rcguards, 48
 %v558 =w loaduw %v560
 jnz %v558, @rcslotdrop559, @rcslotdone559
@rcslotdrop559
 %v561 =l add %rcentries, 192
 dbgloc 38
 call $myl_qbe_rc_slot_drop(l %ctx, l %v561)
@rcslotdone559
@rcprivateprepared539
 %v565 =l add %rcguards, 40
 %v563 =w loaduw %v565
 jnz %v563, @rcslotdrop564, @rcslotdone564
@rcslotdrop564
 %v566 =l add %rcentries, 160
 dbgloc 38
 call $myl_qbe_rc_slot_drop(l %ctx, l %v566)
@rcslotdone564
 %v562 =l copy %l11
 %v567 =l copy %rcwork
 blit %v567, %v562, 56
 %v568 =l add %rcguards, 64
 storew 0, %v568
 %v569 =l add %rcentries, 160
 storel extern $myl_t_a83873657e77deb1bf51281383ae925ccb1b4b6510284b93a36500031c0efc14, %v569
 %v570 =l add %v569, 24
 storew 2, %v570
 %v571 =l add %v569, 8
 storel %v562, %v571
 %v572 =l add %v569, 16
 %v573 =l add %rcguards, 40
 storel %v573, %v572
 %v575 =l add %rcentries, 280
 %v576 =l add %rcentries, 184
 %v574 =w loaduw %v575
 storew %v574, %v576
 %v577 =l add %rcguards, 40
 storew 1, %v577
 %v578 =l loadl %l0
 storel %v578, %s0
 %v581 =l add %rcguards, 48
 %v579 =w loaduw %v581
 jnz %v579, @rcslotdrop580, @rcslotdone580
@rcslotdrop580
 %v582 =l add %rcentries, 192
 dbgloc 40
 call $myl_qbe_rc_slot_drop(l %ctx, l %v582)
@rcslotdone580
 %v585 =l add %rcguards, 32
 %v583 =w loaduw %v585
 jnz %v583, @rcslotdrop584, @rcslotdone584
@rcslotdrop584
 %v586 =l add %rcentries, 128
 dbgloc 40
 call $myl_qbe_rc_slot_drop(l %ctx, l %v586)
@rcslotdone584
 %v588 =l add %rcguards, 0
 %v587 =l copy %l0
 %v591 =l add %rcentries, 0
 storel extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, %v591
 %v592 =l add %v591, 24
 storew 2, %v592
 %v593 =l add %v591, 8
 storel %v587, %v593
 %v594 =l add %v591, 16
 %v595 =l add %rcguards, 0
 storel %v595, %v594
 dbgloc 40
 %v590 =w call $myl_qbe_rc_unique_local(l %ctx, l extern $myl_t_10ba51025942802e98cbdad911475b594471021f660d3c2b48989b42d51368d2, l %v587, l %v588)
 jnz %v590, @rcunique596, @failure
@rcunique596
 %v597 =l loadl %l0
 %v598 =l copy %rcborrow10
 dbgloc 40
 call $myl_qbe_rc_scope_begin(l %ctx, l %v598)
 dbgloc 40
 %v599 =w call $myl_qbe_rc_scope_pin(l %ctx, l %v598, l %v597)
 jnz %v599, @rcunique600, @failure
@rcunique600
 storel %v597, %l10
 %v601 =l loadl %l1
 storel %v601, %s0
 %v602 =l loadl %s0
 storel %v602, %l12
 %v603 =l loadl %l12
 storel %v603, %s0
 storel 0, %s1
 %v604 =l loadl %s1
 %v605 =l loadl %s0
 %v606 =l csltl %v605, %v604
 storel %v606, %s0
 %v607 =l loadl %s0
 jnz %v607, @next608, @i51
@next608
 %v608 =l loadl %l10
 # myl-obj %v608
 %v610 =l add %v608, 0
 %v609 =l loadl %v610
 storel %v609, %s0
 %v611 =l loadl %s0
 %v612 =l cugtl %v611, 9223372036854775807
 jnz %v612, @cast_overflow613, @cast_ok613
@cast_overflow613
 dbgloc 48
 call $myl_qbe_fail_cast(l %ctx, l %v611, l 320)
 hlt
@cast_ok613
 storel %v611, %s0
 %v614 =l loadl %l12
 storel %v614, %s1
 %v615 =l loadl %s1
 %v616 =l loadl %s0
 %v617 =l add %v616, %v615
 %v619 =l xor %v616, %v617
 %v620 =l xor %v615, %v617
 %v621 =l and %v619, %v620
 %v618 =l csltl %v621, 0
 jnz %v618, @overflow617, @checked617
@overflow617
 dbgloc 50
 call $myl_qbe_fail_overflow_op(l %ctx, l 0, l %v616, l %v615, l 64)
 hlt
@checked617
 storel %v617, %s0
 %v622 =l loadl %s0
 storel %v622, %l12
@i51
 %v623 =l loadl %l12
 storel %v623, %s0
 blit %l11, %agg52, 56
 storel %agg52, %s1
 %v624 =l loadl %l10
 # myl-obj %v624
 %v626 =l loadl %s1
 %v627 =l loadl %s0
 # myl-obj %v624
 %v628 =l loadl %v624
 %v629 =l cultl %v627, %v628
 jnz %v629, @success630, @failed630
@failed630
 dbgloc 55
 call $myl_qbe_fail_normalized_index_bounds(l %ctx, l %v627, l %v628)
 hlt
@success630
 %v631 =l loadl %s1
 dbgloc 55
 %v632 =w call $myl_rc_list_set(l %heap, l %v624, l %v627, l %v631)
 jnz %v632, @success633, @failed633
@failed633
 dbgloc 55
 call $myl_qbe_fail_allocation(l %ctx)
 hlt
@success633
 storel 0, %s0
 %v636 =l add %rcguards, 56
 %v634 =w loaduw %v636
 jnz %v634, @rcslotdrop635, @rcslotdone635
@rcslotdrop635
 %v637 =l add %rcentries, 224
 dbgloc 55
 call $myl_qbe_rc_slot_drop(l %ctx, l %v637)
@rcslotdone635
 %v638 =l copy %rcborrow10
 dbgloc 55
 call $myl_qbe_rc_scope_end(l %ctx, l %v638)
 %v641 =l add %rcguards, 16
 %v639 =w loaduw %v641
 jnz %v639, @rcslotdrop640, @rcslotdone640
@rcslotdrop640
 %v642 =l add %rcentries, 64
 dbgloc 57
 call $myl_qbe_rc_slot_drop(l %ctx, l %v642)
@rcslotdone640
 jmp @i88
@i58
 storel 0, %s0
 %v643 =l loadl %s0
 jnz %v643, @success644, @failed644
@failed644
 dbgloc 60
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success644
 jmp @i88
@i61
 storel 0, %s0
 %v645 =l loadl %s0
 jnz %v645, @success646, @failed646
@failed646
 dbgloc 63
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success646
 jmp @i88
@i64
 storel 0, %s0
 %v647 =l loadl %s0
 jnz %v647, @success648, @failed648
@failed648
 dbgloc 66
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success648
 jmp @i88
@i67
 storel 0, %s0
 %v649 =l loadl %s0
 jnz %v649, @success650, @failed650
@failed650
 dbgloc 69
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success650
 jmp @i88
@i70
 storel 0, %s0
 %v651 =l loadl %s0
 jnz %v651, @success652, @failed652
@failed652
 dbgloc 72
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success652
 jmp @i88
@i73
 storel 0, %s0
 %v653 =l loadl %s0
 jnz %v653, @success654, @failed654
@failed654
 dbgloc 75
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success654
 jmp @i88
@i76
 storel 0, %s0
 %v655 =l loadl %s0
 jnz %v655, @success656, @failed656
@failed656
 dbgloc 78
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success656
 jmp @i88
@i79
 storel 0, %s0
 %v657 =l loadl %s0
 jnz %v657, @success658, @failed658
@failed658
 dbgloc 81
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success658
 jmp @i88
@i82
 storel 0, %s0
 %v659 =l loadl %s0
 jnz %v659, @success660, @failed660
@failed660
 dbgloc 84
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success660
 jmp @i88
@i85
 storel 0, %s0
 %v661 =l loadl %s0
 jnz %v661, @success662, @failed662
@failed662
 dbgloc 87
 call $myl_qbe_fail_assert(l %ctx)
 hlt
@success662
 jmp @i88
@i88
 storel 0, %s0
 %v663 =l loadl %s0
 dbgloc 90
 call $myl_qbe_rc_frame_cleanup(l %ctx, l %rcframe)
 dbgloc 90
 call $myl_qbe_rc_frame_leave(l %ctx, l %rcframe)
 ret %v663
@failure
 dbgloc 90
 call $myl_qbe_rc_frame_cleanup(l %ctx, l %rcframe)
 dbgloc 90
 call $myl_qbe_rc_frame_leave(l %ctx, l %rcframe)
 ret 0
@entry_failure
 ret 0
}