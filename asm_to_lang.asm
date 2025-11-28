; asm_to_lang.asm
; Minimal translator from a small subset of x86-64 assembly to a C-like high-level form.
; Target: Windows x64 (Microsoft ABI), NASM syntax. Links against msvcrt for stdio.
; Supported patterns (subset):
;   label:                     -> "label:"
;   mov/lea reg|[mem], src     -> "let dst = src;" or "[mem] = src;"
;   add/sub reg|[mem], src     -> "dst = dst +/- src;"
;   push/pop/call/ret          -> rendered as is (call emits "()")
;   cmp/test a, b              -> remembers operands for following conditional jumps
;   jmp label                  -> "goto label;"
;   je/jz/jne/jnz/jl/jg/jle/jge/ja/jae/jb/jbe label -> "if (a <op> b) goto label;"
; Unhandled lines are ignored.

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

mode_read db "r", 0

op_mov db "mov", 0
op_lea db "lea", 0
op_add db "add", 0
op_sub db "sub", 0
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

section .text

; int main(int argc, char** argv)
main:
    push rbp
    mov rbp, rsp
    sub rsp, 48                ; 32 bytes shadow space + 16 bytes locals, keep 16-byte alignment

    cmp ecx, 2                 ; argc < 2?
    jl .usage

    mov rax, rdx               ; argv
    mov [rbp-16], rax          ; save argv for error paths
    mov rcx, [rax+8]           ; argv[1] filename
    lea rdx, [rel mode_read]
    call fopen
    test rax, rax
    jnz .opened

    ; fopen failed
    lea rcx, [rel fmt_open_fail]
    mov rdx, [rbp-16]
    mov rdx, [rdx+8]
    call printf
    mov ecx, 1
    call exit

.usage:
    lea rcx, [rel fmt_usage]
    xor rdx, rdx
    call printf
    mov ecx, 1
    call exit

.opened:
    mov [rbp-8], rax           ; stash FILE*

.read_loop:
    lea rcx, [rel linebuf]
    mov edx, 1024
    mov r8, [rbp-8]
    call fgets
    test rax, rax
    je .done
    lea rcx, [rel linebuf]
    call parse_line
    jmp .read_loop

.done:
    xor ecx, ecx
    call exit

; parse_line(char* line)
; Clobbers: rax, rcx, rdx, r8-r11, preserves rbx/rsi/rdi.
parse_line:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rbx
    sub rsp, 40                ; 32 shadow + 8 for alignment

    mov rsi, rcx               ; line pointer
    mov rcx, rsi
    call skip_ws
    mov rsi, rax
    mov al, [rsi]
    test al, al
    je .pl_done
    cmp al, ';'
    je .pl_done
    cmp al, '.'
    je .pl_done

    ; parse op / label
    lea rdi, [rel opbuf]
    mov rbx, rsi
.copy_token:
    mov al, [rbx]
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
    mov [rdi], al
    inc rdi
    inc rbx
    jmp .copy_token

.finish_token:
    mov byte [rdi], 0
    jmp .after_token

.label:
    mov byte [rdi], 0
    lea rcx, [rel fmt_label]
    lea rdx, [rel opbuf]
    xor r8d, r8d
    xor r9d, r9d
    call printf
    jmp .pl_done

.after_token:
    mov rcx, rbx
    call skip_ws
    mov rsi, rax

    mov byte [rel arg1buf], 0
    mov byte [rel arg2buf], 0

    mov al, [rsi]
    test al, al
    je .process_op

    ; arg1
    mov rcx, rsi
    lea rdx, [rel arg1buf]
    call parse_operand
    mov rsi, rax
    mov rcx, rsi
    call skip_ws
    mov rsi, rax
    mov al, [rsi]
    cmp al, ','
    jne .process_op
    inc rsi
    mov rcx, rsi
    call skip_ws
    mov rsi, rax
    mov rcx, rsi
    lea rdx, [rel arg2buf]
    call parse_operand

.process_op:
    ; ret
    lea rcx, [rel opbuf]
    lea rdx, [rel op_ret]
    call streq
    cmp eax, 1
    jne .check_call
    lea rcx, [rel fmt_ret]
    xor rdx, rdx
    xor r8d, r8d
    xor r9d, r9d
    call printf
    jmp .pl_done

.check_call:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_call]
    call streq
    cmp eax, 1
    jne .check_push
    lea rcx, [rel fmt_call]
    lea rdx, [rel arg1buf]
    xor r8d, r8d
    xor r9d, r9d
    call printf
    jmp .pl_done

.check_push:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_push]
    call streq
    cmp eax, 1
    jne .check_pop
    lea rcx, [rel fmt_push]
    lea rdx, [rel arg1buf]
    xor r8d, r8d
    xor r9d, r9d
    call printf
    jmp .pl_done

.check_pop:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_pop]
    call streq
    cmp eax, 1
    jne .check_lea
    lea rcx, [rel fmt_pop]
    lea rdx, [rel arg1buf]
    xor r8d, r8d
    xor r9d, r9d
    call printf
    jmp .pl_done

.check_lea:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_lea]
    call streq
    cmp eax, 1
    jne .check_mov
    lea rcx, [rel fmt_lea]
    lea rdx, [rel arg1buf]
    lea r8,  [rel arg2buf]
    xor r9d, r9d
    call printf
    jmp .pl_done

.check_mov:
    ; mov
    lea rcx, [rel opbuf]
    lea rdx, [rel op_mov]
    call streq
    cmp eax, 1
    jne .check_add
    lea rax, [rel arg1buf]
    mov dl, [rax]
    cmp dl, '['
    jne .mov_reg
    lea rcx, [rel fmt_store]
    lea rdx, [rel arg1buf]
    lea r8,  [rel arg2buf]
    xor r9d, r9d
    call printf
    jmp .pl_done
.mov_reg:
    lea rcx, [rel fmt_assign]
    lea rdx, [rel arg1buf]
    lea r8,  [rel arg2buf]
    xor r9d, r9d
    call printf
    jmp .pl_done

.check_add:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_add]
    call streq
    cmp eax, 1
    jne .check_sub
    lea rcx, [rel fmt_add]
    lea rdx, [rel arg1buf]
    lea r8,  [rel arg1buf]
    lea r9,  [rel arg2buf]
    call printf
    jmp .pl_done

.check_sub:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_sub]
    call streq
    cmp eax, 1
    jne .check_imul
    lea rcx, [rel fmt_sub]
    lea rdx, [rel arg1buf]
    lea r8,  [rel arg1buf]
    lea r9,  [rel arg2buf]
    call printf
    jmp .pl_done

.check_imul:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_imul]
    call streq
    cmp eax, 1
    jne .check_and
    lea rcx, [rel fmt_mul]
    lea rdx, [rel arg1buf]
    lea r8,  [rel arg1buf]
    lea r9,  [rel arg2buf]
    call printf
    jmp .pl_done

.check_and:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_and]
    call streq
    cmp eax, 1
    jne .check_or
    lea rcx, [rel fmt_and]
    lea rdx, [rel arg1buf]
    lea r8,  [rel arg1buf]
    lea r9,  [rel arg2buf]
    call printf
    jmp .pl_done

.check_or:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_or]
    call streq
    cmp eax, 1
    jne .check_xor
    lea rcx, [rel fmt_or]
    lea rdx, [rel arg1buf]
    lea r8,  [rel arg1buf]
    lea r9,  [rel arg2buf]
    call printf
    jmp .pl_done

.check_xor:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_xor]
    call streq
    cmp eax, 1
    jne .check_shl
    lea rcx, [rel fmt_xor]
    lea rdx, [rel arg1buf]
    lea r8,  [rel arg1buf]
    lea r9,  [rel arg2buf]
    call printf
    jmp .pl_done

.check_shl:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_shl]
    call streq
    cmp eax, 1
    jne .check_shr
    lea rcx, [rel fmt_shl]
    lea rdx, [rel arg1buf]
    lea r8,  [rel arg1buf]
    lea r9,  [rel arg2buf]
    call printf
    jmp .pl_done

.check_shr:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_shr]
    call streq
    cmp eax, 1
    jne .check_sar
    lea rcx, [rel fmt_shr]
    lea rdx, [rel arg1buf]
    lea r8,  [rel arg1buf]
    lea r9,  [rel arg2buf]
    call printf
    jmp .pl_done

.check_sar:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_sar]
    call streq
    cmp eax, 1
    jne .check_cmp
    lea rcx, [rel fmt_shr]
    lea rdx, [rel arg1buf]
    lea r8,  [rel arg1buf]
    lea r9,  [rel arg2buf]
    call printf
    jmp .pl_done

.check_cmp:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_cmp]
    call streq
    cmp eax, 1
    jne .check_test
    lea rcx, [rel cmp_left]
    lea rdx, [rel arg1buf]
    call copy_str
    lea rcx, [rel cmp_right]
    lea rdx, [rel arg2buf]
    call copy_str
    jmp .pl_done

.check_test:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_test]
    call streq
    cmp eax, 1
    jne .check_jmp
    lea rcx, [rel cmp_left]
    lea rdx, [rel arg1buf]
    call copy_str
    lea rcx, [rel cmp_right]
    lea rdx, [rel arg2buf]
    call copy_str
    jmp .pl_done

.check_jmp:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_jmp]
    call streq
    cmp eax, 1
    jne .check_je
    lea rcx, [rel fmt_goto]
    lea rdx, [rel arg1buf]
    xor r8d, r8d
    xor r9d, r9d
    call printf
    jmp .pl_done

.check_je:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_je]
    call streq
    cmp eax, 1
    jne .check_jz
    lea rcx, [rel fmt_if_eq]
    lea rdx, [rel cmp_left]
    lea r8,  [rel cmp_right]
    lea r9,  [rel arg1buf]
    call printf
    jmp .pl_done

.check_jz:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_jz]
    call streq
    cmp eax, 1
    jne .check_jne
    lea rcx, [rel fmt_if_eq]
    lea rdx, [rel cmp_left]
    lea r8,  [rel cmp_right]
    lea r9,  [rel arg1buf]
    call printf
    jmp .pl_done

.check_jne:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_jne]
    call streq
    cmp eax, 1
    jne .check_jnz
    lea rcx, [rel fmt_if_ne]
    lea rdx, [rel cmp_left]
    lea r8,  [rel cmp_right]
    lea r9,  [rel arg1buf]
    call printf
    jmp .pl_done

.check_jnz:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_jnz]
    call streq
    cmp eax, 1
    jne .check_jl
    lea rcx, [rel fmt_if_ne]
    lea rdx, [rel cmp_left]
    lea r8,  [rel cmp_right]
    lea r9,  [rel arg1buf]
    call printf
    jmp .pl_done

.check_jl:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_jl]
    call streq
    cmp eax, 1
    jne .check_jg
    lea rcx, [rel fmt_if_lt]
    lea rdx, [rel cmp_left]
    lea r8,  [rel cmp_right]
    lea r9,  [rel arg1buf]
    call printf
    jmp .pl_done

.check_jg:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_jg]
    call streq
    cmp eax, 1
    jne .check_jle
    lea rcx, [rel fmt_if_gt]
    lea rdx, [rel cmp_left]
    lea r8,  [rel cmp_right]
    lea r9,  [rel arg1buf]
    call printf
    jmp .pl_done

.check_jle:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_jle]
    call streq
    cmp eax, 1
    jne .check_jge
    lea rcx, [rel fmt_if_le]
    lea rdx, [rel cmp_left]
    lea r8,  [rel cmp_right]
    lea r9,  [rel arg1buf]
    call printf
    jmp .pl_done

.check_jge:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_jge]
    call streq
    cmp eax, 1
    jne .check_ja
    lea rcx, [rel fmt_if_ge]
    lea rdx, [rel cmp_left]
    lea r8,  [rel cmp_right]
    lea r9,  [rel arg1buf]
    call printf
    jmp .pl_done

.check_ja:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_ja]
    call streq
    cmp eax, 1
    jne .check_jae
    lea rcx, [rel fmt_if_gt]
    lea rdx, [rel cmp_left]
    lea r8,  [rel cmp_right]
    lea r9,  [rel arg1buf]
    call printf
    jmp .pl_done

.check_jae:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_jae]
    call streq
    cmp eax, 1
    jne .check_jb
    lea rcx, [rel fmt_if_ge]
    lea rdx, [rel cmp_left]
    lea r8,  [rel cmp_right]
    lea r9,  [rel arg1buf]
    call printf
    jmp .pl_done

.check_jb:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_jb]
    call streq
    cmp eax, 1
    jne .check_jbe
    lea rcx, [rel fmt_if_lt]
    lea rdx, [rel cmp_left]
    lea r8,  [rel cmp_right]
    lea r9,  [rel arg1buf]
    call printf
    jmp .pl_done

.check_jbe:
    lea rcx, [rel opbuf]
    lea rdx, [rel op_jbe]
    call streq
    cmp eax, 1
    jne .pl_done
    lea rcx, [rel fmt_if_le]
    lea rdx, [rel cmp_left]
    lea r8,  [rel cmp_right]
    lea r9,  [rel arg1buf]
    call printf

.pl_done:
    add rsp, 40
    pop rbx
    pop rsi
    pop rdi
    pop rbp
    ret

; skip_ws(char* p) -> returns first non-space pointer in rax
skip_ws:
    mov rax, rcx
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

; parse_operand(char* src, char* dest) -> returns pointer after token in rax
parse_operand:
    mov rax, rcx       ; src
    mov r8, rdx        ; dest
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

; streq(const char* a, const char* b) -> eax = 1 if equal else 0
streq:
    mov r8, rcx
    mov r9, rdx
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

; copy_str(dest, src)
copy_str:
    mov r8, rcx
    mov r9, rdx
.cs_loop:
    mov al, [r9]
    mov [r8], al
    inc r8
    inc r9
    test al, al
    jne .cs_loop
    ret
