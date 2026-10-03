
/home/epentland/.cache/mylang-tmp/runtime-parity-arithmetic-20261003/native_bytes-bulk.o:     file format elf64-x86-64


Disassembly of section .text.myl_native_bytes_sum_xor:

0000000000000000 <myl_native_bytes_sum_xor>:
   0:	55                   	push   %rbp
   1:	48 89 e5             	mov    %rsp,%rbp
   4:	48 83 fe 10          	cmp    $0x10,%rsi
   8:	72 1c                	jb     26 <myl_native_bytes_sum_xor+0x26>
   a:	c5 f9 6e c2          	vmovd  %edx,%xmm0
   e:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
  13:	48 8d 46 f0          	lea    -0x10(%rsi),%rax
  17:	89 c1                	mov    %eax,%ecx
  19:	f7 d1                	not    %ecx
  1b:	f6 c1 30             	test   $0x30,%cl
  1e:	75 16                	jne    36 <myl_native_bytes_sum_xor+0x36>
  20:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
  24:	eb 43                	jmp    69 <myl_native_bytes_sum_xor+0x69>
  26:	31 c0                	xor    %eax,%eax
  28:	48 85 f6             	test   %rsi,%rsi
  2b:	0f 85 a7 00 00 00    	jne    d8 <myl_native_bytes_sum_xor+0xd8>
  31:	e9 3c 01 00 00       	jmp    172 <myl_native_bytes_sum_xor+0x172>
  36:	89 c1                	mov    %eax,%ecx
  38:	c1 e9 04             	shr    $0x4,%ecx
  3b:	ff c1                	inc    %ecx
  3d:	83 e1 03             	and    $0x3,%ecx
  40:	c5 e9 ef d2          	vpxor  %xmm2,%xmm2,%xmm2
  44:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
  48:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
  4f:	00 
  50:	c5 f9 ef 1f          	vpxor  (%rdi),%xmm0,%xmm3
  54:	c5 e1 f6 da          	vpsadbw %xmm2,%xmm3,%xmm3
  58:	c5 e1 d4 c9          	vpaddq %xmm1,%xmm3,%xmm1
  5c:	48 83 c7 10          	add    $0x10,%rdi
  60:	48 83 c6 f0          	add    $0xfffffffffffffff0,%rsi
  64:	48 ff c9             	dec    %rcx
  67:	75 e7                	jne    50 <myl_native_bytes_sum_xor+0x50>
  69:	48 83 f8 30          	cmp    $0x30,%rax
  6d:	72 52                	jb     c1 <myl_native_bytes_sum_xor+0xc1>
  6f:	c5 e9 ef d2          	vpxor  %xmm2,%xmm2,%xmm2
  73:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  7a:	84 00 00 00 00 00 
  80:	c5 f9 ef 1f          	vpxor  (%rdi),%xmm0,%xmm3
  84:	c5 e1 f6 da          	vpsadbw %xmm2,%xmm3,%xmm3
  88:	c5 e1 d4 c9          	vpaddq %xmm1,%xmm3,%xmm1
  8c:	c5 f9 ef 5f 10       	vpxor  0x10(%rdi),%xmm0,%xmm3
  91:	c5 e1 f6 da          	vpsadbw %xmm2,%xmm3,%xmm3
  95:	c5 f9 ef 67 20       	vpxor  0x20(%rdi),%xmm0,%xmm4
  9a:	c5 d9 f6 e2          	vpsadbw %xmm2,%xmm4,%xmm4
  9e:	c5 d9 d4 db          	vpaddq %xmm3,%xmm4,%xmm3
  a2:	c5 e1 d4 c9          	vpaddq %xmm1,%xmm3,%xmm1
  a6:	c5 f9 ef 5f 30       	vpxor  0x30(%rdi),%xmm0,%xmm3
  ab:	c5 e1 f6 da          	vpsadbw %xmm2,%xmm3,%xmm3
  af:	c5 e1 d4 c9          	vpaddq %xmm1,%xmm3,%xmm1
  b3:	48 83 c7 40          	add    $0x40,%rdi
  b7:	48 83 c6 c0          	add    $0xffffffffffffffc0,%rsi
  bb:	48 83 fe 0f          	cmp    $0xf,%rsi
  bf:	77 bf                	ja     80 <myl_native_bytes_sum_xor+0x80>
  c1:	c5 f9 70 c1 ee       	vpshufd $0xee,%xmm1,%xmm0
  c6:	c5 f1 d4 c0          	vpaddq %xmm0,%xmm1,%xmm0
  ca:	c4 e1 f9 7e c0       	vmovq  %xmm0,%rax
  cf:	48 85 f6             	test   %rsi,%rsi
  d2:	0f 84 9a 00 00 00    	je     172 <myl_native_bytes_sum_xor+0x172>
  d8:	48 89 f1             	mov    %rsi,%rcx
  db:	48 83 e1 03          	and    $0x3,%rcx
  df:	74 37                	je     118 <myl_native_bytes_sum_xor+0x118>
  e1:	45 31 c0             	xor    %r8d,%r8d
  e4:	66 66 66 2e 0f 1f 84 	data16 data16 cs nopw 0x0(%rax,%rax,1)
  eb:	00 00 00 00 00 
  f0:	46 0f b6 0c 07       	movzbl (%rdi,%r8,1),%r9d
  f5:	41 30 d1             	xor    %dl,%r9b
  f8:	45 0f b6 c9          	movzbl %r9b,%r9d
  fc:	4c 01 c8             	add    %r9,%rax
  ff:	49 ff c0             	inc    %r8
 102:	4c 39 c1             	cmp    %r8,%rcx
 105:	75 e9                	jne    f0 <myl_native_bytes_sum_xor+0xf0>
 107:	4c 01 c7             	add    %r8,%rdi
 10a:	48 89 f1             	mov    %rsi,%rcx
 10d:	4c 29 c1             	sub    %r8,%rcx
 110:	48 83 fe 04          	cmp    $0x4,%rsi
 114:	73 0b                	jae    121 <myl_native_bytes_sum_xor+0x121>
 116:	eb 5a                	jmp    172 <myl_native_bytes_sum_xor+0x172>
 118:	48 89 f1             	mov    %rsi,%rcx
 11b:	48 83 fe 04          	cmp    $0x4,%rsi
 11f:	72 51                	jb     172 <myl_native_bytes_sum_xor+0x172>
 121:	31 f6                	xor    %esi,%esi
 123:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 12a:	84 00 00 00 00 00 
 130:	44 0f b6 04 37       	movzbl (%rdi,%rsi,1),%r8d
 135:	41 30 d0             	xor    %dl,%r8b
 138:	45 0f b6 c0          	movzbl %r8b,%r8d
 13c:	49 01 c0             	add    %rax,%r8
 13f:	0f b6 44 37 01       	movzbl 0x1(%rdi,%rsi,1),%eax
 144:	30 d0                	xor    %dl,%al
 146:	0f b6 c0             	movzbl %al,%eax
 149:	44 0f b6 4c 37 02    	movzbl 0x2(%rdi,%rsi,1),%r9d
 14f:	41 30 d1             	xor    %dl,%r9b
 152:	45 0f b6 c9          	movzbl %r9b,%r9d
 156:	49 01 c1             	add    %rax,%r9
 159:	4d 01 c1             	add    %r8,%r9
 15c:	0f b6 44 37 03       	movzbl 0x3(%rdi,%rsi,1),%eax
 161:	30 d0                	xor    %dl,%al
 163:	0f b6 c0             	movzbl %al,%eax
 166:	4c 01 c8             	add    %r9,%rax
 169:	48 83 c6 04          	add    $0x4,%rsi
 16d:	48 39 f1             	cmp    %rsi,%rcx
 170:	75 be                	jne    130 <myl_native_bytes_sum_xor+0x130>
 172:	5d                   	pop    %rbp
 173:	c3                   	ret

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
