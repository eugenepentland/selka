 10079e0:	mov    %r9,-0x60(%rbp)
 10079e4:	mov    %rax,-0x58(%rbp)
 10079e8:	cmp    %rax,%r9
 10079eb:	setl   %r8b
 10079ef:	movzbq %r8b,%r8
 10079f3:	mov    %r8,-0x60(%rbp)
 10079f7:	jge    1007ae4 <myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605+0xda4>
 10079fd:	mov    %rax,-0x60(%rbp)
 1007a01:	mov    (%rcx),%r8
 1007a04:	cmp    %r8,%rax
 1007a07:	jne    1007add <myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605+0xd9d>
 1007a0d:	movq   $0x0,-0x60(%rbp)
 1007a15:	mov    %r9,-0x60(%rbp)
 1007a19:	mov    (%rcx),%r8
 1007a1c:	cmp    %r8,%r9
 1007a1f:	jae    1007ad0 <myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605+0xd90>
 1007a25:	mov    0x20(%rcx),%r8
 1007a29:	mov    (%r8,%r9,8),%r11
 1007a2d:	mov    %r11,-0x60(%rbp)
 1007a31:	mov    %rdx,-0x60(%rbp)
 1007a35:	mov    %r11,-0x58(%rbp)
 1007a39:	mov    %rdx,%r10
 1007a3c:	add    %r11,%rdx
 1007a3f:	mov    %r10,%r8
 1007a42:	xor    %rdx,%r8
 1007a45:	mov    %r11,%rbx
 1007a48:	xor    %rdx,%rbx
 1007a4b:	and    %rbx,%r8
 1007a4e:	cmp    $0x0,%r8
 1007a52:	jl     1007ab8 <myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605+0xd78>
 1007a54:	mov    %rdx,-0x60(%rbp)
 1007a58:	mov    %rax,-0x60(%rbp)
 1007a5c:	mov    (%rcx),%r8
 1007a5f:	cmp    %r8,%rax
 1007a62:	jne    1007ab1 <myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605+0xd71>
 1007a64:	movq   $0x0,-0x60(%rbp)
 1007a6c:	mov    %r9,-0x60(%rbp)
 1007a70:	movq   $0x1,-0x58(%rbp)
 1007a78:	movabs $0x7ffffffffffffffe,%r8
 1007a82:	cmp    %r8,%r9
 1007a85:	jg     1007a94 <myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605+0xd54>
 1007a87:	add    $0x1,%r9
 1007a8b:	mov    %r9,-0x60(%rbp)
 1007a8f:	jmp    10079e0 <myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605+0xca0>
