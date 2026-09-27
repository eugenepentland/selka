 1004ff0:	movq   $0xf42400,-0x38(%rbp)
 1004ff8:	cmp    $0xf42400,%r13
 1004fff:	jge    10050b4 <calloc@plt-0xa81c>
 1005005:	mov    0x10(%rbx),%rax
 1005009:	mov    (%rbx),%rcx
 100500c:	mov    0x8(%rbx),%rdx
 1005010:	cmp    %rdx,%rcx
 1005013:	jb     100505f <calloc@plt-0xa871>
 100505f:	mov    0x20(%rbx),%rdx
 1005063:	mov    %r13,(%rdx,%rcx,8)
 1005067:	add    $0x1,%rcx
 100506b:	mov    %rcx,(%rbx)
 100506e:	add    $0x1,%rax
 1005072:	mov    %rax,0x10(%rbx)
 1005076:	movq   $0x1,-0x38(%rbp)
 100507e:	movabs $0x7ffffffffffffffe,%rax
 1005088:	cmp    %rax,%r13
 100508b:	jg     1005096 <calloc@plt-0xa83a>
 100508d:	add    $0x1,%r13
 1005091:	jmp    1004ff0 <calloc@plt-0xa8e0>
