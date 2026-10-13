
.tmp/lox-eda-parity/P1/call-env-001/baseline-lox:     file format elf64-x86-64


Disassembly of section .text:

0000000001073620 <my.interpreter::enter_function>:
 1073620:	55                   	push   %rbp
 1073621:	41 57                	push   %r15
 1073623:	41 56                	push   %r14
 1073625:	41 55                	push   %r13
 1073627:	41 54                	push   %r12
 1073629:	53                   	push   %rbx
 107362a:	48 81 ec d8 00 00 00 	sub    $0xd8,%rsp
 1073631:	4d 89 cc             	mov    %r9,%r12
 1073634:	49 89 fd             	mov    %rdi,%r13
 1073637:	48 8b b4 24 28 01 00 	mov    0x128(%rsp),%rsi
 107363e:	00 
 107363f:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1073643:	48 39 d6             	cmp    %rdx,%rsi
 1073646:	0f 83 af 02 00 00    	jae    10738fb <my.interpreter::enter_function+0x2db>
 107364c:	48 89 f0             	mov    %rsi,%rax
 107364f:	4c 8b b4 24 60 01 00 	mov    0x160(%rsp),%r14
 1073656:	00 
 1073657:	48 8d 04 80          	lea    (%rax,%rax,4),%rax
 107365b:	48 c1 e0 04          	shl    $0x4,%rax
 107365f:	48 8b 54 01 50       	mov    0x50(%rcx,%rax,1),%rdx
 1073664:	48 8b 7a 08          	mov    0x8(%rdx),%rdi
 1073668:	48 39 bc 24 50 01 00 	cmp    %rdi,0x150(%rsp)
 107366f:	00 
 1073670:	0f 85 16 01 00 00    	jne    107378c <my.interpreter::enter_function+0x16c>
 1073676:	48 8b b4 24 10 01 00 	mov    0x110(%rsp),%rsi
 107367d:	00 
 107367e:	48 89 f2             	mov    %rsi,%rdx
 1073681:	48 ff c2             	inc    %rdx
 1073684:	0f 80 69 03 00 00    	jo     10739f3 <my.interpreter::enter_function+0x3d3>
 107368a:	48 83 fa 40          	cmp    $0x40,%rdx
 107368e:	0f 8d 39 02 00 00    	jge    10738cd <my.interpreter::enter_function+0x2ad>
 1073694:	4c 89 6c 24 08       	mov    %r13,0x8(%rsp)
 1073699:	48 8b 94 24 48 01 00 	mov    0x148(%rsp),%rdx
 10736a0:	00 
 10736a1:	48 01 c8             	add    %rcx,%rax
 10736a4:	48 83 c0 20          	add    $0x20,%rax
 10736a8:	48 8b 48 48          	mov    0x48(%rax),%rcx
 10736ac:	48 8d 7c 24 10       	lea    0x10(%rsp),%rdi
 10736b1:	4c 89 e6             	mov    %r12,%rsi
 10736b4:	e8 77 8d ff ff       	call   106c430 <my.interpreter::new_env>
 10736b9:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 10736be:	48 83 bc 24 50 01 00 	cmpq   $0x0,0x150(%rsp)
 10736c5:	00 00 
 10736c7:	0f 8e 93 00 00 00    	jle    1073760 <my.interpreter::enter_function+0x140>
 10736cd:	4c 8b ac 24 58 01 00 	mov    0x158(%rsp),%r13
 10736d4:	00 
 10736d5:	49 8b 5c 24 78       	mov    0x78(%r12),%rbx
 10736da:	4c 8d 7b 20          	lea    0x20(%rbx),%r15
 10736de:	31 ed                	xor    %ebp,%ebp
 10736e0:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10736e7:	0f 1f 84 00 00 00 00 
 10736ee:	00 
 10736ef:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10736f6:	0f 1f 84 00 00 00 00 
 10736fd:	00 
 10736fe:	66 90                	xchg   %ax,%ax
 1073700:	4c 89 ee             	mov    %r13,%rsi
 1073703:	48 01 ee             	add    %rbp,%rsi
 1073706:	0f 80 d5 02 00 00    	jo     10739e1 <my.interpreter::enter_function+0x3c1>
 107370c:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1073710:	48 39 d6             	cmp    %rdx,%rsi
 1073713:	73 2d                	jae    1073742 <my.interpreter::enter_function+0x122>
 1073715:	48 89 f0             	mov    %rsi,%rax
 1073718:	48 c1 e0 04          	shl    $0x4,%rax
 107371c:	4d 8b 44 07 08       	mov    0x8(%r15,%rax,1),%r8
 1073721:	41 8b 0c 07          	mov    (%r15,%rax,1),%ecx
 1073725:	4c 89 e7             	mov    %r12,%rdi
 1073728:	4c 89 f6             	mov    %r14,%rsi
 107372b:	48 89 ea             	mov    %rbp,%rdx
 107372e:	e8 8d 8f ff ff       	call   106c6c0 <my.heap::set_env_slot>
 1073733:	48 ff c5             	inc    %rbp
 1073736:	48 39 ac 24 50 01 00 	cmp    %rbp,0x150(%rsp)
 107373d:	00 
 107373e:	75 c0                	jne    1073700 <my.interpreter::enter_function+0xe0>
 1073740:	eb 1e                	jmp    1073760 <my.interpreter::enter_function+0x140>
 1073742:	48 89 f0             	mov    %rsi,%rax
 1073745:	48 c1 f8 3f          	sar    $0x3f,%rax
 1073749:	48 21 d0             	and    %rdx,%rax
 107374c:	48 01 f0             	add    %rsi,%rax
 107374f:	48 39 d0             	cmp    %rdx,%rax
 1073752:	72 c4                	jb     1073718 <my.interpreter::enter_function+0xf8>
 1073754:	48 8d 3d 15 5f 01 00 	lea    0x15f15(%rip),%rdi        # 1089670 <core_durable_error.verbs+0x9660>
 107375b:	e8 e0 14 fb ff       	call   1024c40 <myl_core_trap>
 1073760:	4c 8b 6c 24 08       	mov    0x8(%rsp),%r13
 1073765:	49 c7 45 00 00 00 00 	movq   $0x0,0x0(%r13)
 107376c:	00 
 107376d:	b8 08 00 00 00       	mov    $0x8,%eax
 1073772:	4d 89 74 05 00       	mov    %r14,0x0(%r13,%rax,1)
 1073777:	4c 89 e8             	mov    %r13,%rax
 107377a:	48 81 c4 d8 00 00 00 	add    $0xd8,%rsp
 1073781:	5b                   	pop    %rbx
 1073782:	41 5c                	pop    %r12
 1073784:	41 5d                	pop    %r13
 1073786:	41 5e                	pop    %r14
 1073788:	41 5f                	pop    %r15
 107378a:	5d                   	pop    %rbp
 107378b:	c3                   	ret
 107378c:	64 4c 8b 24 25 d8 fe 	mov    %fs:0xfffffffffffffed8,%r12
 1073793:	ff ff 
 1073795:	4d 85 e4             	test   %r12,%r12
 1073798:	0f 84 7f 01 00 00    	je     107391d <my.interpreter::enter_function+0x2fd>
 107379e:	49 8b 04 24          	mov    (%r12),%rax
 10737a2:	64 48 89 04 25 d8 fe 	mov    %rax,%fs:0xfffffffffffffed8
 10737a9:	ff ff 
 10737ab:	41 c7 04 24 00 00 00 	movl   $0x3000000,(%r12)
 10737b2:	03 
 10737b3:	49 c7 44 24 08 00 00 	movq   $0x0,0x8(%r12)
 10737ba:	00 00 
 10737bc:	49 c7 44 24 10 08 00 	movq   $0x8,0x10(%r12)
 10737c3:	00 00 
 10737c5:	48 8d 05 7c 09 fa ff 	lea    -0x5f684(%rip),%rax        # 1014148 <core_number_pairs+0xcee8>
 10737cc:	49 89 44 24 18       	mov    %rax,0x18(%r12)
 10737d1:	31 c0                	xor    %eax,%eax
 10737d3:	48 8d 0d 46 ec f9 ff 	lea    -0x613ba(%rip),%rcx        # 1012420 <core_number_pairs+0xb1c0>
 10737da:	49 89 4c c4 20       	mov    %rcx,0x20(%r12,%rax,8)
 10737df:	48 ff c0             	inc    %rax
 10737e2:	49 89 44 24 08       	mov    %rax,0x8(%r12)
 10737e7:	e8 54 96 fc ff       	call   103ce40 <myl_core_str_from_i64>
 10737ec:	49 8b 4c 24 08       	mov    0x8(%r12),%rcx
 10737f1:	49 8b 54 24 10       	mov    0x10(%r12),%rdx
 10737f6:	48 39 d1             	cmp    %rdx,%rcx
 10737f9:	0f 83 66 01 00 00    	jae    1073965 <my.interpreter::enter_function+0x345>
 10737ff:	49 89 44 cc 20       	mov    %rax,0x20(%r12,%rcx,8)
 1073804:	48 ff c1             	inc    %rcx
 1073807:	49 89 4c 24 08       	mov    %rcx,0x8(%r12)
 107380c:	48 39 d1             	cmp    %rdx,%rcx
 107380f:	0f 83 75 01 00 00    	jae    107398a <my.interpreter::enter_function+0x36a>
 1073815:	48 8d 05 44 ec f9 ff 	lea    -0x613bc(%rip),%rax        # 1012460 <core_number_pairs+0xb200>
 107381c:	49 89 44 cc 20       	mov    %rax,0x20(%r12,%rcx,8)
 1073821:	48 ff c1             	inc    %rcx
 1073824:	49 89 4c 24 08       	mov    %rcx,0x8(%r12)
 1073829:	48 8b bc 24 50 01 00 	mov    0x150(%rsp),%rdi
 1073830:	00 
 1073831:	e8 0a 96 fc ff       	call   103ce40 <myl_core_str_from_i64>
 1073836:	49 8b 4c 24 08       	mov    0x8(%r12),%rcx
 107383b:	49 8b 54 24 10       	mov    0x10(%r12),%rdx
 1073840:	48 39 d1             	cmp    %rdx,%rcx
 1073843:	0f 83 5a 01 00 00    	jae    10739a3 <my.interpreter::enter_function+0x383>
 1073849:	49 89 44 cc 20       	mov    %rax,0x20(%r12,%rcx,8)
 107384e:	48 ff c1             	inc    %rcx
 1073851:	49 89 4c 24 08       	mov    %rcx,0x8(%r12)
 1073856:	48 39 d1             	cmp    %rdx,%rcx
 1073859:	0f 83 69 01 00 00    	jae    10739c8 <my.interpreter::enter_function+0x3a8>
 107385f:	48 8d 05 3a ec f9 ff 	lea    -0x613c6(%rip),%rax        # 10124a0 <core_number_pairs+0xb240>
 1073866:	49 89 44 cc 20       	mov    %rax,0x20(%r12,%rcx,8)
 107386b:	48 ff c1             	inc    %rcx
 107386e:	49 89 4c 24 08       	mov    %rcx,0x8(%r12)
 1073873:	48 8d 3d 46 e7 f9 ff 	lea    -0x618ba(%rip),%rdi        # 1011fc0 <core_number_pairs+0xad60>
 107387a:	4c 89 e6             	mov    %r12,%rsi
 107387d:	e8 3e 99 fb ff       	call   102d1c0 <myl_core_str_join>
 1073882:	49 89 c7             	mov    %rax,%r15
 1073885:	4c 89 e7             	mov    %r12,%rdi
 1073888:	e8 33 06 fb ff       	call   1023ec0 <myl_core_drop_owned>
 107388d:	4c 89 ff             	mov    %r15,%rdi
 1073890:	e8 6b bc fb ff       	call   102f500 <myl_core_text_encode>
 1073895:	49 89 c4             	mov    %rax,%r12
 1073898:	4c 89 ff             	mov    %r15,%rdi
 107389b:	e8 20 06 fb ff       	call   1023ec0 <myl_core_drop_owned>
 10738a0:	4c 89 e7             	mov    %r12,%rdi
 10738a3:	e8 98 0e fb ff       	call   1024740 <myl_core_owned_octets_copy>
 10738a8:	49 89 c7             	mov    %rax,%r15
 10738ab:	4c 89 e7             	mov    %r12,%rdi
 10738ae:	e8 0d 06 fb ff       	call   1023ec0 <myl_core_drop_owned>
 10738b3:	48 8d 3d f6 5c 01 00 	lea    0x15cf6(%rip),%rdi        # 10895b0 <core_durable_error.verbs+0x95a0>
 10738ba:	e8 81 37 fe ff       	call   1057040 <myl_core_err_trace_origin_preserve_most>
 10738bf:	49 c7 45 00 01 00 00 	movq   $0x1,0x0(%r13)
 10738c6:	00 
 10738c7:	4d 89 7d 08          	mov    %r15,0x8(%r13)
 10738cb:	eb 24                	jmp    10738f1 <my.interpreter::enter_function+0x2d1>
 10738cd:	48 8d 3d 8c ea f9 ff 	lea    -0x61574(%rip),%rdi        # 1012360 <core_number_pairs+0xb100>
 10738d4:	e8 67 0e fb ff       	call   1024740 <myl_core_owned_octets_copy>
 10738d9:	48 8d 3d 30 5d 01 00 	lea    0x15d30(%rip),%rdi        # 1089610 <core_durable_error.verbs+0x9600>
 10738e0:	e8 5b 37 fe ff       	call   1057040 <myl_core_err_trace_origin_preserve_most>
 10738e5:	49 c7 45 00 01 00 00 	movq   $0x1,0x0(%r13)
 10738ec:	00 
 10738ed:	49 89 45 08          	mov    %rax,0x8(%r13)
 10738f1:	b8 10 00 00 00       	mov    $0x10,%eax
 10738f6:	e9 77 fe ff ff       	jmp    1073772 <my.interpreter::enter_function+0x152>
 10738fb:	48 89 f0             	mov    %rsi,%rax
 10738fe:	48 c1 f8 3f          	sar    $0x3f,%rax
 1073902:	48 21 d0             	and    %rdx,%rax
 1073905:	48 01 f0             	add    %rsi,%rax
 1073908:	48 39 d0             	cmp    %rdx,%rax
 107390b:	0f 82 3e fd ff ff    	jb     107364f <my.interpreter::enter_function+0x2f>
 1073911:	48 8d 3d 68 5c 01 00 	lea    0x15c68(%rip),%rdi        # 1089580 <core_durable_error.verbs+0x9570>
 1073918:	e8 23 13 fb ff       	call   1024c40 <myl_core_trap>
 107391d:	48 89 fb             	mov    %rdi,%rbx
 1073920:	bf 05 00 00 00       	mov    $0x5,%edi
 1073925:	be 08 00 00 00       	mov    $0x8,%esi
 107392a:	e8 d1 f7 fa ff       	call   1023100 <myl_core_list_new_slow>
 107392f:	49 89 c4             	mov    %rax,%r12
 1073932:	48 8b 40 08          	mov    0x8(%rax),%rax
 1073936:	49 3b 44 24 10       	cmp    0x10(%r12),%rax
 107393b:	48 8d 0d 06 08 fa ff 	lea    -0x5f7fa(%rip),%rcx        # 1014148 <core_number_pairs+0xcee8>
 1073942:	49 89 4c 24 18       	mov    %rcx,0x18(%r12)
 1073947:	72 14                	jb     107395d <my.interpreter::enter_function+0x33d>
 1073949:	be 08 00 00 00       	mov    $0x8,%esi
 107394e:	4c 89 e7             	mov    %r12,%rdi
 1073951:	e8 6a f8 fa ff       	call   10231c0 <myl_core_list_grow>
 1073956:	49 89 c4             	mov    %rax,%r12
 1073959:	48 8b 40 08          	mov    0x8(%rax),%rax
 107395d:	48 89 df             	mov    %rbx,%rdi
 1073960:	e9 6e fe ff ff       	jmp    10737d3 <my.interpreter::enter_function+0x1b3>
 1073965:	be 08 00 00 00       	mov    $0x8,%esi
 107396a:	4c 89 e7             	mov    %r12,%rdi
 107396d:	48 89 c3             	mov    %rax,%rbx
 1073970:	e8 4b f8 fa ff       	call   10231c0 <myl_core_list_grow>
 1073975:	49 89 c4             	mov    %rax,%r12
 1073978:	48 89 d8             	mov    %rbx,%rax
 107397b:	49 8b 4c 24 08       	mov    0x8(%r12),%rcx
 1073980:	49 8b 54 24 10       	mov    0x10(%r12),%rdx
 1073985:	e9 75 fe ff ff       	jmp    10737ff <my.interpreter::enter_function+0x1df>
 107398a:	be 08 00 00 00       	mov    $0x8,%esi
 107398f:	4c 89 e7             	mov    %r12,%rdi
 1073992:	e8 29 f8 fa ff       	call   10231c0 <myl_core_list_grow>
 1073997:	49 89 c4             	mov    %rax,%r12
 107399a:	48 8b 48 08          	mov    0x8(%rax),%rcx
 107399e:	e9 72 fe ff ff       	jmp    1073815 <my.interpreter::enter_function+0x1f5>
 10739a3:	be 08 00 00 00       	mov    $0x8,%esi
 10739a8:	4c 89 e7             	mov    %r12,%rdi
 10739ab:	48 89 c3             	mov    %rax,%rbx
 10739ae:	e8 0d f8 fa ff       	call   10231c0 <myl_core_list_grow>
 10739b3:	49 89 c4             	mov    %rax,%r12
 10739b6:	48 89 d8             	mov    %rbx,%rax
 10739b9:	49 8b 4c 24 08       	mov    0x8(%r12),%rcx
 10739be:	49 8b 54 24 10       	mov    0x10(%r12),%rdx
 10739c3:	e9 81 fe ff ff       	jmp    1073849 <my.interpreter::enter_function+0x229>
 10739c8:	be 08 00 00 00       	mov    $0x8,%esi
 10739cd:	4c 89 e7             	mov    %r12,%rdi
 10739d0:	e8 eb f7 fa ff       	call   10231c0 <myl_core_list_grow>
 10739d5:	49 89 c4             	mov    %rax,%r12
 10739d8:	48 8b 48 08          	mov    0x8(%rax),%rcx
 10739dc:	e9 7e fe ff ff       	jmp    107385f <my.interpreter::enter_function+0x23f>
 10739e1:	48 8d 3d 58 5c 01 00 	lea    0x15c58(%rip),%rdi        # 1089640 <core_durable_error.verbs+0x9630>
 10739e8:	4c 89 ee             	mov    %r13,%rsi
 10739eb:	48 89 ea             	mov    %rbp,%rdx
 10739ee:	e8 4d 12 fb ff       	call   1024c40 <myl_core_trap>
 10739f3:	48 8d 3d e6 5b 01 00 	lea    0x15be6(%rip),%rdi        # 10895e0 <core_durable_error.verbs+0x95d0>
 10739fa:	ba 01 00 00 00       	mov    $0x1,%edx
 10739ff:	e8 3c 12 fb ff       	call   1024c40 <myl_core_trap>
