; asm_to_lang_sysv.asm
; Linux/WSL x86-64 SysV ABI variant (NASM, links with glibc via gcc -no-pie)
; Functionally mirrors asm_to_lang.asm: reads an input .asm, prints C-like translations.
; Supported patterns (subset):
;   label
;   mov/lea reg|[mem], src
;   add/sub/imul/mul reg|[mem], src
;   inc/dec/neg/not
;   push/pop/call/ret
;   cmp/test + conditional jumps je/jz/jne/jnz/jl/jg/jle/jge/ja/jae/jb/jbe, and jmp

default rel

extern printf
extern fopen
extern fgets
extern exit

global main

section .data
fmt_usage     db "Usage: asm_to_lang <input.asm>", 10, 0
fmt_open_fail db "Failed to open %s", 10, 0
fmt_label     db "%s:", 10, 0
fmt_assign    db "let %s = %s;", 10, 0
fmt_store     db "%s = %s;", 10, 0
fmt_add       db "%s = %s + %s;", 10, 0
fmt_sub       db "%s = %s - %s;", 10, 0
fmt_mul       db "%s = %s * %s;", 10, 0
fmt_neg       db "%s = -%s;", 10, 0
fmt_notb      db "%s = ~%s;", 10, 0
fmt_and       db "%s = %s & %s;", 10, 0
fmt_or        db "%s = %s | %s;", 10, 0
fmt_xor       db "%s = %s ^ %s;", 10, 0
fmt_shl       db "%s = %s << %s;", 10, 0
fmt_shr       db "%s = %s >> %s;", 10, 0
fmt_goto      db "goto %s;", 10, 0
fmt_call      db "call %s();", 10, 0
fmt_ret       db "return;", 10, 0
fmt_push      db "push %s;", 10, 0
fmt_pop       db "pop %s;", 10, 0
fmt_lea       db "let %s = &%s;", 10, 0
fmt_if_eq     db "if (%s == %s) goto %s;", 10, 0
fmt_if_ne     db "if (%s != %s) goto %s;", 10, 0
fmt_if_lt     db "if (%s < %s) goto %s;", 10, 0
fmt_if_gt     db "if (%s > %s) goto %s;", 10, 0
fmt_if_le     db "if (%s <= %s) goto %s;", 10, 0
fmt_if_ge     db "if (%s >= %s) goto %s;", 10, 0

str_one      db "1", 0

mode_read db "r", 0

op_mov db "mov", 0
op_lea db "lea", 0
op_add db "add", 0
op_sub db "sub", 0
op_inc db "inc", 0
op_dec db "dec", 0
op_neg db "neg", 0
op_not db "not", 0
op_imul db "imul", 0
op_and db "and", 0
op_or  db "or", 0
op_xor db "xor", 0
op_shl db "shl", 0
op_shr db "shr", 0
op_sar db "sar", 0
op_cmp db "cmp", 0
op_test db "test", 0
op_jmp db "jmp", 0
op_je  db "je", 0
op_jz  db "jz", 0
op_jne db "jne", 0
op_jnz db "jnz", 0
op_jl  db "jl", 0
op_jg  db "jg", 0
op_jle db "jle", 0
op_jge db "jge", 0
op_ja  db "ja", 0
op_jae db "jae", 0
op_jb  db "jb", 0
op_jbe db "jbe", 0
op_call db "call", 0
op_ret  db "ret", 0
op_push db "push", 0
op_pop  db "pop", 0

section .bss
linebuf   resb 1024
opbuf     resb 32
arg1buf   resb 64
arg2buf   resb 64
cmp_left  resb 64
cmp_right resb 64
tmpbuf    resb 128

section .text

; int main(int argc, char** argv)
main:
    push rbp
    mov rbp, rsp
    sub rsp, 8                ; align stack to 16 before calls (after push rbp)

    cmp edi, 2
    jl .usage

    mov rbx, rsi              ; argv
    mov rdi, [rbx+8]          ; filename
    lea rsi, [rel mode_read]
    call fopen
    test rax, rax
    jnz .opened

    lea rdi, [rel fmt_open_fail]
    mov rsi, [rbx+8]
    xor eax, eax
    call printf
    mov edi, 1
    call exit

.usage:
    lea rdi, [rel fmt_usage]
    xor esi, esi
    xor eax, eax
    call printf
    mov edi, 1
    call exit

.opened:
    mov r12, rax              ; FILE*

.read_loop:
    lea rdi, [rel linebuf]
    mov esi, 1024
    mov rdx, r12
    call fgets
    test rax, rax
    je .done
    lea rdi, [rel linebuf]
    call parse_line
    jmp .read_loop

.done:
    xor edi, edi
    call exit

; parse_line(char* line)
; Clobbers: rax, rdi, rsi, rdx, r8-r11; preserves rbx, r12-r15, rbp.
parse_line:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rbx
    sub rsp, 8                ; keep 16 alignment

    mov rsi, rdi              ; line pointer
    mov rdi, rsi
    call skip_ws
    mov rsi, rax
    mov al, [rsi]
    test al, al
    je .pl_done
    cmp al, ';'
    je .pl_done
    cmp al, '.'
    je .pl_done

    lea rbx, [rel opbuf]
.copy_token:
    mov al, [rsi]
    cmp al, 0
    je .finish_token
    cmp al, ':'
    je .label
    cmp al, ' '
    je .finish_token
    cmp al, 9
    je .finish_token
    cmp al, 0x0d
    je .finish_token
    cmp al, 0x0a
    je .finish_token
    mov [rbx], al
    inc rbx
    inc rsi
    jmp .copy_token

.finish_token:
    mov byte [rbx], 0
    jmp .after_token

.label:
    mov byte [rbx], 0
    lea rdi, [rel fmt_label]
    lea rsi, [rel opbuf]
    xor eax, eax
    call printf
    jmp .pl_done

.after_token:
    mov rdi, rsi
    call skip_ws
    mov rsi, rax

    mov byte [rel arg1buf], 0
    mov byte [rel arg2buf], 0

    mov al, [rsi]
    test al, al
    je .process_op

    mov rdi, rsi
    lea rsi, [rel arg1buf]
    call parse_operand
    mov rsi, rax
    mov rdi, rsi
    call skip_ws
    mov rsi, rax
    mov al, [rsi]
    cmp al, ','
    jne .process_op
    inc rsi
    mov rdi, rsi
    call skip_ws
    mov rsi, rax
    mov rdi, rsi
    lea rsi, [rel arg2buf]
    call parse_operand

    ; normalize memory
    lea rax, [rel arg1buf]
    mov dl, [rax]
    cmp dl, '['
    jne .check_arg2_mem
    mov rdi, rax
    call format_mem_inplace
.check_arg2_mem:
    lea rax, [rel arg2buf]
    mov dl, [rax]
    cmp dl, '['
    jne .process_op
    mov rdi, rax
    call format_mem_inplace

.process_op:
    ; ret
    lea rdi, [rel opbuf]
    lea rsi, [rel op_ret]
    call streq
    cmp eax, 1
    jne .check_call
    lea rdi, [rel fmt_ret]
    xor eax, eax
    call printf
    jmp .pl_done

.check_call:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_call]
    call streq
    cmp eax, 1
    jne .check_push
    lea rdi, [rel fmt_call]
    lea rsi, [rel arg1buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_push:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_push]
    call streq
    cmp eax, 1
    jne .check_pop
    lea rdi, [rel fmt_push]
    lea rsi, [rel arg1buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_pop:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_pop]
    call streq
    cmp eax, 1
    jne .check_lea
    lea rdi, [rel fmt_pop]
    lea rsi, [rel arg1buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_lea:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_lea]
    call streq
    cmp eax, 1
    jne .check_mov
    lea rdi, [rel fmt_lea]
    lea rsi, [rel arg1buf]
    lea rdx, [rel arg2buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_inc:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_inc]
    call streq
    cmp eax, 1
    jne .check_dec
    lea rdi, [rel fmt_add]
    lea rsi, [rel arg1buf]
    lea rdx, [rel arg1buf]
    lea rcx, [rel str_one]
    xor eax, eax
    call printf
    jmp .pl_done

.check_dec:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_dec]
    call streq
    cmp eax, 1
    jne .check_neg
    lea rdi, [rel fmt_sub]
    lea rsi, [rel arg1buf]
    lea rdx, [rel arg1buf]
    lea rcx, [rel str_one]
    xor eax, eax
    call printf
    jmp .pl_done

.check_neg:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_neg]
    call streq
    cmp eax, 1
    jne .check_not
    lea rdi, [rel fmt_neg]
    lea rsi, [rel arg1buf]
    lea rdx, [rel arg1buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_not:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_not]
    call streq
    cmp eax, 1
    jne .check_mov
    lea rdi, [rel fmt_notb]
    lea rsi, [rel arg1buf]
    lea rdx, [rel arg1buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_mov:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_mov]
    call streq
    cmp eax, 1
    jne .check_add
    lea rax, [rel arg1buf]
    mov dl, [rax]
    cmp dl, '*'
    jne .mov_reg
    lea rdi, [rel fmt_store]
    lea rsi, [rel arg1buf]
    lea rdx, [rel arg2buf]
    xor eax, eax
    call printf
    jmp .pl_done
.mov_reg:
    lea rdi, [rel fmt_assign]
    lea rsi, [rel arg1buf]
    lea rdx, [rel arg2buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_add:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_add]
    call streq
    cmp eax, 1
    jne .check_sub
    lea rdi, [rel fmt_add]
    lea rsi, [rel arg1buf]
    lea rdx, [rel arg1buf]
    lea rcx, [rel arg2buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_sub:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_sub]
    call streq
    cmp eax, 1
    jne .check_imul
    lea rdi, [rel fmt_sub]
    lea rsi, [rel arg1buf]
    lea rdx, [rel arg1buf]
    lea rcx, [rel arg2buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_imul:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_imul]
    call streq
    cmp eax, 1
    jne .check_and
    lea rdi, [rel fmt_mul]
    lea rsi, [rel arg1buf]
    lea rdx, [rel arg1buf]
    lea rcx, [rel arg2buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_and:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_and]
    call streq
    cmp eax, 1
    jne .check_or
    lea rdi, [rel fmt_and]
    lea rsi, [rel arg1buf]
    lea rdx, [rel arg1buf]
    lea rcx, [rel arg2buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_or:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_or]
    call streq
    cmp eax, 1
    jne .check_xor
    lea rdi, [rel fmt_or]
    lea rsi, [rel arg1buf]
    lea rdx, [rel arg1buf]
    lea rcx, [rel arg2buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_xor:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_xor]
    call streq
    cmp eax, 1
    jne .check_shl
    lea rdi, [rel fmt_xor]
    lea rsi, [rel arg1buf]
    lea rdx, [rel arg1buf]
    lea rcx, [rel arg2buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_shl:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_shl]
    call streq
    cmp eax, 1
    jne .check_shr
    lea rdi, [rel fmt_shl]
    lea rsi, [rel arg1buf]
    lea rdx, [rel arg1buf]
    lea rcx, [rel arg2buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_shr:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_shr]
    call streq
    cmp eax, 1
    jne .check_sar
    lea rdi, [rel fmt_shr]
    lea rsi, [rel arg1buf]
    lea rdx, [rel arg1buf]
    lea rcx, [rel arg2buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_sar:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_sar]
    call streq
    cmp eax, 1
    jne .check_cmp
    lea rdi, [rel fmt_shr]
    lea rsi, [rel arg1buf]
    lea rdx, [rel arg1buf]
    lea rcx, [rel arg2buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_cmp:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_cmp]
    call streq
    cmp eax, 1
    jne .check_test
    lea rdi, [rel cmp_left]
    lea rsi, [rel arg1buf]
    call copy_str
    lea rdi, [rel cmp_right]
    lea rsi, [rel arg2buf]
    call copy_str
    jmp .pl_done

.check_test:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_test]
    call streq
    cmp eax, 1
    jne .check_jmp
    lea rdi, [rel cmp_left]
    lea rsi, [rel arg1buf]
    call copy_str
    lea rdi, [rel cmp_right]
    lea rsi, [rel arg2buf]
    call copy_str
    jmp .pl_done

.check_jmp:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_jmp]
    call streq
    cmp eax, 1
    jne .check_je
    lea rdi, [rel fmt_goto]
    lea rsi, [rel arg1buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_je:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_je]
    call streq
    cmp eax, 1
    jne .check_jz
    lea rdi, [rel fmt_if_eq]
    lea rsi, [rel cmp_left]
    lea rdx, [rel cmp_right]
    lea rcx, [rel arg1buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_jz:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_jz]
    call streq
    cmp eax, 1
    jne .check_jne
    lea rdi, [rel fmt_if_eq]
    lea rsi, [rel cmp_left]
    lea rdx, [rel cmp_right]
    lea rcx, [rel arg1buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_jne:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_jne]
    call streq
    cmp eax, 1
    jne .check_jnz
    lea rdi, [rel fmt_if_ne]
    lea rsi, [rel cmp_left]
    lea rdx, [rel cmp_right]
    lea rcx, [rel arg1buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_jnz:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_jnz]
    call streq
    cmp eax, 1
    jne .check_jl
    lea rdi, [rel fmt_if_ne]
    lea rsi, [rel cmp_left]
    lea rdx, [rel cmp_right]
    lea rcx, [rel arg1buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_jl:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_jl]
    call streq
    cmp eax, 1
    jne .check_jg
    lea rdi, [rel fmt_if_lt]
    lea rsi, [rel cmp_left]
    lea rdx, [rel cmp_right]
    lea rcx, [rel arg1buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_jg:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_jg]
    call streq
    cmp eax, 1
    jne .check_jle
    lea rdi, [rel fmt_if_gt]
    lea rsi, [rel cmp_left]
    lea rdx, [rel cmp_right]
    lea rcx, [rel arg1buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_jle:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_jle]
    call streq
    cmp eax, 1
    jne .check_jge
    lea rdi, [rel fmt_if_le]
    lea rsi, [rel cmp_left]
    lea rdx, [rel cmp_right]
    lea rcx, [rel arg1buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_jge:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_jge]
    call streq
    cmp eax, 1
    jne .check_ja
    lea rdi, [rel fmt_if_ge]
    lea rsi, [rel cmp_left]
    lea rdx, [rel cmp_right]
    lea rcx, [rel arg1buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_ja:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_ja]
    call streq
    cmp eax, 1
    jne .check_jae
    lea rdi, [rel fmt_if_gt]
    lea rsi, [rel cmp_left]
    lea rdx, [rel cmp_right]
    lea rcx, [rel arg1buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_jae:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_jae]
    call streq
    cmp eax, 1
    jne .check_jb
    lea rdi, [rel fmt_if_ge]
    lea rsi, [rel cmp_left]
    lea rdx, [rel cmp_right]
    lea rcx, [rel arg1buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_jb:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_jb]
    call streq
    cmp eax, 1
    jne .check_jbe
    lea rdi, [rel fmt_if_lt]
    lea rsi, [rel cmp_left]
    lea rdx, [rel cmp_right]
    lea rcx, [rel arg1buf]
    xor eax, eax
    call printf
    jmp .pl_done

.check_jbe:
    lea rdi, [rel opbuf]
    lea rsi, [rel op_jbe]
    call streq
    cmp eax, 1
    jne .pl_done
    lea rdi, [rel fmt_if_le]
    lea rsi, [rel cmp_left]
    lea rdx, [rel cmp_right]
    lea rcx, [rel arg1buf]
    xor eax, eax
    call printf

.pl_done:
    add rsp, 8
    pop rbx
    pop rsi
    pop rdi
    pop rbp
    ret

; skip_ws(char* p) -> rax
skip_ws:
    mov rax, rdi
.sw_loop:
    mov dl, [rax]
    cmp dl, ' '
    je .sw_inc
    cmp dl, 9
    je .sw_inc
    cmp dl, 0x0d
    je .sw_inc
    cmp dl, 0x0a
    je .sw_inc
    ret
.sw_inc:
    inc rax
    jmp .sw_loop

; parse_operand(char* src, char* dest) -> rax points after token
parse_operand:
    mov rax, rdi
    mov r8, rsi
.po_loop:
    mov dl, [rax]
    cmp dl, 0
    je .po_done
    cmp dl, ','
    je .po_done
    cmp dl, ';'
    je .po_done
    cmp dl, ' '
    je .po_done
    cmp dl, 9
    je .po_done
    cmp dl, 0x0d
    je .po_done
    cmp dl, 0x0a
    je .po_done
    mov [r8], dl
    inc r8
    inc rax
    jmp .po_loop
.po_done:
    mov byte [r8], 0
    ret

; streq(a, b) -> eax = 1 if equal else 0
streq:
    mov r8, rdi
    mov r9, rsi
.se_loop:
    mov al, [r8]
    mov dl, [r9]
    cmp al, dl
    jne .se_ne
    test al, al
    je .se_eq
    inc r8
    inc r9
    jmp .se_loop
.se_eq:
    mov eax, 1
    ret
.se_ne:
    xor eax, eax
    ret

copy_str:
    mov r8, rdi
    mov r9, rsi
.cs_loop:
    mov al, [r9]
    mov [r8], al
    inc r8
    inc r9
    test al, al
    jne .cs_loop
    ret

; format_mem_inplace(buf): turns "[rbp-8]" into "*(rbp-8)"
format_mem_inplace:
    mov r8, rdi
    lea r9, [rel tmpbuf]
    mov byte [r9], '*'
    mov byte [r9+1], '('
    mov r10, 2
    inc r8
.fm_copy:
    mov al, [r8]
    test al, al
    je .fm_end
    cmp al, ']'
    je .fm_end
    cmp al, ' '
    je .fm_skip
    cmp al, 9
    je .fm_skip
    cmp al, 0x0d
    je .fm_skip
    cmp al, 0x0a
    je .fm_skip
    cmp al, '+'
    je .fm_op
    cmp al, '-'
    je .fm_op
    cmp al, '*'
    je .fm_op
    mov [r9+r10], al
    inc r10
    inc r8
    jmp .fm_copy
.fm_op:
    cmp r10, 0
    je .fm_writeop
    mov bl, [r9+r10-1]
    cmp bl, ' '
    je .fm_writeop
    mov byte [r9+r10], ' '
    inc r10
.fm_writeop:
    mov [r9+r10], al
    inc r10
    mov byte [r9+r10], ' '
    inc r10
    inc r8
    jmp .fm_copy
.fm_skip:
    inc r8
    jmp .fm_copy
.fm_end:
    mov byte [r9+r10], ')'
    inc r10
    mov byte [r9+r10], 0
    mov r8, rdi
    lea r9, [rel tmpbuf]
.fm_copyback:
    mov al, [r9]
    mov [r8], al
    inc r8
    inc r9
    test al, al
    jne .fm_copyback
    ret
