
.mylang-cache/goal110-equality-bounded/helper-after-llvm:     file format elf64-x86-64


Disassembly of section .text:

00000000010017e0 <main>:
 10017e0:	55                   	push   %rbp
 10017e1:	48 89 e5             	mov    %rsp,%rbp
 10017e4:	41 57                	push   %r15
 10017e6:	41 56                	push   %r14
 10017e8:	41 55                	push   %r13
 10017ea:	41 54                	push   %r12
 10017ec:	53                   	push   %rbx
 10017ed:	48 81 ec 78 50 00 00 	sub    $0x5078,%rsp
 10017f4:	bb 02 00 00 00       	mov    $0x2,%ebx
 10017f9:	83 ff 06             	cmp    $0x6,%edi
 10017fc:	0f 85 f6 05 00 00    	jne    1001df8 <main+0x618>
 1001802:	48 8b 7e 08          	mov    0x8(%rsi),%rdi
 1001806:	49 89 f6             	mov    %rsi,%r14
 1001809:	31 f6                	xor    %esi,%esi
 100180b:	ba 0a 00 00 00       	mov    $0xa,%edx
 1001810:	e8 6b 06 00 00       	call   1001e80 <strtoull@plt>
 1001815:	49 89 c7             	mov    %rax,%r15
 1001818:	49 8b 7e 10          	mov    0x10(%r14),%rdi
 100181c:	31 f6                	xor    %esi,%esi
 100181e:	ba 0a 00 00 00       	mov    $0xa,%edx
 1001823:	e8 68 06 00 00       	call   1001e90 <strtoul@plt>
 1001828:	49 89 c4             	mov    %rax,%r12
 100182b:	49 8b 7e 18          	mov    0x18(%r14),%rdi
 100182f:	31 f6                	xor    %esi,%esi
 1001831:	ba 0a 00 00 00       	mov    $0xa,%edx
 1001836:	e8 85 06 00 00       	call   1001ec0 <strtol@plt>
 100183b:	48 89 45 c8          	mov    %rax,-0x38(%rbp)
 100183f:	49 8b 7e 20          	mov    0x20(%r14),%rdi
 1001843:	31 f6                	xor    %esi,%esi
 1001845:	ba 0a 00 00 00       	mov    $0xa,%edx
 100184a:	e8 71 06 00 00       	call   1001ec0 <strtol@plt>
 100184f:	49 89 c5             	mov    %rax,%r13
 1001852:	49 8b 7e 28          	mov    0x28(%r14),%rdi
 1001856:	31 f6                	xor    %esi,%esi
 1001858:	ba 0a 00 00 00       	mov    $0xa,%edx
 100185d:	e8 1e 06 00 00       	call   1001e80 <strtoull@plt>
 1001862:	49 81 ff 01 00 01 00 	cmp    $0x10001,%r15
 1001869:	0f 92 c2             	setb   %dl
 100186c:	41 83 fc 05          	cmp    $0x5,%r12d
 1001870:	0f 92 c1             	setb   %cl
 1001873:	20 d1                	and    %dl,%cl
 1001875:	48 89 45 88          	mov    %rax,-0x78(%rbp)
 1001879:	48 85 c0             	test   %rax,%rax
 100187c:	0f 95 c0             	setne  %al
 100187f:	20 c8                	and    %cl,%al
 1001881:	3c 01                	cmp    $0x1,%al
 1001883:	0f 85 6f 05 00 00    	jne    1001df8 <main+0x618>
 1001889:	49 8d 47 01          	lea    0x1(%r15),%rax
 100188d:	48 d1 e8             	shr    $1,%rax
 1001890:	31 d2                	xor    %edx,%edx
 1001892:	45 85 ed             	test   %r13d,%r13d
 1001895:	0f 94 c2             	sete   %dl
 1001898:	49 0f 44 c7          	cmove  %r15,%rax
 100189c:	48 89 45 b8          	mov    %rax,-0x48(%rbp)
 10018a0:	4c 89 a5 70 ff ff ff 	mov    %r12,-0x90(%rbp)
 10018a7:	45 85 e4             	test   %r12d,%r12d
 10018aa:	0f 95 c0             	setne  %al
 10018ad:	4c 89 f9             	mov    %r15,%rcx
 10018b0:	48 83 c1 ff          	add    $0xffffffffffffffff,%rcx
 10018b4:	48 89 8d 78 ff ff ff 	mov    %rcx,-0x88(%rbp)
 10018bb:	0f 92 c1             	setb   %cl
 10018be:	20 c1                	and    %al,%cl
 10018c0:	88 4d d7             	mov    %cl,-0x29(%rbp)
 10018c3:	4c 89 f8             	mov    %r15,%rax
 10018c6:	48 d1 e8             	shr    $1,%rax
 10018c9:	48 89 45 80          	mov    %rax,-0x80(%rbp)
 10018cd:	48 89 95 60 ff ff ff 	mov    %rdx,-0xa0(%rbp)
 10018d4:	8d 42 04             	lea    0x4(%rdx),%eax
 10018d7:	89 45 c4             	mov    %eax,-0x3c(%rbp)
 10018da:	31 c9                	xor    %ecx,%ecx
 10018dc:	31 db                	xor    %ebx,%ebx
 10018de:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 10018e2:	4c 89 ad 68 ff ff ff 	mov    %r13,-0x98(%rbp)
 10018e9:	eb 27                	jmp    1001912 <main+0x132>
 10018eb:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 10018f0:	48 89 f8             	mov    %rdi,%rax
 10018f3:	48 ff c0             	inc    %rax
 10018f6:	4c 39 f8             	cmp    %r15,%rax
 10018f9:	b9 00 00 00 00       	mov    $0x0,%ecx
 10018fe:	48 0f 45 c8          	cmovne %rax,%rcx
 1001902:	48 ff c3             	inc    %rbx
 1001905:	48 81 fb 00 01 00 00 	cmp    $0x100,%rbx
 100190c:	0f 84 54 02 00 00    	je     1001b66 <main+0x386>
 1001912:	85 f6                	test   %esi,%esi
 1001914:	48 89 4d a0          	mov    %rcx,-0x60(%rbp)
 1001918:	74 36                	je     1001950 <main+0x170>
 100191a:	8d 04 db             	lea    (%rbx,%rbx,8),%eax
 100191d:	8d 04 83             	lea    (%rbx,%rax,4),%eax
 1001920:	c1 e8 08             	shr    $0x8,%eax
 1001923:	89 d9                	mov    %ebx,%ecx
 1001925:	28 c1                	sub    %al,%cl
 1001927:	d0 e9                	shr    $1,%cl
 1001929:	00 c1                	add    %al,%cl
 100192b:	c0 e9 02             	shr    $0x2,%cl
 100192e:	0f b6 c1             	movzbl %cl,%eax
 1001931:	8d 0c c5 00 00 00 00 	lea    0x0(,%rax,8),%ecx
 1001938:	29 c1                	sub    %eax,%ecx
 100193a:	89 d8                	mov    %ebx,%eax
 100193c:	28 c8                	sub    %cl,%al
 100193e:	fe c0                	inc    %al
 1001940:	0f b6 c8             	movzbl %al,%ecx
 1001943:	eb 0d                	jmp    1001952 <main+0x172>
 1001945:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 100194c:	00 00 00 00 
 1001950:	31 c9                	xor    %ecx,%ecx
 1001952:	49 8d 47 18          	lea    0x18(%r15),%rax
 1001956:	49 89 cc             	mov    %rcx,%r12
 1001959:	4c 8d 2c 08          	lea    (%rax,%rcx,1),%r13
 100195d:	4c 89 ef             	mov    %r13,%rdi
 1001960:	c5 f8 77             	vzeroupper
 1001963:	e8 e8 04 00 00       	call   1001e50 <malloc@plt>
 1001968:	49 89 c6             	mov    %rax,%r14
 100196b:	48 89 84 dd 60 ef ff 	mov    %rax,-0x10a0(%rbp,%rbx,8)
 1001972:	ff 
 1001973:	4c 89 ef             	mov    %r13,%rdi
 1001976:	e8 d5 04 00 00       	call   1001e50 <malloc@plt>
 100197b:	48 89 84 dd 60 f7 ff 	mov    %rax,-0x8a0(%rbp,%rbx,8)
 1001982:	ff 
 1001983:	4d 85 f6             	test   %r14,%r14
 1001986:	0f 84 80 04 00 00    	je     1001e0c <main+0x62c>
 100198c:	49 89 c5             	mov    %rax,%r13
 100198f:	48 85 c0             	test   %rax,%rax
 1001992:	0f 84 74 04 00 00    	je     1001e0c <main+0x62c>
 1001998:	48 8b 45 b8          	mov    -0x48(%rbp),%rax
 100199c:	4c 01 e0             	add    %r12,%rax
 100199f:	4b 8d 0c 3c          	lea    (%r12,%r15,1),%rcx
 10019a3:	49 89 06             	mov    %rax,(%r14)
 10019a6:	49 89 4e 08          	mov    %rcx,0x8(%r14)
 10019aa:	48 8b 85 60 ff ff ff 	mov    -0xa0(%rbp),%rax
 10019b1:	41 89 46 10          	mov    %eax,0x10(%r14)
 10019b5:	41 c7 46 14 00 00 00 	movl   $0x0,0x14(%r14)
 10019bc:	00 
 10019bd:	49 8b 46 10          	mov    0x10(%r14),%rax
 10019c1:	49 89 45 10          	mov    %rax,0x10(%r13)
 10019c5:	49 8b 06             	mov    (%r14),%rax
 10019c8:	49 89 45 00          	mov    %rax,0x0(%r13)
 10019cc:	49 8b 46 08          	mov    0x8(%r14),%rax
 10019d0:	49 89 45 08          	mov    %rax,0x8(%r13)
 10019d4:	49 8d 7e 18          	lea    0x18(%r14),%rdi
 10019d8:	be 7a 00 00 00       	mov    $0x7a,%esi
 10019dd:	4c 89 e2             	mov    %r12,%rdx
 10019e0:	e8 fb 04 00 00       	call   1001ee0 <memset@plt>
 10019e5:	49 8d 7d 18          	lea    0x18(%r13),%rdi
 10019e9:	be 7a 00 00 00       	mov    $0x7a,%esi
 10019ee:	4c 89 e2             	mov    %r12,%rdx
 10019f1:	e8 ea 04 00 00       	call   1001ee0 <memset@plt>
 10019f6:	4d 89 eb             	mov    %r13,%r11
 10019f9:	4b 8d 0c 2c          	lea    (%r12,%r13,1),%rcx
 10019fd:	48 83 c1 18          	add    $0x18,%rcx
 1001a01:	4d 85 ff             	test   %r15,%r15
 1001a04:	49 ba c9 42 16 b2 90 	movabs $0x642c8590b21642c9,%r10
 1001a0b:	85 2c 64 
 1001a0e:	4c 8b ad 68 ff ff ff 	mov    -0x98(%rbp),%r13
 1001a15:	0f 84 85 00 00 00    	je     1001aa0 <main+0x2c0>
 1001a1b:	4b 8d 04 26          	lea    (%r14,%r12,1),%rax
 1001a1f:	48 83 c0 18          	add    $0x18,%rax
 1001a23:	89 de                	mov    %ebx,%esi
 1001a25:	40 80 e6 0f          	and    $0xf,%sil
 1001a29:	40 80 ce a0          	or     $0xa0,%sil
 1001a2d:	31 ff                	xor    %edi,%edi
 1001a2f:	eb 4a                	jmp    1001a7b <main+0x29b>
 1001a31:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1001a38:	0f 1f 84 00 00 00 00 
 1001a3f:	00 
 1001a40:	48 8d 14 1f          	lea    (%rdi,%rbx,1),%rdx
 1001a44:	c4 42 b3 f6 ca       	mulx   %r10,%r9,%r9
 1001a49:	41 89 d0             	mov    %edx,%r8d
 1001a4c:	45 29 c8             	sub    %r9d,%r8d
 1001a4f:	41 d1 e8             	shr    $1,%r8d
 1001a52:	45 01 c8             	add    %r9d,%r8d
 1001a55:	41 c1 e8 04          	shr    $0x4,%r8d
 1001a59:	47 8d 0c 40          	lea    (%r8,%r8,2),%r9d
 1001a5d:	41 c1 e1 03          	shl    $0x3,%r9d
 1001a61:	45 29 c8             	sub    %r9d,%r8d
 1001a64:	41 01 d0             	add    %edx,%r8d
 1001a67:	41 80 c0 61          	add    $0x61,%r8b
 1001a6b:	44 88 04 39          	mov    %r8b,(%rcx,%rdi,1)
 1001a6f:	44 88 04 38          	mov    %r8b,(%rax,%rdi,1)
 1001a73:	48 ff c7             	inc    %rdi
 1001a76:	4c 39 ff             	cmp    %r15,%rdi
 1001a79:	73 25                	jae    1001aa0 <main+0x2c0>
 1001a7b:	45 85 ed             	test   %r13d,%r13d
 1001a7e:	74 c0                	je     1001a40 <main+0x260>
 1001a80:	48 8d 57 01          	lea    0x1(%rdi),%rdx
 1001a84:	4c 39 fa             	cmp    %r15,%rdx
 1001a87:	73 b7                	jae    1001a40 <main+0x260>
 1001a89:	c6 04 39 c3          	movb   $0xc3,(%rcx,%rdi,1)
 1001a8d:	c6 04 38 c3          	movb   $0xc3,(%rax,%rdi,1)
 1001a91:	48 89 d7             	mov    %rdx,%rdi
 1001a94:	41 89 f0             	mov    %esi,%r8d
 1001a97:	eb d2                	jmp    1001a6b <main+0x28b>
 1001a99:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 1001aa0:	80 7d d7 00          	cmpb   $0x0,-0x29(%rbp)
 1001aa4:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 1001aa8:	48 8b 7d a0          	mov    -0x60(%rbp),%rdi
 1001aac:	74 4e                	je     1001afc <main+0x31c>
 1001aae:	48 8b 85 70 ff ff ff 	mov    -0x90(%rbp),%rax
 1001ab5:	83 f8 01             	cmp    $0x1,%eax
 1001ab8:	74 2b                	je     1001ae5 <main+0x305>
 1001aba:	48 8b 95 78 ff ff ff 	mov    -0x88(%rbp),%rdx
 1001ac1:	83 f8 03             	cmp    $0x3,%eax
 1001ac4:	74 21                	je     1001ae7 <main+0x307>
 1001ac6:	48 8b 55 80          	mov    -0x80(%rbp),%rdx
 1001aca:	83 f8 02             	cmp    $0x2,%eax
 1001acd:	74 18                	je     1001ae7 <main+0x307>
 1001acf:	48 89 d8             	mov    %rbx,%rax
 1001ad2:	4c 09 f8             	or     %r15,%rax
 1001ad5:	48 c1 e8 20          	shr    $0x20,%rax
 1001ad9:	74 7d                	je     1001b58 <main+0x378>
 1001adb:	48 89 fa             	mov    %rdi,%rdx
 1001ade:	45 85 ed             	test   %r13d,%r13d
 1001ae1:	75 09                	jne    1001aec <main+0x30c>
 1001ae3:	eb 13                	jmp    1001af8 <main+0x318>
 1001ae5:	31 d2                	xor    %edx,%edx
 1001ae7:	45 85 ed             	test   %r13d,%r13d
 1001aea:	74 0c                	je     1001af8 <main+0x318>
 1001aec:	31 c0                	xor    %eax,%eax
 1001aee:	80 3c 11 c3          	cmpb   $0xc3,(%rcx,%rdx,1)
 1001af2:	0f 94 c0             	sete   %al
 1001af5:	48 01 c2             	add    %rax,%rdx
 1001af8:	80 34 11 01          	xorb   $0x1,(%rcx,%rdx,1)
 1001afc:	85 f6                	test   %esi,%esi
 1001afe:	0f 84 ec fd ff ff    	je     10018f0 <main+0x110>
 1001b04:	48 89 d8             	mov    %rbx,%rax
 1001b07:	48 c1 e0 05          	shl    $0x5,%rax
 1001b0b:	48 8b 4d b8          	mov    -0x48(%rbp),%rcx
 1001b0f:	48 89 8c 05 60 cf ff 	mov    %rcx,-0x30a0(%rbp,%rax,1)
 1001b16:	ff 
 1001b17:	4c 89 bc 05 68 cf ff 	mov    %r15,-0x3098(%rbp,%rax,1)
 1001b1e:	ff 
 1001b1f:	8b 4d c4             	mov    -0x3c(%rbp),%ecx
 1001b22:	89 8c 05 70 cf ff ff 	mov    %ecx,-0x3090(%rbp,%rax,1)
 1001b29:	44 89 a4 05 74 cf ff 	mov    %r12d,-0x308c(%rbp,%rax,1)
 1001b30:	ff 
 1001b31:	4c 89 b4 05 78 cf ff 	mov    %r14,-0x3088(%rbp,%rax,1)
 1001b38:	ff 
 1001b39:	c5 fe 6f 84 05 60 cf 	vmovdqu -0x30a0(%rbp,%rax,1),%ymm0
 1001b40:	ff ff 
 1001b42:	c5 fe 7f 84 05 60 af 	vmovdqu %ymm0,-0x50a0(%rbp,%rax,1)
 1001b49:	ff ff 
 1001b4b:	4c 89 9c 05 78 af ff 	mov    %r11,-0x5088(%rbp,%rax,1)
 1001b52:	ff 
 1001b53:	e9 98 fd ff ff       	jmp    10018f0 <main+0x110>
 1001b58:	89 d8                	mov    %ebx,%eax
 1001b5a:	31 d2                	xor    %edx,%edx
 1001b5c:	41 f7 f7             	div    %r15d
 1001b5f:	45 85 ed             	test   %r13d,%r13d
 1001b62:	75 88                	jne    1001aec <main+0x30c>
 1001b64:	eb 92                	jmp    1001af8 <main+0x318>
 1001b66:	48 8d 75 90          	lea    -0x70(%rbp),%rsi
 1001b6a:	bf 01 00 00 00       	mov    $0x1,%edi
 1001b6f:	c5 f8 77             	vzeroupper
 1001b72:	e8 59 03 00 00       	call   1001ed0 <clock_gettime@plt>
 1001b77:	85 c0                	test   %eax,%eax
 1001b79:	0f 85 8d 02 00 00    	jne    1001e0c <main+0x62c>
 1001b7f:	c5 f9 6f 45 90       	vmovdqa -0x70(%rbp),%xmm0
 1001b84:	c5 f9 7f 45 a0       	vmovdqa %xmm0,-0x60(%rbp)
 1001b89:	45 31 ff             	xor    %r15d,%r15d
 1001b8c:	31 db                	xor    %ebx,%ebx
 1001b8e:	4c 8b 65 88          	mov    -0x78(%rbp),%r12
 1001b92:	4d 89 e6             	mov    %r12,%r14
 1001b95:	4c 8b 45 c8          	mov    -0x38(%rbp),%r8
 1001b99:	eb 3a                	jmp    1001bd5 <main+0x3f5>
 1001b9b:	48 8b 0f             	mov    (%rdi),%rcx
 1001b9e:	48 8b 7c 17 f8       	mov    -0x8(%rdi,%rdx,1),%rdi
 1001ba3:	48 33 0e             	xor    (%rsi),%rcx
 1001ba6:	48 33 7c 16 f8       	xor    -0x8(%rsi,%rdx,1),%rdi
 1001bab:	31 c0                	xor    %eax,%eax
 1001bad:	48 09 cf             	or     %rcx,%rdi
 1001bb0:	0f 94 c0             	sete   %al
 1001bb3:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1001bba:	84 00 00 00 00 00 
 1001bc0:	89 c0                	mov    %eax,%eax
 1001bc2:	49 01 c7             	add    %rax,%r15
 1001bc5:	48 81 c3 89 00 00 00 	add    $0x89,%rbx
 1001bcc:	49 ff ce             	dec    %r14
 1001bcf:	0f 84 99 01 00 00    	je     1001d6e <main+0x58e>
 1001bd5:	0f b6 c3             	movzbl %bl,%eax
 1001bd8:	45 85 c0             	test   %r8d,%r8d
 1001bdb:	74 33                	je     1001c10 <main+0x430>
 1001bdd:	c1 e0 05             	shl    $0x5,%eax
 1001be0:	48 8d 3c 28          	lea    (%rax,%rbp,1),%rdi
 1001be4:	48 81 c7 60 cf ff ff 	add    $0xffffffffffffcf60,%rdi
 1001beb:	48 8d 34 28          	lea    (%rax,%rbp,1),%rsi
 1001bef:	48 81 c6 60 af ff ff 	add    $0xffffffffffffaf60,%rsi
 1001bf6:	b8 01 00 00 00       	mov    $0x1,%eax
 1001bfb:	48 39 f7             	cmp    %rsi,%rdi
 1001bfe:	75 2d                	jne    1001c2d <main+0x44d>
 1001c00:	eb be                	jmp    1001bc0 <main+0x3e0>
 1001c02:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1001c09:	1f 84 00 00 00 00 00 
 1001c10:	c1 e0 03             	shl    $0x3,%eax
 1001c13:	48 8b bc 05 60 ef ff 	mov    -0x10a0(%rbp,%rax,1),%rdi
 1001c1a:	ff 
 1001c1b:	48 8b b4 05 60 f7 ff 	mov    -0x8a0(%rbp,%rax,1),%rsi
 1001c22:	ff 
 1001c23:	b8 01 00 00 00       	mov    $0x1,%eax
 1001c28:	48 39 f7             	cmp    %rsi,%rdi
 1001c2b:	74 93                	je     1001bc0 <main+0x3e0>
 1001c2d:	48 85 ff             	test   %rdi,%rdi
 1001c30:	0f 94 c1             	sete   %cl
 1001c33:	48 85 f6             	test   %rsi,%rsi
 1001c36:	0f 94 c2             	sete   %dl
 1001c39:	31 c0                	xor    %eax,%eax
 1001c3b:	08 ca                	or     %cl,%dl
 1001c3d:	75 81                	jne    1001bc0 <main+0x3e0>
 1001c3f:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 1001c43:	48 3b 56 08          	cmp    0x8(%rsi),%rdx
 1001c47:	0f 85 73 ff ff ff    	jne    1001bc0 <main+0x3e0>
 1001c4d:	b8 01 00 00 00       	mov    $0x1,%eax
 1001c52:	48 85 d2             	test   %rdx,%rdx
 1001c55:	0f 84 65 ff ff ff    	je     1001bc0 <main+0x3e0>
 1001c5b:	f6 47 10 04          	testb  $0x4,0x10(%rdi)
 1001c5f:	75 49                	jne    1001caa <main+0x4ca>
 1001c61:	48 83 c7 18          	add    $0x18,%rdi
 1001c65:	f6 46 10 04          	testb  $0x4,0x10(%rsi)
 1001c69:	74 54                	je     1001cbf <main+0x4df>
 1001c6b:	48 8b 46 18          	mov    0x18(%rsi),%rax
 1001c6f:	8b 4e 14             	mov    0x14(%rsi),%ecx
 1001c72:	48 8d 34 08          	lea    (%rax,%rcx,1),%rsi
 1001c76:	48 83 c6 18          	add    $0x18,%rsi
 1001c7a:	48 83 fa 10          	cmp    $0x10,%rdx
 1001c7e:	76 49                	jbe    1001cc9 <main+0x4e9>
 1001c80:	48 83 fa 40          	cmp    $0x40,%rdx
 1001c84:	77 68                	ja     1001cee <main+0x50e>
 1001c86:	c5 fa 6f 07          	vmovdqu (%rdi),%xmm0
 1001c8a:	48 83 fa 20          	cmp    $0x20,%rdx
 1001c8e:	77 7a                	ja     1001d0a <main+0x52a>
 1001c90:	c4 e3 7d 38 44 17 f0 	vinserti128 $0x1,-0x10(%rdi,%rdx,1),%ymm0,%ymm0
 1001c97:	01 
 1001c98:	c5 fa 6f 0e          	vmovdqu (%rsi),%xmm1
 1001c9c:	c4 e3 75 38 4c 16 f0 	vinserti128 $0x1,-0x10(%rsi,%rdx,1),%ymm1,%ymm1
 1001ca3:	01 
 1001ca4:	c5 fd ef c1          	vpxor  %ymm1,%ymm0,%ymm0
 1001ca8:	eb 7b                	jmp    1001d25 <main+0x545>
 1001caa:	48 8b 47 18          	mov    0x18(%rdi),%rax
 1001cae:	8b 4f 14             	mov    0x14(%rdi),%ecx
 1001cb1:	48 8d 3c 08          	lea    (%rax,%rcx,1),%rdi
 1001cb5:	48 83 c7 18          	add    $0x18,%rdi
 1001cb9:	f6 46 10 04          	testb  $0x4,0x10(%rsi)
 1001cbd:	75 ac                	jne    1001c6b <main+0x48b>
 1001cbf:	48 83 c6 18          	add    $0x18,%rsi
 1001cc3:	48 83 fa 10          	cmp    $0x10,%rdx
 1001cc7:	77 b7                	ja     1001c80 <main+0x4a0>
 1001cc9:	48 83 fa 08          	cmp    $0x8,%rdx
 1001ccd:	0f 83 c8 fe ff ff    	jae    1001b9b <main+0x3bb>
 1001cd3:	48 83 fa 04          	cmp    $0x4,%rdx
 1001cd7:	72 58                	jb     1001d31 <main+0x551>
 1001cd9:	8b 0f                	mov    (%rdi),%ecx
 1001cdb:	8b 7c 17 fc          	mov    -0x4(%rdi,%rdx,1),%edi
 1001cdf:	33 0e                	xor    (%rsi),%ecx
 1001ce1:	33 7c 16 fc          	xor    -0x4(%rsi,%rdx,1),%edi
 1001ce5:	31 c0                	xor    %eax,%eax
 1001ce7:	09 cf                	or     %ecx,%edi
 1001ce9:	e9 c2 fe ff ff       	jmp    1001bb0 <main+0x3d0>
 1001cee:	48 81 fa 00 01 00 00 	cmp    $0x100,%rdx
 1001cf5:	77 4c                	ja     1001d43 <main+0x563>
 1001cf7:	c5 f8 77             	vzeroupper
 1001cfa:	e8 71 01 00 00       	call   1001e70 <bcmp@plt>
 1001cff:	89 c1                	mov    %eax,%ecx
 1001d01:	31 c0                	xor    %eax,%eax
 1001d03:	85 c9                	test   %ecx,%ecx
 1001d05:	0f 94 c0             	sete   %al
 1001d08:	eb 41                	jmp    1001d4b <main+0x56b>
 1001d0a:	c5 fe 6f 4c 17 e0    	vmovdqu -0x20(%rdi,%rdx,1),%ymm1
 1001d10:	c4 e3 7d 38 47 10 01 	vinserti128 $0x1,0x10(%rdi),%ymm0,%ymm0
 1001d17:	c5 f5 ef 4c 16 e0    	vpxor  -0x20(%rsi,%rdx,1),%ymm1,%ymm1
 1001d1d:	c5 fd ef 06          	vpxor  (%rsi),%ymm0,%ymm0
 1001d21:	c5 fd eb c1          	vpor   %ymm1,%ymm0,%ymm0
 1001d25:	31 c0                	xor    %eax,%eax
 1001d27:	c4 e2 7d 17 c0       	vptest %ymm0,%ymm0
 1001d2c:	e9 7f fe ff ff       	jmp    1001bb0 <main+0x3d0>
 1001d31:	48 83 fa 01          	cmp    $0x1,%rdx
 1001d35:	75 1d                	jne    1001d54 <main+0x574>
 1001d37:	0f b6 0f             	movzbl (%rdi),%ecx
 1001d3a:	31 c0                	xor    %eax,%eax
 1001d3c:	3a 0e                	cmp    (%rsi),%cl
 1001d3e:	e9 6d fe ff ff       	jmp    1001bb0 <main+0x3d0>
 1001d43:	c5 f8 77             	vzeroupper
 1001d46:	e8 55 fa ff ff       	call   10017a0 <equal_large_octets>
 1001d4b:	4c 8b 45 c8          	mov    -0x38(%rbp),%r8
 1001d4f:	e9 6c fe ff ff       	jmp    1001bc0 <main+0x3e0>
 1001d54:	0f b7 0f             	movzwl (%rdi),%ecx
 1001d57:	0f b7 7c 17 fe       	movzwl -0x2(%rdi,%rdx,1),%edi
 1001d5c:	66 33 0e             	xor    (%rsi),%cx
 1001d5f:	66 33 7c 16 fe       	xor    -0x2(%rsi,%rdx,1),%di
 1001d64:	31 c0                	xor    %eax,%eax
 1001d66:	66 09 cf             	or     %cx,%di
 1001d69:	e9 42 fe ff ff       	jmp    1001bb0 <main+0x3d0>
 1001d6e:	48 8d 75 90          	lea    -0x70(%rbp),%rsi
 1001d72:	bf 01 00 00 00       	mov    $0x1,%edi
 1001d77:	c5 f8 77             	vzeroupper
 1001d7a:	e8 51 01 00 00       	call   1001ed0 <clock_gettime@plt>
 1001d7f:	85 c0                	test   %eax,%eax
 1001d81:	0f 85 85 00 00 00    	jne    1001e0c <main+0x62c>
 1001d87:	c5 f9 6f 45 90       	vmovdqa -0x70(%rbp),%xmm0
 1001d8c:	c5 f9 fb 45 a0       	vpsubq -0x60(%rbp),%xmm0,%xmm0
 1001d91:	c4 e1 f9 7e c0       	vmovq  %xmm0,%rax
 1001d96:	48 69 c0 00 ca 9a 3b 	imul   $0x3b9aca00,%rax,%rax
 1001d9d:	c4 e3 f9 16 c2 01    	vpextrq $0x1,%xmm0,%rdx
 1001da3:	48 01 c2             	add    %rax,%rdx
 1001da6:	31 db                	xor    %ebx,%ebx
 1001da8:	bf 90 06 00 01       	mov    $0x1000690,%edi
 1001dad:	4c 89 fe             	mov    %r15,%rsi
 1001db0:	31 c0                	xor    %eax,%eax
 1001db2:	e8 f9 00 00 00       	call   1001eb0 <printf@plt>
 1001db7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 1001dbe:	00 00 
 1001dc0:	48 8b bc dd 60 f7 ff 	mov    -0x8a0(%rbp,%rbx,8),%rdi
 1001dc7:	ff 
 1001dc8:	e8 93 00 00 00       	call   1001e60 <free@plt>
 1001dcd:	48 8b bc dd 60 ef ff 	mov    -0x10a0(%rbp,%rbx,8),%rdi
 1001dd4:	ff 
 1001dd5:	e8 86 00 00 00       	call   1001e60 <free@plt>
 1001dda:	48 ff c3             	inc    %rbx
 1001ddd:	48 81 fb 00 01 00 00 	cmp    $0x100,%rbx
 1001de4:	75 da                	jne    1001dc0 <main+0x5e0>
 1001de6:	31 c0                	xor    %eax,%eax
 1001de8:	80 7d d7 00          	cmpb   $0x0,-0x29(%rbp)
 1001dec:	4c 0f 45 e0          	cmovne %rax,%r12
 1001df0:	31 db                	xor    %ebx,%ebx
 1001df2:	4d 39 e7             	cmp    %r12,%r15
 1001df5:	0f 95 c3             	setne  %bl
 1001df8:	89 d8                	mov    %ebx,%eax
 1001dfa:	48 81 c4 78 50 00 00 	add    $0x5078,%rsp
 1001e01:	5b                   	pop    %rbx
 1001e02:	41 5c                	pop    %r12
 1001e04:	41 5d                	pop    %r13
 1001e06:	41 5e                	pop    %r14
 1001e08:	41 5f                	pop    %r15
 1001e0a:	5d                   	pop    %rbp
 1001e0b:	c3                   	ret
 1001e0c:	e8 8f 00 00 00       	call   1001ea0 <abort@plt>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
