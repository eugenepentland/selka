
/home/epentland/.cache/mylang-tmp/runtime-parity-arithmetic-20261003/native_bytes-bulk-baseline.o:     file format elf64-x86-64


Disassembly of section .text.myl_native_bytes_sum_xor:

0000000000000000 <myl_native_bytes_sum_xor>:
   0:	55                   	push   %rbp
   1:	48 89 e5             	mov    %rsp,%rbp
   4:	66 0f ef d2          	pxor   %xmm2,%xmm2
   8:	48 83 fe 10          	cmp    $0x10,%rsi
   c:	0f 82 c3 00 00 00    	jb     d5 <myl_native_bytes_sum_xor+0xd5>
  12:	66 0f 6e c2          	movd   %edx,%xmm0
  16:	66 0f 60 c0          	punpcklbw %xmm0,%xmm0
  1a:	f2 0f 70 c0 00       	pshuflw $0x0,%xmm0,%xmm0
  1f:	66 0f 70 c0 44       	pshufd $0x44,%xmm0,%xmm0
  24:	48 8d 46 f0          	lea    -0x10(%rsi),%rax
  28:	89 c1                	mov    %eax,%ecx
  2a:	f7 d1                	not    %ecx
  2c:	f6 c1 30             	test   $0x30,%cl
  2f:	75 06                	jne    37 <myl_native_bytes_sum_xor+0x37>
  31:	66 0f ef c9          	pxor   %xmm1,%xmm1
  35:	eb 37                	jmp    6e <myl_native_bytes_sum_xor+0x6e>
  37:	89 c1                	mov    %eax,%ecx
  39:	c1 e9 04             	shr    $0x4,%ecx
  3c:	83 c1 01             	add    $0x1,%ecx
  3f:	83 e1 03             	and    $0x3,%ecx
  42:	66 0f ef c9          	pxor   %xmm1,%xmm1
  46:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
  4d:	00 00 00 
  50:	f3 0f 6f 1f          	movdqu (%rdi),%xmm3
  54:	66 0f ef d8          	pxor   %xmm0,%xmm3
  58:	66 0f f6 da          	psadbw %xmm2,%xmm3
  5c:	66 0f d4 cb          	paddq  %xmm3,%xmm1
  60:	48 83 c7 10          	add    $0x10,%rdi
  64:	48 83 c6 f0          	add    $0xfffffffffffffff0,%rsi
  68:	48 83 c1 ff          	add    $0xffffffffffffffff,%rcx
  6c:	75 e2                	jne    50 <myl_native_bytes_sum_xor+0x50>
  6e:	66 0f 6f d1          	movdqa %xmm1,%xmm2
  72:	48 83 f8 30          	cmp    $0x30,%rax
  76:	72 5d                	jb     d5 <myl_native_bytes_sum_xor+0xd5>
  78:	66 0f ef db          	pxor   %xmm3,%xmm3
  7c:	0f 1f 40 00          	nopl   0x0(%rax)
  80:	f3 0f 6f 27          	movdqu (%rdi),%xmm4
  84:	f3 0f 6f 6f 10       	movdqu 0x10(%rdi),%xmm5
  89:	f3 0f 6f 77 20       	movdqu 0x20(%rdi),%xmm6
  8e:	f3 0f 6f 57 30       	movdqu 0x30(%rdi),%xmm2
  93:	66 0f ef e0          	pxor   %xmm0,%xmm4
  97:	66 0f f6 e3          	psadbw %xmm3,%xmm4
  9b:	66 0f d4 e1          	paddq  %xmm1,%xmm4
  9f:	66 0f ef e8          	pxor   %xmm0,%xmm5
  a3:	66 0f f6 eb          	psadbw %xmm3,%xmm5
  a7:	66 0f ef f0          	pxor   %xmm0,%xmm6
  ab:	66 0f f6 f3          	psadbw %xmm3,%xmm6
  af:	66 0f d4 f5          	paddq  %xmm5,%xmm6
  b3:	66 0f d4 f4          	paddq  %xmm4,%xmm6
  b7:	66 0f ef d0          	pxor   %xmm0,%xmm2
  bb:	66 0f f6 d3          	psadbw %xmm3,%xmm2
  bf:	66 0f d4 d6          	paddq  %xmm6,%xmm2
  c3:	48 83 c7 40          	add    $0x40,%rdi
  c7:	48 83 c6 c0          	add    $0xffffffffffffffc0,%rsi
  cb:	66 0f 6f ca          	movdqa %xmm2,%xmm1
  cf:	48 83 fe 0f          	cmp    $0xf,%rsi
  d3:	77 ab                	ja     80 <myl_native_bytes_sum_xor+0x80>
  d5:	66 0f 70 c2 ee       	pshufd $0xee,%xmm2,%xmm0
  da:	66 0f d4 c2          	paddq  %xmm2,%xmm0
  de:	66 48 0f 7e c0       	movq   %xmm0,%rax
  e3:	48 85 f6             	test   %rsi,%rsi
  e6:	0f 84 96 00 00 00    	je     182 <myl_native_bytes_sum_xor+0x182>
  ec:	48 89 f1             	mov    %rsi,%rcx
  ef:	48 83 e1 03          	and    $0x3,%rcx
  f3:	74 34                	je     129 <myl_native_bytes_sum_xor+0x129>
  f5:	45 31 c0             	xor    %r8d,%r8d
  f8:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
  ff:	00 
 100:	46 0f b6 0c 07       	movzbl (%rdi,%r8,1),%r9d
 105:	41 30 d1             	xor    %dl,%r9b
 108:	45 0f b6 c9          	movzbl %r9b,%r9d
 10c:	4c 01 c8             	add    %r9,%rax
 10f:	49 83 c0 01          	add    $0x1,%r8
 113:	4c 39 c1             	cmp    %r8,%rcx
 116:	75 e8                	jne    100 <myl_native_bytes_sum_xor+0x100>
 118:	4c 01 c7             	add    %r8,%rdi
 11b:	48 89 f1             	mov    %rsi,%rcx
 11e:	4c 29 c1             	sub    %r8,%rcx
 121:	48 83 fe 04          	cmp    $0x4,%rsi
 125:	73 0b                	jae    132 <myl_native_bytes_sum_xor+0x132>
 127:	eb 59                	jmp    182 <myl_native_bytes_sum_xor+0x182>
 129:	48 89 f1             	mov    %rsi,%rcx
 12c:	48 83 fe 04          	cmp    $0x4,%rsi
 130:	72 50                	jb     182 <myl_native_bytes_sum_xor+0x182>
 132:	31 f6                	xor    %esi,%esi
 134:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 13b:	00 00 00 
 13e:	66 90                	xchg   %ax,%ax
 140:	44 0f b6 04 37       	movzbl (%rdi,%rsi,1),%r8d
 145:	41 30 d0             	xor    %dl,%r8b
 148:	45 0f b6 c0          	movzbl %r8b,%r8d
 14c:	49 01 c0             	add    %rax,%r8
 14f:	0f b6 44 37 01       	movzbl 0x1(%rdi,%rsi,1),%eax
 154:	30 d0                	xor    %dl,%al
 156:	0f b6 c0             	movzbl %al,%eax
 159:	44 0f b6 4c 37 02    	movzbl 0x2(%rdi,%rsi,1),%r9d
 15f:	41 30 d1             	xor    %dl,%r9b
 162:	45 0f b6 c9          	movzbl %r9b,%r9d
 166:	49 01 c1             	add    %rax,%r9
 169:	4d 01 c1             	add    %r8,%r9
 16c:	0f b6 44 37 03       	movzbl 0x3(%rdi,%rsi,1),%eax
 171:	30 d0                	xor    %dl,%al
 173:	0f b6 c0             	movzbl %al,%eax
 176:	4c 01 c8             	add    %r9,%rax
 179:	48 83 c6 04          	add    $0x4,%rsi
 17d:	48 39 f1             	cmp    %rsi,%rcx
 180:	75 be                	jne    140 <myl_native_bytes_sum_xor+0x140>
 182:	5d                   	pop    %rbp
 183:	c3                   	ret

Disassembly of section .text.myl_native_bytes_new:

Disassembly of section .text.myl_native_bytes_copy:

Disassembly of section .text.myl_native_bytes_equal:

Disassembly of section .text.myl_native_bytes_view:

Disassembly of section .text.myl_native_bytes_buffer_snapshot:

Disassembly of section .text.myl_native_bytes_scalar_count:

Disassembly of section .text.scalar_count:

Disassembly of section .text.myl_native_bytes_scalar_count_range:

Disassembly of section .text.myl_native_bytes_range:

Disassembly of section .text.myl_native_bytes_concat:

Disassembly of section .text.myl_native_bytes_slice:

Disassembly of section .text.myl_native_bytes_find:

Disassembly of section .text.myl_native_bytes_find_any:

Disassembly of section .text.myl_native_bytes_starts_with:

Disassembly of section .text.myl_native_bytes_ends_with:

Disassembly of section .text.myl_native_bytes_compare:

Disassembly of section .text.myl_native_bytes_has_byte:

Disassembly of section .text.myl_native_bytes_split:

Disassembly of section .text.myl_native_bytes_split_whitespace:

Disassembly of section .text.myl_native_bytes_join:

Disassembly of section .text.myl_native_bytes_to_list:

Disassembly of section .text.myl_native_bytes_from_list:

Disassembly of section .text.myl_native_bytes_hex:

Disassembly of section .text.myl_native_bytes_from_hex:

Disassembly of section .text.myl_native_bytes_encode:

Disassembly of section .text.myl_native_bytes_decode:

Disassembly of section .text.myl_native_bytes_decode_range:

Disassembly of section .text.myl_native_bytes_buffer_reserve:

Disassembly of section .text.buffer_ready_rooted:

Disassembly of section .text.myl_native_bytes_buffer_append_byte:

Disassembly of section .text.myl_native_bytes_buffer_append_range:

Disassembly of section .text.myl_native_bytes_buffer_append_utf8:

Disassembly of section .text.myl_native_bytes_buffer_append_raw:

Disassembly of section .text.myl_native_bytes_buffer_append_int:

Disassembly of section .text.myl_native_bytes_copy_octets:

Disassembly of section .text.rc_view_edges:

Disassembly of section .text.rc_bytes_clone_adapter:
