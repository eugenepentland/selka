@i22
 storel %l4, %s0
 %v615 =l loadl %s0
 %v616 =l add %v615, 8
 %v617 =l loadl %v616
 storel %v617, %s0
 %v618 =l copy %s0
 dbgloc 24
 %v619 =w call $myl_rc_native_loan(l %heap, l extern $myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527, l %rcwork, l %v618)
 jnz %v619, @rcsuccess620, @rcfailure620
@rcfailure620
 dbgloc 24
 %v621 =w call $myl_rc_take_failure(l %heap)
 dbgloc 24
 %v622 =w call $myl_qbe_rc_status(l %ctx, w %v621)
 jmp @failure
@rcsuccess620
 %v623 =l add %rcentries, 2048
 storel extern $myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527, %v623
 %v624 =l add %v623, 24
 storew 2, %v624
 %v625 =l add %rcentries, 2072
 storew 16, %v625
 %v626 =l add %rcguards, 512
 storew 1, %v626
 %v629 =l add %rcguards, 488
 %v627 =w loaduw %v629
 jnz %v627, @rcslotdrop628, @rcslotdone628
@rcslotdrop628
 %v630 =l add %rcentries, 1952
 dbgloc 24
 call $myl_qbe_rc_slot_drop(l %ctx, l %v630)
@rcslotdone628
 %v631 =l copy %rcs0
 %v632 =l copy %rcwork
 blit %v632, %v631, 8
 %v633 =l add %rcentries, 1952
 storel extern $myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527, %v633
 %v634 =l add %v633, 24
 storew 2, %v634
 %v636 =l add %rcentries, 2072
 %v637 =l add %rcentries, 1976
 %v635 =w loaduw %v636
 storew %v635, %v637
 %v638 =l add %rcguards, 512
 storew 0, %v638
 %v639 =l add %rcguards, 488
 storew 1, %v639
 %v640 =l loadl %v631
 storel %v640, %s0
 %v641 =l copy %s0
 %v646 =l add %rcguards, 488
 %v647 =l add %rcentries, 1976
 %v642 =w loaduw %v646
 %v643 =w loaduw %v647
 %v643 =w and %v643, 24
 %v644 =w ceqw %v643, 0
 %v645 =w and %v642, %v644
 jnz %v645, @rcprivateown648, @rcprivateloan648
@rcprivateown648
 %v649 =l copy %rcwork
 %v650 =l copy %rcregion
 %v652 =l sub %v641, %v649
 %v653 =l sub %v649, %v641
 %v654 =w cultl %v652, 8
 %v655 =w cultl %v653, 8
 %v656 =w or %v654, %v655
 jnz %v656, @rcmoveslow651, @rcmovecheck651
@rcmovecheck651
 %v660 =l add %v641, 0
 %v657 =l loadl %v660
 %v658 =w cnel %v657, 0
 jnz %v658, @rcmoveheader659, @rcmovenext659
@rcmoveheader659
 %v661 =l sub %v657, 16
 %v662 =l loadl %v661
 %v663 =l and %v662, 5764607523034234881
 %v664 =w cnel %v663, 0
 jnz %v664, @rcmoveslow651, @rcmovenext659
@rcmovenext659
 blit %v641, %v649, 8
 dbgloc 25
 call $memset(l %v641, w 0, l 8)
 jmp @rcmoved651
@rcmoveslow651
 dbgloc 25
 %v665 =w call $myl_rc_native_take(l %heap, l extern $myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527, l %v649, l %v641, w %v650)
 jnz %v665, @rcsuccess666, @rcfailure666
@rcfailure666
 dbgloc 25
 %v667 =w call $myl_rc_take_failure(l %heap)
 dbgloc 25
 %v668 =w call $myl_qbe_rc_status(l %ctx, w %v667)
 jmp @failure
@rcsuccess666
@rcmoved651
 %v669 =l add %rcguards, 488
 storew 0, %v669
 %v670 =l add %rcentries, 2048
 storel extern $myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527, %v670
 %v671 =l add %v670, 24
 storew 2, %v671
 %v672 =l add %rcguards, 512
 storew 1, %v672
 jmp @rcprivateprepared648
@rcprivateloan648
 dbgloc 25
 %v673 =w call $myl_rc_native_loan(l %heap, l extern $myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527, l %rcwork, l %v641)
 jnz %v673, @rcsuccess674, @rcfailure674
@rcfailure674
 dbgloc 25
 %v675 =w call $myl_rc_take_failure(l %heap)
 dbgloc 25
 %v676 =w call $myl_qbe_rc_status(l %ctx, w %v675)
 jmp @failure
@rcsuccess674
 %v677 =l add %rcentries, 2048
 storel extern $myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527, %v677
 %v678 =l add %v677, 24
 storew 2, %v678
 %v679 =l add %rcentries, 2072
 storew 16, %v679
 %v680 =l add %rcguards, 512
 storew 1, %v680
 %v683 =l add %rcguards, 488
 %v681 =w loaduw %v683
 jnz %v681, @rcslotdrop682, @rcslotdone682
@rcslotdrop682
 %v684 =l add %rcentries, 1952
 dbgloc 25
 call $myl_qbe_rc_slot_drop(l %ctx, l %v684)
@rcslotdone682
@rcprivateprepared648
 %v688 =l add %rcguards, 32
 %v686 =w loaduw %v688
 jnz %v686, @rcslotdrop687, @rcslotdone687
@rcslotdrop687
 %v689 =l add %rcentries, 128
 dbgloc 25
 call $myl_qbe_rc_slot_drop(l %ctx, l %v689)
@rcslotdone687
 %v685 =l copy %l5
 %v690 =l copy %rcwork
 blit %v690, %v685, 8
 %v691 =l add %rcguards, 512
 storew 0, %v691
 %v692 =l add %rcentries, 128
 storel extern $myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527, %v692
 %v693 =l add %v692, 24
 storew 2, %v693
 %v694 =l add %v692, 8
 storel %v685, %v694
 %v695 =l add %v692, 16
 %v696 =l add %rcguards, 32
 storel %v696, %v695
 %v698 =l add %rcentries, 2072
 %v699 =l add %rcentries, 152
 %v697 =w loaduw %v698
 storew %v697, %v699
 %v700 =l add %rcguards, 32
 storew 1, %v700
 storel %l4, %s0
 %v701 =l loadl %s0
 %v702 =l add %v701, 24
 %v703 =l loadl %v702
 storel %v703, %s0
 %v706 =l add %rcguards, 488
 %v704 =w loaduw %v706
 jnz %v704, @rcslotdrop705, @rcslotdone705
@rcslotdrop705
 %v707 =l add %rcentries, 1952
 dbgloc 27
 call $myl_qbe_rc_slot_drop(l %ctx, l %v707)
@rcslotdone705
 %v708 =l loadl %s0
 storel %v708, %l6
 %v709 =l loadl %l6
 storel %v709, %s0
 storel 0, %s1
 %v710 =l loadl %s1
 %v711 =l loadl %s0
 %v712 =l csltl %v711, %v710
 storel %v712, %s0
 %v713 =l loadl %s0
 jnz %v713, @next714, @i37
@next714
 %v714 =l loadl %l5
 # myl-obj %v714
 %v716 =l add %v714, 0
 %v715 =l loadl %v716
 storel %v715, %s0
 %v717 =l loadl %s0
 %v718 =l cugtl %v717, 9223372036854775807
 jnz %v718, @cast_overflow719, @cast_ok719
@cast_overflow719
 dbgloc 34
 call $myl_qbe_fail_cast(l %ctx, l %v717, l 320)
 hlt
@cast_ok719
 storel %v717, %s0
 %v720 =l loadl %l6
 storel %v720, %s1
 %v721 =l loadl %s1
 %v722 =l loadl %s0
 %v723 =l add %v722, %v721
 %v725 =l xor %v722, %v723
 %v726 =l xor %v721, %v723
 %v727 =l and %v725, %v726
 %v724 =l csltl %v727, 0
 jnz %v724, @overflow723, @checked723
@overflow723
 dbgloc 36
 call $myl_qbe_fail_overflow_op(l %ctx, l 0, l %v722, l %v721, l 64)
 hlt
@checked723
 storel %v723, %s0
 %v728 =l loadl %s0
 storel %v728, %l6
@i37
 %v729 =l loadl %l6
 storel %v729, %s0
 %v730 =l loadl %l5
 # myl-obj %v730
 %v732 =l loadl %s0
 # myl-obj %v730
 %v733 =l loadl %v730
 %v734 =l cultl %v732, %v733
 jnz %v734, @success735, @failed735
@failed735
 dbgloc 39
 call $myl_qbe_fail_normalized_index_bounds(l %ctx, l %v732, l %v733)
 hlt
@success735
 # myl-obj %v730
 %v738 =l add %v730, 32
 %v739 =l loadl %v738
 # myl-elem %v739 8v
 %v736 =l mul %v732, 8
 %v737 =l add %v739, %v736
 %v740 =l loadl %v737
 storel %v740, %s0
 %v741 =l loadl %s0
 storel %v741, %l7
 %v744 =l add %rcguards, 32
 %v742 =w loaduw %v744
 jnz %v742, @rcslotdrop743, @rcslotdone743
@rcslotdrop743
 %v745 =l add %rcentries, 128
 dbgloc 40
 call $myl_qbe_rc_slot_drop(l %ctx, l %v745)
@rcslotdone743
