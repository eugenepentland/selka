 storel 22, %position
 %v715 =l loadl %ctx
 %v716 =l loadl %maxsteps
 %v717 =l ceql %v715, %v716
 jnz %v717, @step_limit, @step718
@step718
 %v718 =l add %v715, 1
 storel %v718, %ctx
 storel %l4, %s0
 storel 23, %position
 %v719 =l loadl %ctx
 %v720 =l loadl %maxsteps
 %v721 =l ceql %v719, %v720
 jnz %v721, @step_limit, @step722
@step722
 %v722 =l add %v719, 1
 storel %v722, %ctx
 %v723 =l loadl %s0
 %v724 =l add %v723, 8
 %v725 =l loadl %v724
 storel %v725, %s0
 %v726 =l copy %s0
 %v727 =w call $myl_rc_native_loan(l %heap, l extern $myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527, l %rcwork, l %v726)
 jnz %v727, @rcsuccess728, @rcfailure728
@rcfailure728
 %v729 =w call $myl_rc_take_failure(l %heap)
 %v730 =w call $myl_qbe_rc_status(l %ctx, w %v729)
 jmp @failure
@rcsuccess728
 %v731 =l add %rcentries, 2048
 storel extern $myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527, %v731
 %v732 =l add %v731, 24
 storew 2, %v732
 %v733 =l add %rcentries, 2072
 storew 16, %v733
 %v734 =l add %rcguards, 512
 storew 1, %v734
 %v737 =l add %rcguards, 488
 %v735 =w loaduw %v737
 jnz %v735, @rcslotdrop736, @rcslotdone736
@rcslotdrop736
 %v738 =l add %rcentries, 1952
 call $myl_qbe_rc_slot_drop(l %ctx, l %v738)
@rcslotdone736
 %v739 =l copy %rcs0
 %v740 =l copy %rcwork
 blit %v740, %v739, 8
 %v741 =l add %rcentries, 1952
 storel extern $myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527, %v741
 %v742 =l add %v741, 24
 storew 2, %v742
 %v744 =l add %rcentries, 2072
 %v745 =l add %rcentries, 1976
 %v743 =w loaduw %v744
 storew %v743, %v745
 %v746 =l add %rcguards, 512
 storew 0, %v746
 %v747 =l add %rcguards, 488
 storew 1, %v747
 %v748 =l loadl %v739
 storel %v748, %s0
 storel 24, %position
 %v749 =l loadl %ctx
 %v750 =l loadl %maxsteps
 %v751 =l ceql %v749, %v750
 jnz %v751, @step_limit, @step752
@step752
 %v752 =l add %v749, 1
 storel %v752, %ctx
 %v753 =l copy %s0
 %v758 =l add %rcguards, 488
 %v759 =l add %rcentries, 1976
 %v754 =w loaduw %v758
 %v755 =w loaduw %v759
 %v755 =w and %v755, 24
 %v756 =w ceqw %v755, 0
 %v757 =w and %v754, %v756
 jnz %v757, @rcprivateown760, @rcprivateloan760
@rcprivateown760
 %v761 =l copy %rcwork
 %v762 =l copy %rcregion
 %v764 =l sub %v753, %v761
 %v765 =l sub %v761, %v753
 %v766 =w cultl %v764, 8
 %v767 =w cultl %v765, 8
 %v768 =w or %v766, %v767
 jnz %v768, @rcmoveslow763, @rcmovecheck763
@rcmovecheck763
 %v772 =l add %v753, 0
 %v769 =l loadl %v772
 %v770 =w cnel %v769, 0
 jnz %v770, @rcmoveheader771, @rcmovenext771
@rcmoveheader771
 %v773 =l sub %v769, 16
 %v774 =l loadl %v773
 %v775 =l and %v774, 5764607523034234881
 %v776 =w cnel %v775, 0
 jnz %v776, @rcmoveslow763, @rcmovenext771
@rcmovenext771
 blit %v753, %v761, 8
 call $memset(l %v753, w 0, l 8)
 jmp @rcmoved763
@rcmoveslow763
 %v777 =w call $myl_rc_native_take(l %heap, l extern $myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527, l %v761, l %v753, w %v762)
 jnz %v777, @rcsuccess778, @rcfailure778
@rcfailure778
 %v779 =w call $myl_rc_take_failure(l %heap)
 %v780 =w call $myl_qbe_rc_status(l %ctx, w %v779)
 jmp @failure
@rcsuccess778
@rcmoved763
 %v781 =l add %rcguards, 488
 storew 0, %v781
 %v782 =l add %rcentries, 2048
 storel extern $myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527, %v782
 %v783 =l add %v782, 24
 storew 2, %v783
 %v784 =l add %rcguards, 512
 storew 1, %v784
 jmp @rcprivateprepared760
@rcprivateloan760
 %v785 =w call $myl_rc_native_loan(l %heap, l extern $myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527, l %rcwork, l %v753)
 jnz %v785, @rcsuccess786, @rcfailure786
@rcfailure786
 %v787 =w call $myl_rc_take_failure(l %heap)
 %v788 =w call $myl_qbe_rc_status(l %ctx, w %v787)
 jmp @failure
@rcsuccess786
 %v789 =l add %rcentries, 2048
 storel extern $myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527, %v789
 %v790 =l add %v789, 24
 storew 2, %v790
 %v791 =l add %rcentries, 2072
 storew 16, %v791
 %v792 =l add %rcguards, 512
 storew 1, %v792
 %v795 =l add %rcguards, 488
 %v793 =w loaduw %v795
 jnz %v793, @rcslotdrop794, @rcslotdone794
@rcslotdrop794
 %v796 =l add %rcentries, 1952
 call $myl_qbe_rc_slot_drop(l %ctx, l %v796)
@rcslotdone794
@rcprivateprepared760
 %v800 =l add %rcguards, 32
 %v798 =w loaduw %v800
 jnz %v798, @rcslotdrop799, @rcslotdone799
@rcslotdrop799
 %v801 =l add %rcentries, 128
 call $myl_qbe_rc_slot_drop(l %ctx, l %v801)
@rcslotdone799
 %v797 =l copy %l5
 %v802 =l copy %rcwork
 blit %v802, %v797, 8
 %v803 =l add %rcguards, 512
 storew 0, %v803
 %v804 =l add %rcentries, 128
 storel extern $myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527, %v804
 %v805 =l add %v804, 24
 storew 2, %v805
 %v806 =l add %v804, 8
 storel %v797, %v806
 %v807 =l add %v804, 16
 %v808 =l add %rcguards, 32
 storel %v808, %v807
 %v810 =l add %rcentries, 2072
 %v811 =l add %rcentries, 152
 %v809 =w loaduw %v810
 storew %v809, %v811
 %v812 =l add %rcguards, 32
 storew 1, %v812
 storel 25, %position
 %v813 =l loadl %ctx
 %v814 =l loadl %maxsteps
 %v815 =l ceql %v813, %v814
 jnz %v815, @step_limit, @step816
@step816
 %v816 =l add %v813, 1
 storel %v816, %ctx
 storel %l4, %s0
 storel 26, %position
 %v817 =l loadl %ctx
 %v818 =l loadl %maxsteps
 %v819 =l ceql %v817, %v818
 jnz %v819, @step_limit, @step820
@step820
 %v820 =l add %v817, 1
 storel %v820, %ctx
 %v821 =l loadl %s0
 %v822 =l add %v821, 24
 %v823 =l loadl %v822
 storel %v823, %s0
 %v826 =l add %rcguards, 488
 %v824 =w loaduw %v826
 jnz %v824, @rcslotdrop825, @rcslotdone825
@rcslotdrop825
 %v827 =l add %rcentries, 1952
 call $myl_qbe_rc_slot_drop(l %ctx, l %v827)
@rcslotdone825
 storel 27, %position
 %v828 =l loadl %ctx
 %v829 =l loadl %maxsteps
 %v830 =l ceql %v828, %v829
 jnz %v830, @step_limit, @step831
@step831
 %v831 =l add %v828, 1
 storel %v831, %ctx
 %v832 =l loadl %s0
 storel %v832, %l6
 storel 28, %position
 %v833 =l loadl %ctx
 %v834 =l loadl %maxsteps
 %v835 =l ceql %v833, %v834
 jnz %v835, @step_limit, @step836
@step836
 %v836 =l add %v833, 1
 storel %v836, %ctx
 %v837 =l loadl %l6
 storel %v837, %s0
 storel 29, %position
 %v838 =l loadl %ctx
 %v839 =l loadl %maxsteps
 %v840 =l ceql %v838, %v839
 jnz %v840, @step_limit, @step841
@step841
 %v841 =l add %v838, 1
 storel %v841, %ctx
 storel 0, %s1
 storel 30, %position
 %v842 =l loadl %ctx
 %v843 =l loadl %maxsteps
 %v844 =l ceql %v842, %v843
 jnz %v844, @step_limit, @step845
@step845
 %v845 =l add %v842, 1
 storel %v845, %ctx
 %v846 =l loadl %s1
 %v847 =l loadl %s0
 %v848 =l csltl %v847, %v846
 storel %v848, %s0
 storel 31, %position
 %v849 =l loadl %ctx
 %v850 =l loadl %maxsteps
 %v851 =l ceql %v849, %v850
 jnz %v851, @step_limit, @step852
@step852
 %v852 =l add %v849, 1
 storel %v852, %ctx
 %v853 =l loadl %s0
 jnz %v853, @next854, @i37
@next854
 storel 32, %position
 %v854 =l loadl %ctx
 %v855 =l loadl %maxsteps
 %v856 =l ceql %v854, %v855
 jnz %v856, @step_limit, @step857
@step857
 %v857 =l add %v854, 1
 storel %v857, %ctx
 %v858 =l loadl %l5
 # myl-obj %v858
 %v860 =l add %v858, 0
 %v859 =l loadl %v860
 storel %v859, %s0
 storel 33, %position
 %v861 =l loadl %ctx
 %v862 =l loadl %maxsteps
 %v863 =l ceql %v861, %v862
 jnz %v863, @step_limit, @step864
@step864
 %v864 =l add %v861, 1
 storel %v864, %ctx
 %v865 =l loadl %s0
 %v866 =l cugtl %v865, 9223372036854775807
 jnz %v866, @cast_overflow867, @cast_ok867
@cast_overflow867
 call $myl_qbe_fail_cast(l %ctx, l %v865, l 320)
 jmp @failure
@cast_ok867
 storel %v865, %s0
 storel 34, %position
 %v868 =l loadl %ctx
 %v869 =l loadl %maxsteps
 %v870 =l ceql %v868, %v869
 jnz %v870, @step_limit, @step871
@step871
 %v871 =l add %v868, 1
 storel %v871, %ctx
 %v872 =l loadl %l6
 storel %v872, %s1
 storel 35, %position
 %v873 =l loadl %ctx
 %v874 =l loadl %maxsteps
 %v875 =l ceql %v873, %v874
 jnz %v875, @step_limit, @step876
@step876
 %v876 =l add %v873, 1
 storel %v876, %ctx
 %v877 =l loadl %s1
 %v878 =l loadl %s0
 %v879 =l add %v878, %v877
 %v881 =l xor %v878, %v879
 %v882 =l xor %v877, %v879
 %v883 =l and %v881, %v882
 %v880 =l csltl %v883, 0
 jnz %v880, @overflow879, @checked879
@overflow879
 call $myl_qbe_fail_overflow_op(l %ctx, l 0, l %v878, l %v877, l 64)
 jmp @failure
@checked879
 storel %v879, %s0
 storel 36, %position
 %v884 =l loadl %ctx
 %v885 =l loadl %maxsteps
 %v886 =l ceql %v884, %v885
 jnz %v886, @step_limit, @step887
@step887
 %v887 =l add %v884, 1
 storel %v887, %ctx
 %v888 =l loadl %s0
 storel %v888, %l6
@i37
 storel 37, %position
 %v889 =l loadl %ctx
 %v890 =l loadl %maxsteps
 %v891 =l ceql %v889, %v890
 jnz %v891, @step_limit, @step892
@step892
 %v892 =l add %v889, 1
 storel %v892, %ctx
 %v893 =l loadl %l6
 storel %v893, %s0
 storel 38, %position
 %v894 =l loadl %ctx
 %v895 =l loadl %maxsteps
 %v896 =l ceql %v894, %v895
 jnz %v896, @step_limit, @step897
@step897
 %v897 =l add %v894, 1
 storel %v897, %ctx
 %v898 =l loadl %l5
 # myl-obj %v898
 %v900 =l loadl %s0
 # myl-obj %v898
 %v901 =l loadl %v898
 %v902 =l cultl %v900, %v901
 jnz %v902, @success903, @failed903
@failed903
 call $myl_qbe_fail_normalized_index_bounds(l %ctx, l %v900, l %v901)
 jmp @failure
@success903
 # myl-obj %v898
 %v906 =l add %v898, 32
 %v907 =l loadl %v906
 # myl-elem %v907 8v
 %v904 =l mul %v900, 8
 %v905 =l add %v907, %v904
 %v908 =l loadl %v905
 storel %v908, %s0
 storel 39, %position
 %v909 =l loadl %ctx
 %v910 =l loadl %maxsteps
 %v911 =l ceql %v909, %v910
 jnz %v911, @step_limit, @step912
@step912
 %v912 =l add %v909, 1
 storel %v912, %ctx
 %v913 =l loadl %s0
 storel %v913, %l7
 %v916 =l add %rcguards, 32
 %v914 =w loaduw %v916
 jnz %v914, @rcslotdrop915, @rcslotdone915
@rcslotdrop915
 %v917 =l add %rcentries, 128
 call $myl_qbe_rc_slot_drop(l %ctx, l %v917)
@rcslotdone915
