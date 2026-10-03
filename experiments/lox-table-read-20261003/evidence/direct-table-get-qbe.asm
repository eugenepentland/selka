
.tmp-lox-table-read-20261003/bin/direct-entries-qbe:     file format elf64-x86-64


Disassembly of section .text:

000000000111b700 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3>:
 111b700:	f3 0f 1e fa          	endbr64
 111b704:	55                   	push   %rbp
 111b705:	48 89 e5             	mov    %rsp,%rbp
 111b708:	48 83 ec 28          	sub    $0x28,%rsp
 111b70c:	53                   	push   %rbx
 111b70d:	4d 89 c1             	mov    %r8,%r9
 111b710:	49 89 c8             	mov    %rcx,%r8
 111b713:	48 89 d0             	mov    %rdx,%rax
 111b716:	48 89 fb             	mov    %rdi,%rbx
 111b719:	48 89 f7             	mov    %rsi,%rdi
 111b71c:	48 8b 4f 40          	mov    0x40(%rdi),%rcx
 111b720:	48 8d 55 f8          	lea    -0x8(%rbp),%rdx
 111b724:	48 39 ca             	cmp    %rcx,%rdx
 111b727:	72 32                	jb     111b75b <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x5b>
 111b729:	48 8b 10             	mov    (%rax),%rdx
 111b72c:	48 8b 48 08          	mov    0x8(%rax),%rcx
 111b730:	48 89 fe             	mov    %rdi,%rsi
 111b733:	48 8d 7d e0          	lea    -0x20(%rbp),%rdi
 111b737:	e8 64 02 00 00       	call   111b9a0 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f>
 111b73c:	48 89 c1             	mov    %rax,%rcx
 111b73f:	48 89 d8             	mov    %rbx,%rax
 111b742:	48 8b 11             	mov    (%rcx),%rdx
 111b745:	48 89 10             	mov    %rdx,(%rax)
 111b748:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 111b74c:	48 89 50 08          	mov    %rdx,0x8(%rax)
 111b750:	48 8b 49 10          	mov    0x10(%rcx),%rcx
 111b754:	48 89 48 10          	mov    %rcx,0x10(%rax)
 111b758:	5b                   	pop    %rbx
 111b759:	c9                   	leave
 111b75a:	c3                   	ret
 111b75b:	e8 30 fd 03 00       	call   115b490 <myl_qbe_fail_frame>
 111b760:	0f 0b                	ud2

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
