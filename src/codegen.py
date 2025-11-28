from __future__ import annotations

from typing import Dict, List, Set

from . import ast
from .typesys import TypeChecker


class X86Codegen:
    param_regs = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]

    def __init__(self, prog: ast.Program):
        self.prog = prog
        self.lines: List[str] = []
        self.string_labels: Dict[str, str] = {}
        self.label_counter = 0

    def compile(self) -> str:
        TypeChecker(self.prog).check()
        self._collect_strings()
        self._emit_preamble()
        for fn in self.prog.functions:
            self._emit_function(fn)
        return "\n".join(self.lines)

    def _collect_strings(self) -> None:
        for fn in self.prog.functions:
            self._collect_strings_block(fn.body)

    def _collect_strings_block(self, block: ast.Block) -> None:
        for stmt in block.statements:
            if isinstance(stmt, ast.LetStmt):
                self._collect_strings_expr(stmt.expr)
            elif isinstance(stmt, ast.AssignStmt):
                self._collect_strings_expr(stmt.expr)
            elif isinstance(stmt, ast.ExprStmt):
                self._collect_strings_expr(stmt.expr)
            elif isinstance(stmt, ast.ReturnStmt):
                if stmt.expr:
                    self._collect_strings_expr(stmt.expr)
            elif isinstance(stmt, ast.IfStmt):
                self._collect_strings_expr(stmt.cond)
                self._collect_strings_block(stmt.then_block)
                if stmt.else_block:
                    self._collect_strings_block(stmt.else_block)
            elif isinstance(stmt, ast.WhileStmt):
                self._collect_strings_expr(stmt.cond)
                self._collect_strings_block(stmt.body)

    def _collect_strings_expr(self, expr: ast.Expr) -> None:
        if isinstance(expr, ast.StringLiteral):
            if expr.value not in self.string_labels:
                label = f".Lstr{len(self.string_labels)}"
                self.string_labels[expr.value] = label
            expr.label = self.string_labels[expr.value]
        elif isinstance(expr, ast.BinaryOp):
            self._collect_strings_expr(expr.left)
            self._collect_strings_expr(expr.right)
        elif isinstance(expr, ast.UnaryOp):
            self._collect_strings_expr(expr.expr)
        elif isinstance(expr, ast.Call):
            for a in expr.args:
                self._collect_strings_expr(a)

    def _emit(self, line: str) -> None:
        self.lines.append(line)

    def _emit_preamble(self) -> None:
        self._emit(".intel_syntax noprefix")
        self._emit(".section .rodata")
        self._emit(".LC_fmt_int:")
        self._emit('    .asciz "%ld\\n"')
        for val, label in self.string_labels.items():
            escaped = val.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")
            self._emit(f"{label}:")
            self._emit(f'    .asciz "{escaped}"')
        self._emit(".text")
        self._emit(".globl main")
        self._emit("extern printf")
        self._emit("extern puts")

    def _emit_function(self, fn: ast.FunctionDef) -> None:
        self._emit(f"{fn.name}:")
        self._emit("    push rbp")
        self._emit("    mov rbp, rsp")
        env, frame_size = self._layout_frame(fn)
        if frame_size:
            self._emit(f"    sub rsp, {frame_size}")
        # store params
        for idx, param in enumerate(fn.params):
            if idx < len(self.param_regs):
                reg = self.param_regs[idx]
                off = env[param.name]
                self._emit(f"    mov [rbp-{off}], {reg}")
        for stmt in fn.body.statements:
            self._emit_stmt(stmt, env)
        # implicit return 0
        self._emit("    mov rax, 0")
        self._emit("    leave")
        self._emit("    ret")

    def _layout_frame(self, fn: ast.FunctionDef) -> (Dict[str, int], int):
        names: List[str] = []
        for p in fn.params:
            names.append(p.name)
        names.extend(self._collect_locals(fn.body))
        env: Dict[str, int] = {}
        offset = 0
        for name in names:
            if name in env:
                continue
            offset += 8
            env[name] = offset
        frame_size = ((offset + 15) // 16) * 16
        return env, frame_size

    def _collect_locals(self, block: ast.Block) -> List[str]:
        names: List[str] = []
        for stmt in block.statements:
            if isinstance(stmt, ast.LetStmt):
                names.append(stmt.name)
            elif isinstance(stmt, ast.IfStmt):
                names.extend(self._collect_locals(stmt.then_block))
                if stmt.else_block:
                    names.extend(self._collect_locals(stmt.else_block))
            elif isinstance(stmt, ast.WhileStmt):
                names.extend(self._collect_locals(stmt.body))
        return names

    def _emit_stmt(self, stmt: ast.Stmt, env: Dict[str, int]) -> None:
        if isinstance(stmt, ast.LetStmt):
            self._emit_expr(stmt.expr, env)
            off = env[stmt.name]
            self._emit(f"    mov [rbp-{off}], rax")
            return
        if isinstance(stmt, ast.AssignStmt):
            self._emit_expr(stmt.expr, env)
            off = env[stmt.name]
            self._emit(f"    mov [rbp-{off}], rax")
            return
        if isinstance(stmt, ast.ExprStmt):
            self._emit_expr(stmt.expr, env)
            return
        if isinstance(stmt, ast.ReturnStmt):
            if stmt.expr:
                self._emit_expr(stmt.expr, env)
            else:
                self._emit("    mov rax, 0")
            self._emit("    leave")
            self._emit("    ret")
            return
        if isinstance(stmt, ast.IfStmt):
            else_label = self._new_label("else")
            end_label = self._new_label("endif")
            self._emit_expr(stmt.cond, env)
            self._emit("    cmp rax, 0")
            self._emit(f"    je {else_label}")
            self._emit_block(stmt.then_block, env)
            self._emit(f"    jmp {end_label}")
            self._emit(f"{else_label}:")
            if stmt.else_block:
                self._emit_block(stmt.else_block, env)
            self._emit(f"{end_label}:")
            return
        if isinstance(stmt, ast.WhileStmt):
            start_label = self._new_label("while")
            end_label = self._new_label("endwhile")
            self._emit(f"{start_label}:")
            self._emit_expr(stmt.cond, env)
            self._emit("    cmp rax, 0")
            self._emit(f"    je {end_label}")
            self._emit_block(stmt.body, env)
            self._emit(f"    jmp {start_label}")
            self._emit(f"{end_label}:")
            return

    def _emit_block(self, block: ast.Block, env: Dict[str, int]) -> None:
        for stmt in block.statements:
            self._emit_stmt(stmt, env)

    def _emit_expr(self, expr: ast.Expr, env: Dict[str, int]) -> None:
        if isinstance(expr, ast.IntLiteral):
            self._emit(f"    mov rax, {expr.value}")
        elif isinstance(expr, ast.BoolLiteral):
            self._emit(f"    mov rax, {1 if expr.value else 0}")
        elif isinstance(expr, ast.StringLiteral):
            label = expr.label or self.string_labels.get(expr.value, "")
            self._emit(f"    lea rax, [rel {label}]")
        elif isinstance(expr, ast.VarRef):
            off = env[expr.name]
            self._emit(f"    mov rax, [rbp-{off}]")
        elif isinstance(expr, ast.UnaryOp):
            self._emit_expr(expr.expr, env)
            if expr.op == "-":
                self._emit("    neg rax")
            elif expr.op == "!":
                self._emit("    cmp rax, 0")
                self._emit("    sete al")
                self._emit("    movzx rax, al")
        elif isinstance(expr, ast.BinaryOp):
            if expr.op in {"&&", "||"}:
                self._emit_logical(expr, env)
            else:
                self._emit_expr(expr.left, env)
                self._emit("    push rax")
                self._emit_expr(expr.right, env)
                self._emit("    pop rbx")
                self._emit_binary(expr.op)
        elif isinstance(expr, ast.Call):
            self._emit_call(expr, env)
        else:
            raise ValueError(f"Unhandled expr {expr}")

    def _emit_binary(self, op: str) -> None:
        if op == "+":
            self._emit("    add rax, rbx")
        elif op == "-":
            self._emit("    sub rbx, rax")
            self._emit("    mov rax, rbx")
        elif op == "*":
            self._emit("    imul rax, rbx")
        elif op == "/":
            self._emit("    mov rdx, 0")
            self._emit("    mov rcx, rax")
            self._emit("    mov rax, rbx")
            self._emit("    idiv rcx")
        elif op in {"==", "!=", "<", ">", "<=", ">="}:
            self._emit("    cmp rbx, rax")
            set_instr = {
                "==": "sete",
                "!=": "setne",
                "<": "setl",
                "<=": "setle",
                ">": "setg",
                ">=": "setge",
            }[op]
            self._emit(f"    {set_instr} al")
            self._emit("    movzx rax, al")
        else:
            raise ValueError(f"Unknown binary op {op}")

    def _emit_logical(self, expr: ast.BinaryOp, env: Dict[str, int]) -> None:
        end = self._new_label("logic_end")
        short = self._new_label("logic_short")
        if expr.op == "&&":
            self._emit_expr(expr.left, env)
            self._emit("    cmp rax, 0")
            self._emit(f"    je {short}")
            self._emit_expr(expr.right, env)
            self._emit("    cmp rax, 0")
            self._emit("    setne al")
            self._emit("    movzx rax, al")
            self._emit(f"    jmp {end}")
            self._emit(f"{short}:")
            self._emit("    mov rax, 0")
        else:  # ||
            self._emit_expr(expr.left, env)
            self._emit("    cmp rax, 0")
            self._emit(f"    jne {short}")
            self._emit_expr(expr.right, env)
            self._emit("    cmp rax, 0")
            self._emit("    setne al")
            self._emit("    movzx rax, al")
            self._emit(f"    jmp {end}")
            self._emit(f"{short}:")
            self._emit("    mov rax, 1")
        self._emit(f"{end}:")

    def _emit_call(self, call: ast.Call, env: Dict[str, int]) -> None:
        if call.callee == "print":
            arg = call.args[0]
            self._emit_expr(arg, env)
            if getattr(arg, "inferred_type", None) == "string":
                self._emit("    mov rdi, rax")
                self._emit("    call puts")
                self._emit("    mov rax, 0")
            else:
                self._emit("    mov rsi, rax")
                self._emit("    lea rdi, [rel .LC_fmt_int]")
                self._emit("    xor eax, eax")
                self._emit("    call printf")
                self._emit("    mov rax, 0")
            return

        for idx, arg in enumerate(call.args):
            self._emit_expr(arg, env)
            if idx < len(self.param_regs):
                reg = self.param_regs[idx]
                self._emit(f"    mov {reg}, rax")
        self._emit(f"    call {call.callee}")

    def _new_label(self, prefix: str) -> str:
        lbl = f".L{prefix}{self.label_counter}"
        self.label_counter += 1
        return lbl


def generate_x86_64(prog: ast.Program) -> str:
    return X86Codegen(prog).compile()
