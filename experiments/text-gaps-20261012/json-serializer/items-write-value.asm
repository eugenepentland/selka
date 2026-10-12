
.tmp/text-gaps/json-serializer/text-runtime:     file format elf64-x86-64


Disassembly of section .text:

0000000001050030 <my.json::write_value>:
 1050030:	55                   	push   %rbp
 1050031:	41 57                	push   %r15
 1050033:	41 56                	push   %r14
 1050035:	41 55                	push   %r13
 1050037:	41 54                	push   %r12
 1050039:	53                   	push   %rbx
 105003a:	48 83 ec 18          	sub    $0x18,%rsp
 105003e:	48 89 d3             	mov    %rdx,%rbx
 1050041:	40 80 fe 05          	cmp    $0x5,%sil
 1050045:	0f 87 2c 01 00 00    	ja     1050177 <my.json::write_value+0x147>
 105004b:	40 0f b6 c6          	movzbl %sil,%eax
 105004f:	48 8d 0d 8a 73 fb ff 	lea    -0x48c76(%rip),%rcx        # 10073e0 <core_number_pairs+0x140>
 1050056:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
 105005a:	48 01 c8             	add    %rcx,%rax
 105005d:	ff e0                	jmp    *%rax
 105005f:	48 8b 47 08          	mov    0x8(%rdi),%rax
 1050063:	48 8b 4f 10          	mov    0x10(%rdi),%rcx
 1050067:	48 29 c1             	sub    %rax,%rcx
 105006a:	f6 c3 01             	test   $0x1,%bl
 105006d:	0f 84 56 02 00 00    	je     10502c9 <my.json::write_value+0x299>
 1050073:	48 83 f9 04          	cmp    $0x4,%rcx
 1050077:	0f 8c 71 02 00 00    	jl     10502ee <my.json::write_value+0x2be>
 105007d:	c7 44 07 20 74 72 75 	movl   $0x65757274,0x20(%rdi,%rax,1)
 1050084:	65 
 1050085:	eb 70                	jmp    10500f7 <my.json::write_value+0xc7>
 1050087:	48 89 de             	mov    %rbx,%rsi
 105008a:	e8 91 02 00 00       	call   1050320 <my.json::write_quoted>
 105008f:	48 89 c7             	mov    %rax,%rdi
 1050092:	eb 6b                	jmp    10500ff <my.json::write_value+0xcf>
 1050094:	48 89 de             	mov    %rbx,%rsi
 1050097:	48 83 c4 18          	add    $0x18,%rsp
 105009b:	5b                   	pop    %rbx
 105009c:	41 5c                	pop    %r12
 105009e:	41 5d                	pop    %r13
 10500a0:	41 5e                	pop    %r14
 10500a2:	41 5f                	pop    %r15
 10500a4:	5d                   	pop    %rbp
 10500a5:	e9 d6 cc fe ff       	jmp    103cd80 <myl_core_buffer_append_i64>
 10500aa:	c4 e1 f9 6e c3       	vmovq  %rbx,%xmm0
 10500af:	c5 f9 2e c0          	vucomisd %xmm0,%xmm0
 10500b3:	7a 25                	jp     10500da <my.json::write_value+0xaa>
 10500b5:	c5 f9 54 0d 33 41 fb 	vandpd -0x4becd(%rip),%xmm0,%xmm1        # 10041f0 <core_run_timed_out.message+0x90>
 10500bc:	ff 
 10500bd:	c5 f9 2e 0d 23 44 fb 	vucomisd -0x4bbdd(%rip),%xmm1        # 10044e8 <__anon_2214+0x158>
 10500c4:	ff 
 10500c5:	77 13                	ja     10500da <my.json::write_value+0xaa>
 10500c7:	48 83 c4 18          	add    $0x18,%rsp
 10500cb:	5b                   	pop    %rbx
 10500cc:	41 5c                	pop    %r12
 10500ce:	41 5d                	pop    %r13
 10500d0:	41 5e                	pop    %r14
 10500d2:	41 5f                	pop    %r15
 10500d4:	5d                   	pop    %rbp
 10500d5:	e9 d6 4f 00 00       	jmp    10550b0 <myl_core_buffer_append_f64>
 10500da:	48 8b 47 08          	mov    0x8(%rdi),%rax
 10500de:	48 8b 4f 10          	mov    0x10(%rdi),%rcx
 10500e2:	48 29 c1             	sub    %rax,%rcx
 10500e5:	48 83 f9 04          	cmp    $0x4,%rcx
 10500e9:	0f 8c f6 01 00 00    	jl     10502e5 <my.json::write_value+0x2b5>
 10500ef:	c7 44 07 20 6e 75 6c 	movl   $0x6c6c756e,0x20(%rdi,%rax,1)
 10500f6:	6c 
 10500f7:	48 83 c0 04          	add    $0x4,%rax
 10500fb:	48 89 47 08          	mov    %rax,0x8(%rdi)
 10500ff:	48 89 f8             	mov    %rdi,%rax
 1050102:	48 83 c4 18          	add    $0x18,%rsp
 1050106:	5b                   	pop    %rbx
 1050107:	41 5c                	pop    %r12
 1050109:	41 5d                	pop    %r13
 105010b:	41 5e                	pop    %r14
 105010d:	41 5f                	pop    %r15
 105010f:	5d                   	pop    %rbp
 1050110:	c3                   	ret
 1050111:	be 5b 00 00 00       	mov    $0x5b,%esi
 1050116:	e8 e5 cb fe ff       	call   103cd00 <myl_core_buffer_push_checked>
 105011b:	4c 8b 73 08          	mov    0x8(%rbx),%r14
 105011f:	4d 85 f6             	test   %r14,%r14
 1050122:	74 46                	je     105016a <my.json::write_value+0x13a>
 1050124:	48 8b 53 28          	mov    0x28(%rbx),%rdx
 1050128:	8b 73 20             	mov    0x20(%rbx),%esi
 105012b:	48 89 c7             	mov    %rax,%rdi
 105012e:	e8 fd fe ff ff       	call   1050030 <my.json::write_value>
 1050133:	49 83 fe 01          	cmp    $0x1,%r14
 1050137:	74 31                	je     105016a <my.json::write_value+0x13a>
 1050139:	4c 8d 7b 38          	lea    0x38(%rbx),%r15
 105013d:	49 ff ce             	dec    %r14
 1050140:	49 8b 1f             	mov    (%r15),%rbx
 1050143:	41 8b 6f f8          	mov    -0x8(%r15),%ebp
 1050147:	be 2c 00 00 00       	mov    $0x2c,%esi
 105014c:	48 89 c7             	mov    %rax,%rdi
 105014f:	e8 ac cb fe ff       	call   103cd00 <myl_core_buffer_push_checked>
 1050154:	48 89 c7             	mov    %rax,%rdi
 1050157:	89 ee                	mov    %ebp,%esi
 1050159:	48 89 da             	mov    %rbx,%rdx
 105015c:	e8 cf fe ff ff       	call   1050030 <my.json::write_value>
 1050161:	49 83 c7 10          	add    $0x10,%r15
 1050165:	49 ff ce             	dec    %r14
 1050168:	75 d6                	jne    1050140 <my.json::write_value+0x110>
 105016a:	be 5d 00 00 00       	mov    $0x5d,%esi
 105016f:	48 89 c7             	mov    %rax,%rdi
 1050172:	e9 3f 01 00 00       	jmp    10502b6 <my.json::write_value+0x286>
 1050177:	be 7b 00 00 00       	mov    $0x7b,%esi
 105017c:	e8 7f cb fe ff       	call   103cd00 <myl_core_buffer_push_checked>
 1050181:	49 89 c6             	mov    %rax,%r14
 1050184:	4c 8b 6b 08          	mov    0x8(%rbx),%r13
 1050188:	4d 85 ed             	test   %r13,%r13
 105018b:	0f 84 1d 01 00 00    	je     10502ae <my.json::write_value+0x27e>
 1050191:	48 89 df             	mov    %rbx,%rdi
 1050194:	31 f6                	xor    %esi,%esi
 1050196:	e8 a5 ee fc ff       	call   101f040 <myl_core_dict_ordinal>
 105019b:	48 8d 04 40          	lea    (%rax,%rax,2),%rax
 105019f:	4c 8b 7c c3 20       	mov    0x20(%rbx,%rax,8),%r15
 10501a4:	48 89 df             	mov    %rbx,%rdi
 10501a7:	31 f6                	xor    %esi,%esi
 10501a9:	e8 92 ee fc ff       	call   101f040 <myl_core_dict_ordinal>
 10501ae:	48 8d 04 40          	lea    (%rax,%rax,2),%rax
 10501b2:	4c 8b 64 c3 30       	mov    0x30(%rbx,%rax,8),%r12
 10501b7:	48 89 5c 24 08       	mov    %rbx,0x8(%rsp)
 10501bc:	8b 6c c3 28          	mov    0x28(%rbx,%rax,8),%ebp
 10501c0:	4c 89 f7             	mov    %r14,%rdi
 10501c3:	4c 89 fe             	mov    %r15,%rsi
 10501c6:	e8 55 01 00 00       	call   1050320 <my.json::write_quoted>
 10501cb:	be 3a 00 00 00       	mov    $0x3a,%esi
 10501d0:	48 89 c7             	mov    %rax,%rdi
 10501d3:	e8 28 cb fe ff       	call   103cd00 <myl_core_buffer_push_checked>
 10501d8:	48 89 c7             	mov    %rax,%rdi
 10501db:	89 ee                	mov    %ebp,%esi
 10501dd:	4c 89 e2             	mov    %r12,%rdx
 10501e0:	e8 4b fe ff ff       	call   1050030 <my.json::write_value>
 10501e5:	49 89 c6             	mov    %rax,%r14
 10501e8:	49 83 fd 01          	cmp    $0x1,%r13
 10501ec:	0f 84 bc 00 00 00    	je     10502ae <my.json::write_value+0x27e>
 10501f2:	41 bf 01 00 00 00    	mov    $0x1,%r15d
 10501f8:	48 8b 5c 24 08       	mov    0x8(%rsp),%rbx
 10501fd:	4c 89 6c 24 10       	mov    %r13,0x10(%rsp)
 1050202:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050209:	0f 1f 84 00 00 00 00 
 1050210:	00 
 1050211:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050218:	0f 1f 84 00 00 00 00 
 105021f:	00 
 1050220:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050227:	0f 1f 84 00 00 00 00 
 105022e:	00 
 105022f:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050236:	0f 1f 84 00 00 00 00 
 105023d:	00 
 105023e:	66 90                	xchg   %ax,%ax
 1050240:	48 89 df             	mov    %rbx,%rdi
 1050243:	4c 89 fe             	mov    %r15,%rsi
 1050246:	e8 f5 ed fc ff       	call   101f040 <myl_core_dict_ordinal>
 105024b:	48 8d 04 40          	lea    (%rax,%rax,2),%rax
 105024f:	4c 8b 64 c3 20       	mov    0x20(%rbx,%rax,8),%r12
 1050254:	48 89 df             	mov    %rbx,%rdi
 1050257:	4c 89 fe             	mov    %r15,%rsi
 105025a:	e8 e1 ed fc ff       	call   101f040 <myl_core_dict_ordinal>
 105025f:	48 8d 04 40          	lea    (%rax,%rax,2),%rax
 1050263:	4c 8b 6c c3 30       	mov    0x30(%rbx,%rax,8),%r13
 1050268:	8b 6c c3 28          	mov    0x28(%rbx,%rax,8),%ebp
 105026c:	be 2c 00 00 00       	mov    $0x2c,%esi
 1050271:	4c 89 f7             	mov    %r14,%rdi
 1050274:	e8 87 ca fe ff       	call   103cd00 <myl_core_buffer_push_checked>
 1050279:	48 89 c7             	mov    %rax,%rdi
 105027c:	4c 89 e6             	mov    %r12,%rsi
 105027f:	e8 9c 00 00 00       	call   1050320 <my.json::write_quoted>
 1050284:	be 3a 00 00 00       	mov    $0x3a,%esi
 1050289:	48 89 c7             	mov    %rax,%rdi
 105028c:	e8 6f ca fe ff       	call   103cd00 <myl_core_buffer_push_checked>
 1050291:	48 89 c7             	mov    %rax,%rdi
 1050294:	89 ee                	mov    %ebp,%esi
 1050296:	4c 89 ea             	mov    %r13,%rdx
 1050299:	4c 8b 6c 24 10       	mov    0x10(%rsp),%r13
 105029e:	e8 8d fd ff ff       	call   1050030 <my.json::write_value>
 10502a3:	49 89 c6             	mov    %rax,%r14
 10502a6:	49 ff c7             	inc    %r15
 10502a9:	4d 39 fd             	cmp    %r15,%r13
 10502ac:	75 92                	jne    1050240 <my.json::write_value+0x210>
 10502ae:	be 7d 00 00 00       	mov    $0x7d,%esi
 10502b3:	4c 89 f7             	mov    %r14,%rdi
 10502b6:	48 83 c4 18          	add    $0x18,%rsp
 10502ba:	5b                   	pop    %rbx
 10502bb:	41 5c                	pop    %r12
 10502bd:	41 5d                	pop    %r13
 10502bf:	41 5e                	pop    %r14
 10502c1:	41 5f                	pop    %r15
 10502c3:	5d                   	pop    %rbp
 10502c4:	e9 37 ca fe ff       	jmp    103cd00 <myl_core_buffer_push_checked>
 10502c9:	48 83 f9 05          	cmp    $0x5,%rcx
 10502cd:	7c 40                	jl     105030f <my.json::write_value+0x2df>
 10502cf:	c6 44 07 24 65       	movb   $0x65,0x24(%rdi,%rax,1)
 10502d4:	c7 44 07 20 66 61 6c 	movl   $0x736c6166,0x20(%rdi,%rax,1)
 10502db:	73 
 10502dc:	48 83 c0 05          	add    $0x5,%rax
 10502e0:	e9 16 fe ff ff       	jmp    10500fb <my.json::write_value+0xcb>
 10502e5:	48 8d 35 d4 99 fb ff 	lea    -0x4662c(%rip),%rsi        # 1009cc0 <core_number_pairs+0x2a20>
 10502ec:	eb 07                	jmp    10502f5 <my.json::write_value+0x2c5>
 10502ee:	48 8d 35 0b 9a fb ff 	lea    -0x465f5(%rip),%rsi        # 1009d00 <core_number_pairs+0x2a60>
 10502f5:	b9 04 00 00 00       	mov    $0x4,%ecx
 10502fa:	31 d2                	xor    %edx,%edx
 10502fc:	48 83 c4 18          	add    $0x18,%rsp
 1050300:	5b                   	pop    %rbx
 1050301:	41 5c                	pop    %r12
 1050303:	41 5d                	pop    %r13
 1050305:	41 5e                	pop    %r14
 1050307:	41 5f                	pop    %r15
 1050309:	5d                   	pop    %rbp
 105030a:	e9 71 c8 fe ff       	jmp    103cb80 <myl_core_buffer_append_checked>
 105030f:	48 8d 35 2a 9a fb ff 	lea    -0x465d6(%rip),%rsi        # 1009d40 <core_number_pairs+0x2aa0>
 1050316:	b9 05 00 00 00       	mov    $0x5,%ecx
 105031b:	eb dd                	jmp    10502fa <my.json::write_value+0x2ca>

Disassembly of section .plt:
