dump:
sub rsp, 40
mov r10, rdi
mov QWORD  [rsp], 0
mov QWORD  [rsp+8], 0
mov QWORD  [rsp+16], 0
mov QWORD  [rsp+24], 0
mov BYTE  [rsp+31], 10
mov rcx, rdi
mov esi, 1
mov r9, 7378697629483820647
.L2:
mov rdi, rsi
add rsi, 1
mov r8, rdi
not r8
mov rax, rcx
imul r9
sar rdx, 2
mov rax, rcx
sar rax, 63
sub rdx, rax
lea rax, [rdx+rdx*4]
add rax, rax
sub rcx, rax
mov eax, ecx
neg eax
mov eax, ecx
add eax, 48
mov BYTE  [rsp+32+r8], al
mov rcx, rdx
test rdx, rdx
jne .L2
test r10, r10
js   .L6
.L3:
mov eax, 32
sub rax, rsi
lea rax, [rsp+rax]
mov rdx, rsi
mov rsi, rax
mov edi, 1
mov rax, 1
syscall
add rsp, 40
ret
.L6:
not rsi
mov BYTE [rsp+32+rsi], 45
lea rsi, [rdi+2]
jmp .L3
