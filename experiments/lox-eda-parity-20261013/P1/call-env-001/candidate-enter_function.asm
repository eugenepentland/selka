
.tmp/lox-eda-parity/P1/call-env-001/candidate-lox:     file format elf64-x86-64


Disassembly of section .text:

00000000010737c0 <my.interpreter::enter_function>:
 10737c0:	55                   	push   %rbp
 10737c1:	41 57                	push   %r15
 10737c3:	41 56                	push   %r14
 10737c5:	41 55                	push   %r13
 10737c7:	41 54                	push   %r12
 10737c9:	53                   	push   %rbx
 10737ca:	48 81 ec d8 00 00 00 	sub    $0xd8,%rsp
 10737d1:	4d 89 cc             	mov    %r9,%r12
 10737d4:	49 89 fd             	mov    %rdi,%r13
 10737d7:	48 8b b4 24 28 01 00 	mov    0x128(%rsp),%rsi
 10737de:	00 
 10737df:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 10737e3:	48 39 d6             	cmp    %rdx,%rsi
 10737e6:	0f 83 6f 03 00 00    	jae    1073b5b <my.interpreter::enter_function+0x39b>
 10737ec:	48 89 f0             	mov    %rsi,%rax
 10737ef:	4c 8b b4 24 60 01 00 	mov    0x160(%rsp),%r14
 10737f6:	00 
 10737f7:	4c 8b bc 24 50 01 00 	mov    0x150(%rsp),%r15
 10737fe:	00 
 10737ff:	48 8d 04 80          	lea    (%rax,%rax,4),%rax
 1073803:	48 c1 e0 04          	shl    $0x4,%rax
 1073807:	48 8b 54 01 50       	mov    0x50(%rcx,%rax,1),%rdx
 107380c:	48 8b 7a 08          	mov    0x8(%rdx),%rdi
 1073810:	49 39 ff             	cmp    %rdi,%r15
 1073813:	0f 85 d8 01 00 00    	jne    10739f1 <my.interpreter::enter_function+0x231>
 1073819:	48 8b b4 24 10 01 00 	mov    0x110(%rsp),%rsi
 1073820:	00 
 1073821:	48 89 f2             	mov    %rsi,%rdx
 1073824:	48 ff c2             	inc    %rdx
 1073827:	0f 80 94 04 00 00    	jo     1073cc1 <my.interpreter::enter_function+0x501>
 107382d:	48 83 fa 40          	cmp    $0x40,%rdx
 1073831:	0f 8d f6 02 00 00    	jge    1073b2d <my.interpreter::enter_function+0x36d>
 1073837:	4c 89 6c 24 08       	mov    %r13,0x8(%rsp)
 107383c:	4d 85 ff             	test   %r15,%r15
 107383f:	0f 88 64 04 00 00    	js     1073ca9 <my.interpreter::enter_function+0x4e9>
 1073845:	48 01 c8             	add    %rcx,%rax
 1073848:	48 83 c0 20          	add    $0x20,%rax
 107384c:	48 8b 68 48          	mov    0x48(%rax),%rbp
 1073850:	48 89 e8             	mov    %rbp,%rax
 1073853:	48 c1 f8 3f          	sar    $0x3f,%rax
 1073857:	c4 e2 f8 f2 d5       	andn   %rbp,%rax,%rdx
 107385c:	49 39 d7             	cmp    %rdx,%r15
 107385f:	0f 87 44 04 00 00    	ja     1073ca9 <my.interpreter::enter_function+0x4e9>
 1073865:	4c 8b ac 24 58 01 00 	mov    0x158(%rsp),%r13
 107386c:	00 
 107386d:	4d 85 ed             	test   %r13,%r13
 1073870:	0f 88 3f 04 00 00    	js     1073cb5 <my.interpreter::enter_function+0x4f5>
 1073876:	49 8b 84 24 80 00 00 	mov    0x80(%r12),%rax
 107387d:	00 
 107387e:	4c 29 e8             	sub    %r13,%rax
 1073881:	0f 8c 2e 04 00 00    	jl     1073cb5 <my.interpreter::enter_function+0x4f5>
 1073887:	49 39 c7             	cmp    %rax,%r15
 107388a:	0f 8f 25 04 00 00    	jg     1073cb5 <my.interpreter::enter_function+0x4f5>
 1073890:	48 b8 ff ff ff ff ff 	movabs $0x7ffffffffffffff,%rax
 1073897:	ff ff 07 
 107389a:	48 39 c5             	cmp    %rax,%rbp
 107389d:	0f 8f 2f 04 00 00    	jg     1073cd2 <my.interpreter::enter_function+0x512>
 10738a3:	48 c1 e2 04          	shl    $0x4,%rdx
 10738a7:	48 89 d0             	mov    %rdx,%rax
 10738aa:	48 83 c0 20          	add    $0x20,%rax
 10738ae:	0f 80 2f 04 00 00    	jo     1073ce3 <my.interpreter::enter_function+0x523>
 10738b4:	48 8b 9c 24 48 01 00 	mov    0x148(%rsp),%rbx
 10738bb:	00 
 10738bc:	48 8d 7c 24 10       	lea    0x10(%rsp),%rdi
 10738c1:	4c 89 e6             	mov    %r12,%rsi
 10738c4:	48 89 c2             	mov    %rax,%rdx
 10738c7:	e8 84 de fe ff       	call   1061750 <my.heap::reserve_object>
 10738cc:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 10738d1:	48 89 df             	mov    %rbx,%rdi
 10738d4:	48 89 ee             	mov    %rbp,%rsi
 10738d7:	e8 c4 fc ff ff       	call   10735a0 <my.object::new_env>
 10738dc:	4d 85 ff             	test   %r15,%r15
 10738df:	0f 84 5c 00 00 00    	je     1073941 <my.interpreter::enter_function+0x181>
 10738e5:	49 8b 7c 24 78       	mov    0x78(%r12),%rdi
 10738ea:	4c 8d 4f 20          	lea    0x20(%rdi),%r9
 10738ee:	49 89 d2             	mov    %rdx,%r10
 10738f1:	49 83 c2 20          	add    $0x20,%r10
 10738f5:	31 c9                	xor    %ecx,%ecx
 10738f7:	c5 f8 28 05 e1 0a f9 	vmovaps -0x6f51f(%rip),%xmm0        # 10043e0 <__anon_2214+0xb0>
 10738fe:	ff 
 10738ff:	90                   	nop
 1073900:	4c 89 ee             	mov    %r13,%rsi
 1073903:	48 01 ce             	add    %rcx,%rsi
 1073906:	0f 80 5d 03 00 00    	jo     1073c69 <my.interpreter::enter_function+0x4a9>
 107390c:	4c 8b 47 08          	mov    0x8(%rdi),%r8
 1073910:	4c 39 c6             	cmp    %r8,%rsi
 1073913:	0f 83 74 03 00 00    	jae    1073c8d <my.interpreter::enter_function+0x4cd>
 1073919:	4c 8b 42 08          	mov    0x8(%rdx),%r8
 107391d:	4c 39 c1             	cmp    %r8,%rcx
 1073920:	0f 83 55 03 00 00    	jae    1073c7b <my.interpreter::enter_function+0x4bb>
 1073926:	48 c1 e6 04          	shl    $0x4,%rsi
 107392a:	c4 c1 78 54 0c 31    	vandps (%r9,%rsi,1),%xmm0,%xmm1
 1073930:	c4 c1 78 11 0a       	vmovups %xmm1,(%r10)
 1073935:	48 ff c1             	inc    %rcx
 1073938:	49 83 c2 10          	add    $0x10,%r10
 107393c:	49 39 cf             	cmp    %rcx,%r15
 107393f:	75 bf                	jne    1073900 <my.interpreter::enter_function+0x140>
 1073941:	49 8b 34 24          	mov    (%r12),%rsi
 1073945:	48 8b 4e 08          	mov    0x8(%rsi),%rcx
 1073949:	4c 89 f7             	mov    %r14,%rdi
 107394c:	49 39 ce             	cmp    %rcx,%r14
 107394f:	0f 83 28 02 00 00    	jae    1073b7d <my.interpreter::enter_function+0x3bd>
 1073955:	4c 6b d7 38          	imul   $0x38,%rdi,%r10
 1073959:	46 0f b6 44 16 20    	movzbl 0x20(%rsi,%r10,1),%r8d
 107395f:	4a 8b 7c 16 28       	mov    0x28(%rsi,%r10,1),%rdi
 1073964:	4e 8b 4c 16 30       	mov    0x30(%rsi,%r10,1),%r9
 1073969:	4a 8b 4c 16 38       	mov    0x38(%rsi,%r10,1),%rcx
 107396e:	4e 8b 7c 16 40       	mov    0x40(%rsi,%r10,1),%r15
 1073973:	4a 8b 5c 16 48       	mov    0x48(%rsi,%r10,1),%rbx
 1073978:	4a c7 44 16 20 09 00 	movq   $0x9,0x20(%rsi,%r10,1)
 107397f:	00 00 
 1073981:	4a 89 44 16 28       	mov    %rax,0x28(%rsi,%r10,1)
 1073986:	4a 89 54 16 30       	mov    %rdx,0x30(%rsi,%r10,1)
 107398b:	41 83 f8 09          	cmp    $0x9,%r8d
 107398f:	4c 8b 6c 24 08       	mov    0x8(%rsp),%r13
 1073994:	77 13                	ja     10739a9 <my.interpreter::enter_function+0x1e9>
 1073996:	b8 d0 02 00 00       	mov    $0x2d0,%eax
 107399b:	44 0f a3 c0          	bt     %r8d,%eax
 107399f:	73 2f                	jae    10739d0 <my.interpreter::enter_function+0x210>
 10739a1:	4c 89 cf             	mov    %r9,%rdi
 10739a4:	e8 97 06 fb ff       	call   1024040 <myl_core_drop_owned>
 10739a9:	49 c7 45 00 00 00 00 	movq   $0x0,0x0(%r13)
 10739b0:	00 
 10739b1:	b8 08 00 00 00       	mov    $0x8,%eax
 10739b6:	4d 89 74 05 00       	mov    %r14,0x0(%r13,%rax,1)
 10739bb:	4c 89 e8             	mov    %r13,%rax
 10739be:	48 81 c4 d8 00 00 00 	add    $0xd8,%rsp
 10739c5:	5b                   	pop    %rbx
 10739c6:	41 5c                	pop    %r12
 10739c8:	41 5d                	pop    %r13
 10739ca:	41 5e                	pop    %r14
 10739cc:	41 5f                	pop    %r15
 10739ce:	5d                   	pop    %rbp
 10739cf:	c3                   	ret
 10739d0:	41 83 f8 01          	cmp    $0x1,%r8d
 10739d4:	74 ce                	je     10739a4 <my.interpreter::enter_function+0x1e4>
 10739d6:	41 83 f8 02          	cmp    $0x2,%r8d
 10739da:	75 cd                	jne    10739a9 <my.interpreter::enter_function+0x1e9>
 10739dc:	48 89 cf             	mov    %rcx,%rdi
 10739df:	e8 5c 06 fb ff       	call   1024040 <myl_core_drop_owned>
 10739e4:	4c 89 ff             	mov    %r15,%rdi
 10739e7:	e8 54 06 fb ff       	call   1024040 <myl_core_drop_owned>
 10739ec:	48 89 df             	mov    %rbx,%rdi
 10739ef:	eb b3                	jmp    10739a4 <my.interpreter::enter_function+0x1e4>
 10739f1:	64 4c 8b 24 25 d8 fe 	mov    %fs:0xfffffffffffffed8,%r12
 10739f8:	ff ff 
 10739fa:	4d 85 e4             	test   %r12,%r12
 10739fd:	0f 84 a2 01 00 00    	je     1073ba5 <my.interpreter::enter_function+0x3e5>
 1073a03:	49 8b 04 24          	mov    (%r12),%rax
 1073a07:	64 48 89 04 25 d8 fe 	mov    %rax,%fs:0xfffffffffffffed8
 1073a0e:	ff ff 
 1073a10:	41 c7 04 24 00 00 00 	movl   $0x3000000,(%r12)
 1073a17:	03 
 1073a18:	49 c7 44 24 08 00 00 	movq   $0x0,0x8(%r12)
 1073a1f:	00 00 
 1073a21:	49 c7 44 24 10 08 00 	movq   $0x8,0x10(%r12)
 1073a28:	00 00 
 1073a2a:	48 8d 05 77 08 fa ff 	lea    -0x5f789(%rip),%rax        # 10142a8 <core_number_pairs+0xd048>
 1073a31:	49 89 44 24 18       	mov    %rax,0x18(%r12)
 1073a36:	31 c0                	xor    %eax,%eax
 1073a38:	48 8d 0d 41 eb f9 ff 	lea    -0x614bf(%rip),%rcx        # 1012580 <core_number_pairs+0xb320>
 1073a3f:	49 89 4c c4 20       	mov    %rcx,0x20(%r12,%rax,8)
 1073a44:	48 ff c0             	inc    %rax
 1073a47:	49 89 44 24 08       	mov    %rax,0x8(%r12)
 1073a4c:	e8 6f 95 fc ff       	call   103cfc0 <myl_core_str_from_i64>
 1073a51:	49 8b 4c 24 08       	mov    0x8(%r12),%rcx
 1073a56:	49 8b 54 24 10       	mov    0x10(%r12),%rdx
 1073a5b:	48 39 d1             	cmp    %rdx,%rcx
 1073a5e:	0f 83 89 01 00 00    	jae    1073bed <my.interpreter::enter_function+0x42d>
 1073a64:	49 89 44 cc 20       	mov    %rax,0x20(%r12,%rcx,8)
 1073a69:	48 ff c1             	inc    %rcx
 1073a6c:	49 89 4c 24 08       	mov    %rcx,0x8(%r12)
 1073a71:	48 39 d1             	cmp    %rdx,%rcx
 1073a74:	0f 83 98 01 00 00    	jae    1073c12 <my.interpreter::enter_function+0x452>
 1073a7a:	48 8d 05 3f eb f9 ff 	lea    -0x614c1(%rip),%rax        # 10125c0 <core_number_pairs+0xb360>
 1073a81:	49 89 44 cc 20       	mov    %rax,0x20(%r12,%rcx,8)
 1073a86:	48 ff c1             	inc    %rcx
 1073a89:	49 89 4c 24 08       	mov    %rcx,0x8(%r12)
 1073a8e:	4c 89 ff             	mov    %r15,%rdi
 1073a91:	e8 2a 95 fc ff       	call   103cfc0 <myl_core_str_from_i64>
 1073a96:	49 8b 4c 24 08       	mov    0x8(%r12),%rcx
 1073a9b:	49 8b 54 24 10       	mov    0x10(%r12),%rdx
 1073aa0:	48 39 d1             	cmp    %rdx,%rcx
 1073aa3:	0f 83 82 01 00 00    	jae    1073c2b <my.interpreter::enter_function+0x46b>
 1073aa9:	49 89 44 cc 20       	mov    %rax,0x20(%r12,%rcx,8)
 1073aae:	48 ff c1             	inc    %rcx
 1073ab1:	49 89 4c 24 08       	mov    %rcx,0x8(%r12)
 1073ab6:	48 39 d1             	cmp    %rdx,%rcx
 1073ab9:	0f 83 91 01 00 00    	jae    1073c50 <my.interpreter::enter_function+0x490>
 1073abf:	48 8d 05 3a eb f9 ff 	lea    -0x614c6(%rip),%rax        # 1012600 <core_number_pairs+0xb3a0>
 1073ac6:	49 89 44 cc 20       	mov    %rax,0x20(%r12,%rcx,8)
 1073acb:	48 ff c1             	inc    %rcx
 1073ace:	49 89 4c 24 08       	mov    %rcx,0x8(%r12)
 1073ad3:	48 8d 3d 46 e6 f9 ff 	lea    -0x619ba(%rip),%rdi        # 1012120 <core_number_pairs+0xaec0>
 1073ada:	4c 89 e6             	mov    %r12,%rsi
 1073add:	e8 5e 98 fb ff       	call   102d340 <myl_core_str_join>
 1073ae2:	49 89 c7             	mov    %rax,%r15
 1073ae5:	4c 89 e7             	mov    %r12,%rdi
 1073ae8:	e8 53 05 fb ff       	call   1024040 <myl_core_drop_owned>
 1073aed:	4c 89 ff             	mov    %r15,%rdi
 1073af0:	e8 8b bb fb ff       	call   102f680 <myl_core_text_encode>
 1073af5:	49 89 c4             	mov    %rax,%r12
 1073af8:	4c 89 ff             	mov    %r15,%rdi
 1073afb:	e8 40 05 fb ff       	call   1024040 <myl_core_drop_owned>
 1073b00:	4c 89 e7             	mov    %r12,%rdi
 1073b03:	e8 b8 0d fb ff       	call   10248c0 <myl_core_owned_octets_copy>
 1073b08:	49 89 c7             	mov    %rax,%r15
 1073b0b:	4c 89 e7             	mov    %r12,%rdi
 1073b0e:	e8 2d 05 fb ff       	call   1024040 <myl_core_drop_owned>
 1073b13:	48 8d 3d 96 5d 01 00 	lea    0x15d96(%rip),%rdi        # 10898b0 <core_durable_error.verbs+0x95a0>
 1073b1a:	e8 a1 36 fe ff       	call   10571c0 <myl_core_err_trace_origin_preserve_most>
 1073b1f:	49 c7 45 00 01 00 00 	movq   $0x1,0x0(%r13)
 1073b26:	00 
 1073b27:	4d 89 7d 08          	mov    %r15,0x8(%r13)
 1073b2b:	eb 24                	jmp    1073b51 <my.interpreter::enter_function+0x391>
 1073b2d:	48 8d 3d 8c e9 f9 ff 	lea    -0x61674(%rip),%rdi        # 10124c0 <core_number_pairs+0xb260>
 1073b34:	e8 87 0d fb ff       	call   10248c0 <myl_core_owned_octets_copy>
 1073b39:	48 8d 3d d0 5d 01 00 	lea    0x15dd0(%rip),%rdi        # 1089910 <core_durable_error.verbs+0x9600>
 1073b40:	e8 7b 36 fe ff       	call   10571c0 <myl_core_err_trace_origin_preserve_most>
 1073b45:	49 c7 45 00 01 00 00 	movq   $0x1,0x0(%r13)
 1073b4c:	00 
 1073b4d:	49 89 45 08          	mov    %rax,0x8(%r13)
 1073b51:	b8 10 00 00 00       	mov    $0x10,%eax
 1073b56:	e9 5b fe ff ff       	jmp    10739b6 <my.interpreter::enter_function+0x1f6>
 1073b5b:	48 89 f0             	mov    %rsi,%rax
 1073b5e:	48 c1 f8 3f          	sar    $0x3f,%rax
 1073b62:	48 21 d0             	and    %rdx,%rax
 1073b65:	48 01 f0             	add    %rsi,%rax
 1073b68:	48 39 d0             	cmp    %rdx,%rax
 1073b6b:	0f 82 7e fc ff ff    	jb     10737ef <my.interpreter::enter_function+0x2f>
 1073b71:	48 8d 3d 08 5d 01 00 	lea    0x15d08(%rip),%rdi        # 1089880 <core_durable_error.verbs+0x9570>
 1073b78:	e8 43 12 fb ff       	call   1024dc0 <myl_core_trap>
 1073b7d:	4c 89 f7             	mov    %r14,%rdi
 1073b80:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1073b84:	48 21 cf             	and    %rcx,%rdi
 1073b87:	4c 01 f7             	add    %r14,%rdi
 1073b8a:	48 39 cf             	cmp    %rcx,%rdi
 1073b8d:	0f 82 c2 fd ff ff    	jb     1073955 <my.interpreter::enter_function+0x195>
 1073b93:	48 8d 3d 06 64 01 00 	lea    0x16406(%rip),%rdi        # 1089fa0 <core_durable_error.verbs+0x9c90>
 1073b9a:	4c 89 f6             	mov    %r14,%rsi
 1073b9d:	48 89 ca             	mov    %rcx,%rdx
 1073ba0:	e8 1b 12 fb ff       	call   1024dc0 <myl_core_trap>
 1073ba5:	48 89 fb             	mov    %rdi,%rbx
 1073ba8:	bf 05 00 00 00       	mov    $0x5,%edi
 1073bad:	be 08 00 00 00       	mov    $0x8,%esi
 1073bb2:	e8 c9 f6 fa ff       	call   1023280 <myl_core_list_new_slow>
 1073bb7:	49 89 c4             	mov    %rax,%r12
 1073bba:	48 8b 40 08          	mov    0x8(%rax),%rax
 1073bbe:	49 3b 44 24 10       	cmp    0x10(%r12),%rax
 1073bc3:	48 8d 0d de 06 fa ff 	lea    -0x5f922(%rip),%rcx        # 10142a8 <core_number_pairs+0xd048>
 1073bca:	49 89 4c 24 18       	mov    %rcx,0x18(%r12)
 1073bcf:	72 14                	jb     1073be5 <my.interpreter::enter_function+0x425>
 1073bd1:	be 08 00 00 00       	mov    $0x8,%esi
 1073bd6:	4c 89 e7             	mov    %r12,%rdi
 1073bd9:	e8 62 f7 fa ff       	call   1023340 <myl_core_list_grow>
 1073bde:	49 89 c4             	mov    %rax,%r12
 1073be1:	48 8b 40 08          	mov    0x8(%rax),%rax
 1073be5:	48 89 df             	mov    %rbx,%rdi
 1073be8:	e9 4b fe ff ff       	jmp    1073a38 <my.interpreter::enter_function+0x278>
 1073bed:	be 08 00 00 00       	mov    $0x8,%esi
 1073bf2:	4c 89 e7             	mov    %r12,%rdi
 1073bf5:	48 89 c3             	mov    %rax,%rbx
 1073bf8:	e8 43 f7 fa ff       	call   1023340 <myl_core_list_grow>
 1073bfd:	49 89 c4             	mov    %rax,%r12
 1073c00:	48 89 d8             	mov    %rbx,%rax
 1073c03:	49 8b 4c 24 08       	mov    0x8(%r12),%rcx
 1073c08:	49 8b 54 24 10       	mov    0x10(%r12),%rdx
 1073c0d:	e9 52 fe ff ff       	jmp    1073a64 <my.interpreter::enter_function+0x2a4>
 1073c12:	be 08 00 00 00       	mov    $0x8,%esi
 1073c17:	4c 89 e7             	mov    %r12,%rdi
 1073c1a:	e8 21 f7 fa ff       	call   1023340 <myl_core_list_grow>
 1073c1f:	49 89 c4             	mov    %rax,%r12
 1073c22:	48 8b 48 08          	mov    0x8(%rax),%rcx
 1073c26:	e9 4f fe ff ff       	jmp    1073a7a <my.interpreter::enter_function+0x2ba>
 1073c2b:	be 08 00 00 00       	mov    $0x8,%esi
 1073c30:	4c 89 e7             	mov    %r12,%rdi
 1073c33:	48 89 c3             	mov    %rax,%rbx
 1073c36:	e8 05 f7 fa ff       	call   1023340 <myl_core_list_grow>
 1073c3b:	49 89 c4             	mov    %rax,%r12
 1073c3e:	48 89 d8             	mov    %rbx,%rax
 1073c41:	49 8b 4c 24 08       	mov    0x8(%r12),%rcx
 1073c46:	49 8b 54 24 10       	mov    0x10(%r12),%rdx
 1073c4b:	e9 59 fe ff ff       	jmp    1073aa9 <my.interpreter::enter_function+0x2e9>
 1073c50:	be 08 00 00 00       	mov    $0x8,%esi
 1073c55:	4c 89 e7             	mov    %r12,%rdi
 1073c58:	e8 e3 f6 fa ff       	call   1023340 <myl_core_list_grow>
 1073c5d:	49 89 c4             	mov    %rax,%r12
 1073c60:	48 8b 48 08          	mov    0x8(%rax),%rcx
 1073c64:	e9 56 fe ff ff       	jmp    1073abf <my.interpreter::enter_function+0x2ff>
 1073c69:	48 8d 3d a0 62 01 00 	lea    0x162a0(%rip),%rdi        # 1089f10 <core_durable_error.verbs+0x9c00>
 1073c70:	4c 89 ee             	mov    %r13,%rsi
 1073c73:	48 89 ca             	mov    %rcx,%rdx
 1073c76:	e8 45 11 fb ff       	call   1024dc0 <myl_core_trap>
 1073c7b:	48 8d 3d ee 62 01 00 	lea    0x162ee(%rip),%rdi        # 1089f70 <core_durable_error.verbs+0x9c60>
 1073c82:	48 89 ce             	mov    %rcx,%rsi
 1073c85:	4c 89 c2             	mov    %r8,%rdx
 1073c88:	e8 33 11 fb ff       	call   1024dc0 <myl_core_trap>
 1073c8d:	48 89 f0             	mov    %rsi,%rax
 1073c90:	48 c1 f8 3f          	sar    $0x3f,%rax
 1073c94:	4c 21 c0             	and    %r8,%rax
 1073c97:	48 29 c6             	sub    %rax,%rsi
 1073c9a:	48 8d 3d 9f 62 01 00 	lea    0x1629f(%rip),%rdi        # 1089f40 <core_durable_error.verbs+0x9c30>
 1073ca1:	4c 89 c2             	mov    %r8,%rdx
 1073ca4:	e8 17 11 fb ff       	call   1024dc0 <myl_core_trap>
 1073ca9:	48 8d 3d a0 61 01 00 	lea    0x161a0(%rip),%rdi        # 1089e50 <core_durable_error.verbs+0x9b40>
 1073cb0:	e8 8b 64 fb ff       	call   102a140 <myl_core_assert_fail>
 1073cb5:	48 8d 3d c4 61 01 00 	lea    0x161c4(%rip),%rdi        # 1089e80 <core_durable_error.verbs+0x9b70>
 1073cbc:	e8 7f 64 fb ff       	call   102a140 <myl_core_assert_fail>
 1073cc1:	48 8d 3d 18 5c 01 00 	lea    0x15c18(%rip),%rdi        # 10898e0 <core_durable_error.verbs+0x95d0>
 1073cc8:	ba 01 00 00 00       	mov    $0x1,%edx
 1073ccd:	e8 ee 10 fb ff       	call   1024dc0 <myl_core_trap>
 1073cd2:	48 8d 3d d7 61 01 00 	lea    0x161d7(%rip),%rdi        # 1089eb0 <core_durable_error.verbs+0x9ba0>
 1073cd9:	be 10 00 00 00       	mov    $0x10,%esi
 1073cde:	e8 dd 10 fb ff       	call   1024dc0 <myl_core_trap>
 1073ce3:	48 8d 3d f6 61 01 00 	lea    0x161f6(%rip),%rdi        # 1089ee0 <core_durable_error.verbs+0x9bd0>
 1073cea:	be 20 00 00 00       	mov    $0x20,%esi
 1073cef:	e8 cc 10 fb ff       	call   1024dc0 <myl_core_trap>
