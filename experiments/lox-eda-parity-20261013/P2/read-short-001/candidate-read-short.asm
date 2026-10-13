
.tmp/lox-eda-parity/P2/read-short-001/candidate:     file format elf64-x86-64


Disassembly of section .text:

0000000001063850 <my.vm::read_short>:
 1063850:	53                   	push   %rbx
 1063851:	4d 89 c2             	mov    %r8,%r10
 1063854:	49 83 c2 02          	add    $0x2,%r10
 1063858:	0f 80 13 01 00 00    	jo     1063971 <my.vm::read_short+0x121>
 106385e:	4c 8b 06             	mov    (%rsi),%r8
 1063861:	49 8b 40 08          	mov    0x8(%r8),%rax
 1063865:	48 89 ce             	mov    %rcx,%rsi
 1063868:	48 39 c1             	cmp    %rax,%rcx
 106386b:	0f 83 8b 00 00 00    	jae    10638fc <my.vm::read_short+0xac>
 1063871:	48 6b c6 38          	imul   $0x38,%rsi,%rax
 1063875:	41 83 7c 00 20 02    	cmpl   $0x2,0x20(%r8,%rax,1)
 106387b:	0f 85 04 01 00 00    	jne    1063985 <my.vm::read_short+0x135>
 1063881:	49 8d 72 fe          	lea    -0x2(%r10),%rsi
 1063885:	4c 01 c0             	add    %r8,%rax
 1063888:	48 83 c0 20          	add    $0x20,%rax
 106388c:	4c 8b 58 18          	mov    0x18(%rax),%r11
 1063890:	49 8b 43 08          	mov    0x8(%r11),%rax
 1063894:	48 39 c6             	cmp    %rax,%rsi
 1063897:	0f 83 87 00 00 00    	jae    1063924 <my.vm::read_short+0xd4>
 106389d:	49 89 f0             	mov    %rsi,%r8
 10638a0:	4b 8b 74 c3 20       	mov    0x20(%r11,%r8,8),%rsi
 10638a5:	49 b8 00 00 00 00 00 	movabs $0xff80000000000000,%r8
 10638ac:	00 80 ff 
 10638af:	49 01 f0             	add    %rsi,%r8
 10638b2:	49 c1 e8 38          	shr    $0x38,%r8
 10638b6:	41 81 f8 fe 00 00 00 	cmp    $0xfe,%r8d
 10638bd:	0f 86 ce 00 00 00    	jbe    1063991 <my.vm::read_short+0x141>
 10638c3:	4d 8d 42 ff          	lea    -0x1(%r10),%r8
 10638c7:	49 39 c0             	cmp    %rax,%r8
 10638ca:	73 7e                	jae    106394a <my.vm::read_short+0xfa>
 10638cc:	4c 89 c3             	mov    %r8,%rbx
 10638cf:	48 c1 e6 08          	shl    $0x8,%rsi
 10638d3:	49 8b 44 db 20       	mov    0x20(%r11,%rbx,8),%rax
 10638d8:	49 89 f0             	mov    %rsi,%r8
 10638db:	49 01 c0             	add    %rax,%r8
 10638de:	0f 80 be 00 00 00    	jo     10639a2 <my.vm::read_short+0x152>
 10638e4:	4c 89 07             	mov    %r8,(%rdi)
 10638e7:	48 89 57 08          	mov    %rdx,0x8(%rdi)
 10638eb:	48 89 4f 10          	mov    %rcx,0x10(%rdi)
 10638ef:	4c 89 57 18          	mov    %r10,0x18(%rdi)
 10638f3:	4c 89 4f 20          	mov    %r9,0x20(%rdi)
 10638f7:	48 89 f8             	mov    %rdi,%rax
 10638fa:	5b                   	pop    %rbx
 10638fb:	c3                   	ret
 10638fc:	48 89 ce             	mov    %rcx,%rsi
 10638ff:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1063903:	48 21 c6             	and    %rax,%rsi
 1063906:	48 01 ce             	add    %rcx,%rsi
 1063909:	48 39 c6             	cmp    %rax,%rsi
 106390c:	0f 82 5f ff ff ff    	jb     1063871 <my.vm::read_short+0x21>
 1063912:	48 8d 3d d7 11 02 00 	lea    0x211d7(%rip),%rdi        # 1084af0 <core_durable_error.verbs+0x4aa0>
 1063919:	48 89 ce             	mov    %rcx,%rsi
 106391c:	48 89 c2             	mov    %rax,%rdx
 106391f:	e8 dc 13 fc ff       	call   1024d00 <myl_core_trap>
 1063924:	45 31 c0             	xor    %r8d,%r8d
 1063927:	49 83 fa 02          	cmp    $0x2,%r10
 106392b:	4c 0f 4c c0          	cmovl  %rax,%r8
 106392f:	49 01 f0             	add    %rsi,%r8
 1063932:	49 39 c0             	cmp    %rax,%r8
 1063935:	0f 82 65 ff ff ff    	jb     10638a0 <my.vm::read_short+0x50>
 106393b:	48 8d 3d 0e 12 02 00 	lea    0x2120e(%rip),%rdi        # 1084b50 <core_durable_error.verbs+0x4b00>
 1063942:	48 89 c2             	mov    %rax,%rdx
 1063945:	e8 b6 13 fc ff       	call   1024d00 <myl_core_trap>
 106394a:	31 db                	xor    %ebx,%ebx
 106394c:	4d 85 d2             	test   %r10,%r10
 106394f:	48 0f 4e d8          	cmovle %rax,%rbx
 1063953:	4c 01 c3             	add    %r8,%rbx
 1063956:	48 39 c3             	cmp    %rax,%rbx
 1063959:	0f 82 70 ff ff ff    	jb     10638cf <my.vm::read_short+0x7f>
 106395f:	48 8d 3d 4a 12 02 00 	lea    0x2124a(%rip),%rdi        # 1084bb0 <core_durable_error.verbs+0x4b60>
 1063966:	4c 89 c6             	mov    %r8,%rsi
 1063969:	48 89 c2             	mov    %rax,%rdx
 106396c:	e8 8f 13 fc ff       	call   1024d00 <myl_core_trap>
 1063971:	48 8d 3d 58 ec 01 00 	lea    0x1ec58(%rip),%rdi        # 10825d0 <core_durable_error.verbs+0x2580>
 1063978:	ba 02 00 00 00       	mov    $0x2,%edx
 106397d:	4c 89 c6             	mov    %r8,%rsi
 1063980:	e8 7b 13 fc ff       	call   1024d00 <myl_core_trap>
 1063985:	48 8d 3d 94 11 02 00 	lea    0x21194(%rip),%rdi        # 1084b20 <core_durable_error.verbs+0x4ad0>
 106398c:	e8 ef 66 fc ff       	call   102a080 <myl_core_assert_fail>
 1063991:	48 8d 3d e8 11 02 00 	lea    0x211e8(%rip),%rdi        # 1084b80 <core_durable_error.verbs+0x4b30>
 1063998:	ba 00 01 00 00       	mov    $0x100,%edx
 106399d:	e8 5e 13 fc ff       	call   1024d00 <myl_core_trap>
 10639a2:	48 8d 3d 37 12 02 00 	lea    0x21237(%rip),%rdi        # 1084be0 <core_durable_error.verbs+0x4b90>
 10639a9:	48 89 c2             	mov    %rax,%rdx
 10639ac:	e8 4f 13 fc ff       	call   1024d00 <myl_core_trap>

Disassembly of section .plt:
