
.mylang-cache/goal110-text/equality-text-llvm:     file format elf64-x86-64


Disassembly of section .text:

0000000001091d30 <myl_native_text_equal>:
 1091d30:	48 39 f7             	cmp    %rsi,%rdi
 1091d33:	74 62                	je     1091d97 <myl_native_text_equal+0x67>
 1091d35:	48 85 ff             	test   %rdi,%rdi
 1091d38:	0f 94 c1             	sete   %cl
 1091d3b:	48 85 f6             	test   %rsi,%rsi
 1091d3e:	0f 94 c2             	sete   %dl
 1091d41:	31 c0                	xor    %eax,%eax
 1091d43:	08 ca                	or     %cl,%dl
 1091d45:	0f 85 d7 00 00 00    	jne    1091e22 <myl_native_text_equal+0xf2>
 1091d4b:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 1091d4f:	48 3b 56 08          	cmp    0x8(%rsi),%rdx
 1091d53:	0f 85 c9 00 00 00    	jne    1091e22 <myl_native_text_equal+0xf2>
 1091d59:	f6 47 10 04          	testb  $0x4,0x10(%rdi)
 1091d5d:	75 3e                	jne    1091d9d <myl_native_text_equal+0x6d>
 1091d5f:	48 83 c7 18          	add    $0x18,%rdi
 1091d63:	f6 46 10 04          	testb  $0x4,0x10(%rsi)
 1091d67:	74 49                	je     1091db2 <myl_native_text_equal+0x82>
 1091d69:	48 8b 46 18          	mov    0x18(%rsi),%rax
 1091d6d:	8b 4e 14             	mov    0x14(%rsi),%ecx
 1091d70:	48 8d 34 08          	lea    (%rax,%rcx,1),%rsi
 1091d74:	48 83 c6 18          	add    $0x18,%rsi
 1091d78:	48 83 fa 08          	cmp    $0x8,%rdx
 1091d7c:	73 3e                	jae    1091dbc <myl_native_text_equal+0x8c>
 1091d7e:	48 83 fa 04          	cmp    $0x4,%rdx
 1091d82:	72 73                	jb     1091df7 <myl_native_text_equal+0xc7>
 1091d84:	8b 07                	mov    (%rdi),%eax
 1091d86:	8b 4c 17 fc          	mov    -0x4(%rdi,%rdx,1),%ecx
 1091d8a:	33 06                	xor    (%rsi),%eax
 1091d8c:	33 4c 16 fc          	xor    -0x4(%rsi,%rdx,1),%ecx
 1091d90:	09 c1                	or     %eax,%ecx
 1091d92:	e9 85 00 00 00       	jmp    1091e1c <myl_native_text_equal+0xec>
 1091d97:	b8 01 00 00 00       	mov    $0x1,%eax
 1091d9c:	c3                   	ret
 1091d9d:	48 8b 47 18          	mov    0x18(%rdi),%rax
 1091da1:	8b 4f 14             	mov    0x14(%rdi),%ecx
 1091da4:	48 8d 3c 08          	lea    (%rax,%rcx,1),%rdi
 1091da8:	48 83 c7 18          	add    $0x18,%rdi
 1091dac:	f6 46 10 04          	testb  $0x4,0x10(%rsi)
 1091db0:	75 b7                	jne    1091d69 <myl_native_text_equal+0x39>
 1091db2:	48 83 c6 18          	add    $0x18,%rsi
 1091db6:	48 83 fa 08          	cmp    $0x8,%rdx
 1091dba:	72 c2                	jb     1091d7e <myl_native_text_equal+0x4e>
 1091dbc:	48 8b 0f             	mov    (%rdi),%rcx
 1091dbf:	31 c0                	xor    %eax,%eax
 1091dc1:	48 3b 0e             	cmp    (%rsi),%rcx
 1091dc4:	75 59                	jne    1091e1f <myl_native_text_equal+0xef>
 1091dc6:	48 8b 4c 16 f8       	mov    -0x8(%rsi,%rdx,1),%rcx
 1091dcb:	48 39 4c 17 f8       	cmp    %rcx,-0x8(%rdi,%rdx,1)
 1091dd0:	75 4d                	jne    1091e1f <myl_native_text_equal+0xef>
 1091dd2:	b0 01                	mov    $0x1,%al
 1091dd4:	48 83 fa 11          	cmp    $0x11,%rdx
 1091dd8:	72 45                	jb     1091e1f <myl_native_text_equal+0xef>
 1091dda:	55                   	push   %rbp
 1091ddb:	48 89 e5             	mov    %rsp,%rbp
 1091dde:	48 83 c7 08          	add    $0x8,%rdi
 1091de2:	48 83 c6 08          	add    $0x8,%rsi
 1091de6:	48 83 c2 f0          	add    $0xfffffffffffffff0,%rdx
 1091dea:	e8 61 94 01 00       	call   10ab250 <bcmp@plt>
 1091def:	85 c0                	test   %eax,%eax
 1091df1:	0f 94 c0             	sete   %al
 1091df4:	5d                   	pop    %rbp
 1091df5:	eb 28                	jmp    1091e1f <myl_native_text_equal+0xef>
 1091df7:	48 83 fa 02          	cmp    $0x2,%rdx
 1091dfb:	72 15                	jb     1091e12 <myl_native_text_equal+0xe2>
 1091dfd:	0f b7 07             	movzwl (%rdi),%eax
 1091e00:	0f b7 4c 17 fe       	movzwl -0x2(%rdi,%rdx,1),%ecx
 1091e05:	66 33 06             	xor    (%rsi),%ax
 1091e08:	66 33 4c 16 fe       	xor    -0x2(%rsi,%rdx,1),%cx
 1091e0d:	66 09 c1             	or     %ax,%cx
 1091e10:	eb 0a                	jmp    1091e1c <myl_native_text_equal+0xec>
 1091e12:	48 85 d2             	test   %rdx,%rdx
 1091e15:	74 0c                	je     1091e23 <myl_native_text_equal+0xf3>
 1091e17:	0f b6 07             	movzbl (%rdi),%eax
 1091e1a:	3a 06                	cmp    (%rsi),%al
 1091e1c:	0f 94 c0             	sete   %al
 1091e1f:	0f b6 c0             	movzbl %al,%eax
 1091e22:	c3                   	ret
 1091e23:	b0 01                	mov    $0x1,%al
 1091e25:	eb f8                	jmp    1091e1f <myl_native_text_equal+0xef>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
