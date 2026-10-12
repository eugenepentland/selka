
.tmp/text-gaps/json-serializer/quote-probe:     file format elf64-x86-64


Disassembly of section .text:

0000000001048910 <my.textgap_json_quote_guard_probe::write_quoted>:
 1048910:	55                   	push   %rbp
 1048911:	41 57                	push   %r15
 1048913:	41 56                	push   %r14
 1048915:	41 55                	push   %r13
 1048917:	41 54                	push   %r12
 1048919:	53                   	push   %rbx
 104891a:	50                   	push   %rax
 104891b:	48 b8 01 00 00 00 00 	movabs $0x800000000001,%rax
 1048922:	80 00 00 
 1048925:	48 8b 5e 08          	mov    0x8(%rsi),%rbx
 1048929:	48 ff c8             	dec    %rax
 104892c:	48 39 c3             	cmp    %rax,%rbx
 104892f:	0f 87 54 03 00 00    	ja     1048c89 <my.textgap_json_quote_guard_probe::write_quoted+0x379>
 1048935:	49 89 f6             	mov    %rsi,%r14
 1048938:	49 83 c6 20          	add    $0x20,%r14
 104893c:	be 22 00 00 00       	mov    $0x22,%esi
 1048941:	e8 ba 16 ff ff       	call   103a000 <myl_core_buffer_push_checked>
 1048946:	49 89 c5             	mov    %rax,%r13
 1048949:	45 31 e4             	xor    %r12d,%r12d
 104894c:	45 31 ff             	xor    %r15d,%r15d
 104894f:	4c 89 34 24          	mov    %r14,(%rsp)
 1048953:	eb 65                	jmp    10489ba <my.textgap_json_quote_guard_probe::write_quoted+0xaa>
 1048955:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 104895c:	0f 1f 84 00 00 00 00 
 1048963:	00 
 1048964:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 104896b:	0f 1f 84 00 00 00 00 
 1048972:	00 
 1048973:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 104897a:	84 00 00 00 00 00 
 1048980:	be 5c 00 00 00       	mov    $0x5c,%esi
 1048985:	4c 89 ef             	mov    %r13,%rdi
 1048988:	e8 73 16 ff ff       	call   103a000 <myl_core_buffer_push_checked>
 104898d:	48 89 c7             	mov    %rax,%rdi
 1048990:	48 89 ee             	mov    %rbp,%rsi
 1048993:	e8 68 16 ff ff       	call   103a000 <myl_core_buffer_push_checked>
 1048998:	49 89 c5             	mov    %rax,%r13
 104899b:	4c 8b 34 24          	mov    (%rsp),%r14
 104899f:	4d 8d 7c 24 01       	lea    0x1(%r12),%r15
 10489a4:	49 ff c4             	inc    %r12
 10489a7:	48 b8 01 00 00 00 00 	movabs $0x800000000001,%rax
 10489ae:	80 00 00 
 10489b1:	4c 39 e0             	cmp    %r12,%rax
 10489b4:	0f 84 a5 02 00 00    	je     1048c5f <my.textgap_json_quote_guard_probe::write_quoted+0x34f>
 10489ba:	4c 39 e3             	cmp    %r12,%rbx
 10489bd:	0f 84 31 02 00 00    	je     1048bf4 <my.textgap_json_quote_guard_probe::write_quoted+0x2e4>
 10489c3:	4c 89 f7             	mov    %r14,%rdi
 10489c6:	48 89 de             	mov    %rbx,%rsi
 10489c9:	4c 89 e2             	mov    %r12,%rdx
 10489cc:	e8 2f 18 ff ff       	call   103a200 <myl_core_span_bytes_index_offset>
 10489d1:	48 39 d8             	cmp    %rbx,%rax
 10489d4:	0f 83 9d 02 00 00    	jae    1048c77 <my.textgap_json_quote_guard_probe::write_quoted+0x367>
 10489da:	41 0f b6 2c 06       	movzbl (%r14,%rax,1),%ebp
 10489df:	48 83 fd 22          	cmp    $0x22,%rbp
 10489e3:	74 12                	je     10489f7 <my.textgap_json_quote_guard_probe::write_quoted+0xe7>
 10489e5:	48 83 fd 5c          	cmp    $0x5c,%rbp
 10489e9:	0f 94 c0             	sete   %al
 10489ec:	40 80 fd 20          	cmp    $0x20,%bpl
 10489f0:	0f 92 c1             	setb   %cl
 10489f3:	08 c1                	or     %al,%cl
 10489f5:	74 ad                	je     10489a4 <my.textgap_json_quote_guard_probe::write_quoted+0x94>
 10489f7:	4c 89 e2             	mov    %r12,%rdx
 10489fa:	4c 29 fa             	sub    %r15,%rdx
 10489fd:	48 85 d2             	test   %rdx,%rdx
 1048a00:	0f 8e 47 01 00 00    	jle    1048b4d <my.textgap_json_quote_guard_probe::write_quoted+0x23d>
 1048a06:	4d 8b 75 08          	mov    0x8(%r13),%r14
 1048a0a:	49 8b 45 10          	mov    0x10(%r13),%rax
 1048a0e:	4c 29 f0             	sub    %r14,%rax
 1048a11:	48 39 c2             	cmp    %rax,%rdx
 1048a14:	0f 8f 33 01 00 00    	jg     1048b4d <my.textgap_json_quote_guard_probe::write_quoted+0x23d>
 1048a1a:	4b 8d 3c 2e          	lea    (%r14,%r13,1),%rdi
 1048a1e:	48 83 c7 20          	add    $0x20,%rdi
 1048a22:	48 8b 04 24          	mov    (%rsp),%rax
 1048a26:	4a 8d 34 38          	lea    (%rax,%r15,1),%rsi
 1048a2a:	e8 51 87 00 00       	call   1051180 <memmove@plt>
 1048a2f:	4d 01 e6             	add    %r12,%r14
 1048a32:	4d 29 fe             	sub    %r15,%r14
 1048a35:	4d 89 75 08          	mov    %r14,0x8(%r13)
 1048a39:	40 80 fd 20          	cmp    $0x20,%bpl
 1048a3d:	0f 83 3d ff ff ff    	jae    1048980 <my.textgap_json_quote_guard_probe::write_quoted+0x70>
 1048a43:	49 8b 45 08          	mov    0x8(%r13),%rax
 1048a47:	49 8b 4d 10          	mov    0x10(%r13),%rcx
 1048a4b:	48 29 c1             	sub    %rax,%rcx
 1048a4e:	8d 55 f8             	lea    -0x8(%rbp),%edx
 1048a51:	83 fa 05             	cmp    $0x5,%edx
 1048a54:	4c 8b 34 24          	mov    (%rsp),%r14
 1048a58:	77 27                	ja     1048a81 <my.textgap_json_quote_guard_probe::write_quoted+0x171>
 1048a5a:	48 8d 35 d7 e8 fb ff 	lea    -0x41729(%rip),%rsi        # 1007338 <core_number_pairs+0xf8>
 1048a61:	48 63 14 96          	movslq (%rsi,%rdx,4),%rdx
 1048a65:	48 01 f2             	add    %rsi,%rdx
 1048a68:	ff e2                	jmp    *%rdx
 1048a6a:	48 83 f9 02          	cmp    $0x2,%rcx
 1048a6e:	0f 8c 2f 01 00 00    	jl     1048ba3 <my.textgap_json_quote_guard_probe::write_quoted+0x293>
 1048a74:	66 41 c7 44 05 20 5c 	movw   $0x625c,0x20(%r13,%rax,1)
 1048a7b:	62 
 1048a7c:	e9 bf 00 00 00       	jmp    1048b40 <my.textgap_json_quote_guard_probe::write_quoted+0x230>
 1048a81:	48 83 f9 04          	cmp    $0x4,%rcx
 1048a85:	0f 8c e9 00 00 00    	jl     1048b74 <my.textgap_json_quote_guard_probe::write_quoted+0x264>
 1048a8b:	41 c7 44 05 20 5c 75 	movl   $0x3030755c,0x20(%r13,%rax,1)
 1048a92:	30 30 
 1048a94:	48 83 c0 04          	add    $0x4,%rax
 1048a98:	49 89 45 08          	mov    %rax,0x8(%r13)
 1048a9c:	89 e8                	mov    %ebp,%eax
 1048a9e:	c1 e8 04             	shr    $0x4,%eax
 1048aa1:	4c 8d 3d 98 f4 fb ff 	lea    -0x40b68(%rip),%r15        # 1007f40 <core_number_pairs+0xd00>
 1048aa8:	42 0f b6 74 38 20    	movzbl 0x20(%rax,%r15,1),%esi
 1048aae:	4c 89 ef             	mov    %r13,%rdi
 1048ab1:	e8 4a 15 ff ff       	call   103a000 <myl_core_buffer_push_checked>
 1048ab6:	83 e5 0f             	and    $0xf,%ebp
 1048ab9:	42 0f b6 74 3d 20    	movzbl 0x20(%rbp,%r15,1),%esi
 1048abf:	48 89 c7             	mov    %rax,%rdi
 1048ac2:	e8 39 15 ff ff       	call   103a000 <myl_core_buffer_push_checked>
 1048ac7:	49 89 c5             	mov    %rax,%r13
 1048aca:	e9 d0 fe ff ff       	jmp    104899f <my.textgap_json_quote_guard_probe::write_quoted+0x8f>
 1048acf:	48 83 f9 02          	cmp    $0x2,%rcx
 1048ad3:	0f 8c b9 00 00 00    	jl     1048b92 <my.textgap_json_quote_guard_probe::write_quoted+0x282>
 1048ad9:	66 41 c7 44 05 20 5c 	movw   $0x6e5c,0x20(%r13,%rax,1)
 1048ae0:	6e 
 1048ae1:	eb 5d                	jmp    1048b40 <my.textgap_json_quote_guard_probe::write_quoted+0x230>
 1048ae3:	48 83 f9 02          	cmp    $0x2,%rcx
 1048ae7:	0f 8c c7 00 00 00    	jl     1048bb4 <my.textgap_json_quote_guard_probe::write_quoted+0x2a4>
 1048aed:	66 41 c7 44 05 20 5c 	movw   $0x745c,0x20(%r13,%rax,1)
 1048af4:	74 
 1048af5:	eb 49                	jmp    1048b40 <my.textgap_json_quote_guard_probe::write_quoted+0x230>
 1048af7:	48 83 f9 02          	cmp    $0x2,%rcx
 1048afb:	0f 8c c4 00 00 00    	jl     1048bc5 <my.textgap_json_quote_guard_probe::write_quoted+0x2b5>
 1048b01:	66 41 c7 44 05 20 5c 	movw   $0x665c,0x20(%r13,%rax,1)
 1048b08:	66 
 1048b09:	eb 35                	jmp    1048b40 <my.textgap_json_quote_guard_probe::write_quoted+0x230>
 1048b0b:	48 83 f9 02          	cmp    $0x2,%rcx
 1048b0f:	0f 8c c1 00 00 00    	jl     1048bd6 <my.textgap_json_quote_guard_probe::write_quoted+0x2c6>
 1048b15:	66 41 c7 44 05 20 5c 	movw   $0x725c,0x20(%r13,%rax,1)
 1048b1c:	72 
 1048b1d:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1048b24:	0f 1f 84 00 00 00 00 
 1048b2b:	00 
 1048b2c:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1048b33:	0f 1f 84 00 00 00 00 
 1048b3a:	00 
 1048b3b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 1048b40:	48 83 c0 02          	add    $0x2,%rax
 1048b44:	49 89 45 08          	mov    %rax,0x8(%r13)
 1048b48:	e9 52 fe ff ff       	jmp    104899f <my.textgap_json_quote_guard_probe::write_quoted+0x8f>
 1048b4d:	4c 89 ef             	mov    %r13,%rdi
 1048b50:	48 8b 34 24          	mov    (%rsp),%rsi
 1048b54:	48 89 da             	mov    %rbx,%rdx
 1048b57:	4c 89 f9             	mov    %r15,%rcx
 1048b5a:	4d 89 e0             	mov    %r12,%r8
 1048b5d:	e8 1e 14 ff ff       	call   1039f80 <myl_core_buffer_append_span_checked>
 1048b62:	49 89 c5             	mov    %rax,%r13
 1048b65:	40 80 fd 20          	cmp    $0x20,%bpl
 1048b69:	0f 83 11 fe ff ff    	jae    1048980 <my.textgap_json_quote_guard_probe::write_quoted+0x70>
 1048b6f:	e9 cf fe ff ff       	jmp    1048a43 <my.textgap_json_quote_guard_probe::write_quoted+0x133>
 1048b74:	b9 04 00 00 00       	mov    $0x4,%ecx
 1048b79:	4c 89 ef             	mov    %r13,%rdi
 1048b7c:	48 8d 35 7d f3 fb ff 	lea    -0x40c83(%rip),%rsi        # 1007f00 <core_number_pairs+0xcc0>
 1048b83:	31 d2                	xor    %edx,%edx
 1048b85:	e8 f6 12 ff ff       	call   1039e80 <myl_core_buffer_append_checked>
 1048b8a:	49 89 c5             	mov    %rax,%r13
 1048b8d:	e9 0a ff ff ff       	jmp    1048a9c <my.textgap_json_quote_guard_probe::write_quoted+0x18c>
 1048b92:	b9 02 00 00 00       	mov    $0x2,%ecx
 1048b97:	4c 89 ef             	mov    %r13,%rdi
 1048b9a:	48 8d 35 9f f2 fb ff 	lea    -0x40d61(%rip),%rsi        # 1007e40 <core_number_pairs+0xc00>
 1048ba1:	eb 42                	jmp    1048be5 <my.textgap_json_quote_guard_probe::write_quoted+0x2d5>
 1048ba3:	b9 02 00 00 00       	mov    $0x2,%ecx
 1048ba8:	4c 89 ef             	mov    %r13,%rdi
 1048bab:	48 8d 35 0e f2 fb ff 	lea    -0x40df2(%rip),%rsi        # 1007dc0 <core_number_pairs+0xb80>
 1048bb2:	eb 31                	jmp    1048be5 <my.textgap_json_quote_guard_probe::write_quoted+0x2d5>
 1048bb4:	b9 02 00 00 00       	mov    $0x2,%ecx
 1048bb9:	4c 89 ef             	mov    %r13,%rdi
 1048bbc:	48 8d 35 3d f2 fb ff 	lea    -0x40dc3(%rip),%rsi        # 1007e00 <core_number_pairs+0xbc0>
 1048bc3:	eb 20                	jmp    1048be5 <my.textgap_json_quote_guard_probe::write_quoted+0x2d5>
 1048bc5:	b9 02 00 00 00       	mov    $0x2,%ecx
 1048bca:	4c 89 ef             	mov    %r13,%rdi
 1048bcd:	48 8d 35 ac f2 fb ff 	lea    -0x40d54(%rip),%rsi        # 1007e80 <core_number_pairs+0xc40>
 1048bd4:	eb 0f                	jmp    1048be5 <my.textgap_json_quote_guard_probe::write_quoted+0x2d5>
 1048bd6:	b9 02 00 00 00       	mov    $0x2,%ecx
 1048bdb:	4c 89 ef             	mov    %r13,%rdi
 1048bde:	48 8d 35 db f2 fb ff 	lea    -0x40d25(%rip),%rsi        # 1007ec0 <core_number_pairs+0xc80>
 1048be5:	31 d2                	xor    %edx,%edx
 1048be7:	e8 94 12 ff ff       	call   1039e80 <myl_core_buffer_append_checked>
 1048bec:	49 89 c5             	mov    %rax,%r13
 1048bef:	e9 ab fd ff ff       	jmp    104899f <my.textgap_json_quote_guard_probe::write_quoted+0x8f>
 1048bf4:	49 89 dc             	mov    %rbx,%r12
 1048bf7:	4d 29 fc             	sub    %r15,%r12
 1048bfa:	7e 49                	jle    1048c45 <my.textgap_json_quote_guard_probe::write_quoted+0x335>
 1048bfc:	4d 8b 75 08          	mov    0x8(%r13),%r14
 1048c00:	49 8b 45 10          	mov    0x10(%r13),%rax
 1048c04:	4c 29 f0             	sub    %r14,%rax
 1048c07:	49 39 c4             	cmp    %rax,%r12
 1048c0a:	7f 39                	jg     1048c45 <my.textgap_json_quote_guard_probe::write_quoted+0x335>
 1048c0c:	4b 8d 3c 2e          	lea    (%r14,%r13,1),%rdi
 1048c10:	48 83 c7 20          	add    $0x20,%rdi
 1048c14:	48 8b 34 24          	mov    (%rsp),%rsi
 1048c18:	4c 01 fe             	add    %r15,%rsi
 1048c1b:	4c 89 e2             	mov    %r12,%rdx
 1048c1e:	e8 5d 85 00 00       	call   1051180 <memmove@plt>
 1048c23:	4d 01 e6             	add    %r12,%r14
 1048c26:	4d 89 75 08          	mov    %r14,0x8(%r13)
 1048c2a:	be 22 00 00 00       	mov    $0x22,%esi
 1048c2f:	4c 89 ef             	mov    %r13,%rdi
 1048c32:	48 83 c4 08          	add    $0x8,%rsp
 1048c36:	5b                   	pop    %rbx
 1048c37:	41 5c                	pop    %r12
 1048c39:	41 5d                	pop    %r13
 1048c3b:	41 5e                	pop    %r14
 1048c3d:	41 5f                	pop    %r15
 1048c3f:	5d                   	pop    %rbp
 1048c40:	e9 bb 13 ff ff       	jmp    103a000 <myl_core_buffer_push_checked>
 1048c45:	4c 89 ef             	mov    %r13,%rdi
 1048c48:	48 8b 34 24          	mov    (%rsp),%rsi
 1048c4c:	48 89 da             	mov    %rbx,%rdx
 1048c4f:	4c 89 f9             	mov    %r15,%rcx
 1048c52:	49 89 d8             	mov    %rbx,%r8
 1048c55:	e8 26 13 ff ff       	call   1039f80 <myl_core_buffer_append_span_checked>
 1048c5a:	49 89 c5             	mov    %rax,%r13
 1048c5d:	eb cb                	jmp    1048c2a <my.textgap_json_quote_guard_probe::write_quoted+0x31a>
 1048c5f:	48 8d 3d 7a 9c 00 00 	lea    0x9c7a(%rip),%rdi        # 10528e0 <core_durable_error.verbs+0x1b0>
 1048c66:	48 be 01 00 00 00 00 	movabs $0x800000000001,%rsi
 1048c6d:	80 00 00 
 1048c70:	31 d2                	xor    %edx,%edx
 1048c72:	e8 49 cf fc ff       	call   1015bc0 <myl_core_trap>
 1048c77:	48 8d 3d 92 9c 00 00 	lea    0x9c92(%rip),%rdi        # 1052910 <core_durable_error.verbs+0x1e0>
 1048c7e:	4c 89 e6             	mov    %r12,%rsi
 1048c81:	48 89 da             	mov    %rbx,%rdx
 1048c84:	e8 37 cf fc ff       	call   1015bc0 <myl_core_trap>
 1048c89:	48 8d 3d 20 9c 00 00 	lea    0x9c20(%rip),%rdi        # 10528b0 <core_durable_error.verbs+0x180>
 1048c90:	48 89 de             	mov    %rbx,%rsi
 1048c93:	31 d2                	xor    %edx,%edx
 1048c95:	e8 26 cf fc ff       	call   1015bc0 <myl_core_trap>

Disassembly of section .plt:
