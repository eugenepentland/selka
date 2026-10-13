
.tmp/lox-eda-parity/P2/scalar-ip-001/candidate:     file format elf64-x86-64


Disassembly of section .text:

0000000001062900 <my.vm::read_byte>:
 1062900:	50                   	push   %rax
 1062901:	48 8b 0f             	mov    (%rdi),%rcx
 1062904:	48 8b 41 08          	mov    0x8(%rcx),%rax
 1062908:	48 39 c6             	cmp    %rax,%rsi
 106290b:	73 37                	jae    1062944 <my.vm::read_byte+0x44>
 106290d:	48 89 f7             	mov    %rsi,%rdi
 1062910:	48 6b c7 38          	imul   $0x38,%rdi,%rax
 1062914:	83 7c 01 20 02       	cmpl   $0x2,0x20(%rcx,%rax,1)
 1062919:	75 6e                	jne    1062989 <my.vm::read_byte+0x89>
 106291b:	48 01 c8             	add    %rcx,%rax
 106291e:	48 83 c0 20          	add    $0x20,%rax
 1062922:	48 8b 70 18          	mov    0x18(%rax),%rsi
 1062926:	48 8b 46 08          	mov    0x8(%rsi),%rax
 106292a:	48 89 d7             	mov    %rdx,%rdi
 106292d:	48 39 c2             	cmp    %rax,%rdx
 1062930:	73 33                	jae    1062965 <my.vm::read_byte+0x65>
 1062932:	48 89 d1             	mov    %rdx,%rcx
 1062935:	48 ff c1             	inc    %rcx
 1062938:	70 5b                	jo     1062995 <my.vm::read_byte+0x95>
 106293a:	48 8b 44 fe 20       	mov    0x20(%rsi,%rdi,8),%rax
 106293f:	48 89 ca             	mov    %rcx,%rdx
 1062942:	59                   	pop    %rcx
 1062943:	c3                   	ret
 1062944:	48 89 f7             	mov    %rsi,%rdi
 1062947:	48 c1 ff 3f          	sar    $0x3f,%rdi
 106294b:	48 21 c7             	and    %rax,%rdi
 106294e:	48 01 f7             	add    %rsi,%rdi
 1062951:	48 39 c7             	cmp    %rax,%rdi
 1062954:	72 ba                	jb     1062910 <my.vm::read_byte+0x10>
 1062956:	48 8d 3d 83 09 02 00 	lea    0x20983(%rip),%rdi        # 10832e0 <core_durable_error.verbs+0x3a50>
 106295d:	48 89 c2             	mov    %rax,%rdx
 1062960:	e8 9b 22 fc ff       	call   1024c00 <myl_core_trap>
 1062965:	48 89 d7             	mov    %rdx,%rdi
 1062968:	48 c1 ff 3f          	sar    $0x3f,%rdi
 106296c:	48 21 c7             	and    %rax,%rdi
 106296f:	48 01 d7             	add    %rdx,%rdi
 1062972:	48 39 c7             	cmp    %rax,%rdi
 1062975:	72 bb                	jb     1062932 <my.vm::read_byte+0x32>
 1062977:	48 8d 3d c2 09 02 00 	lea    0x209c2(%rip),%rdi        # 1083340 <core_durable_error.verbs+0x3ab0>
 106297e:	48 89 d6             	mov    %rdx,%rsi
 1062981:	48 89 c2             	mov    %rax,%rdx
 1062984:	e8 77 22 fc ff       	call   1024c00 <myl_core_trap>
 1062989:	48 8d 3d 80 09 02 00 	lea    0x20980(%rip),%rdi        # 1083310 <core_durable_error.verbs+0x3a80>
 1062990:	e8 eb 75 fc ff       	call   1029f80 <myl_core_assert_fail>
 1062995:	48 8d 3d 34 ec 01 00 	lea    0x1ec34(%rip),%rdi        # 10815d0 <core_durable_error.verbs+0x1d40>
 106299c:	48 89 d6             	mov    %rdx,%rsi
 106299f:	ba 01 00 00 00       	mov    $0x1,%edx
 10629a4:	e8 57 22 fc ff       	call   1024c00 <myl_core_trap>

Disassembly of section .plt:
