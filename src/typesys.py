from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

from . import ast
from .errors import TypeError


TypeName = str


@dataclass
class FunctionSig:
    params: List[TypeName]
    ret: TypeName


BUILTINS: Dict[str, List[FunctionSig]] = {
    "print": [
        FunctionSig(["int"], "void"),
        FunctionSig(["string"], "void"),
    ]
}


class TypeChecker:
    def __init__(self, prog: ast.Program):
        self.prog = prog
        self.funcs: Dict[str, FunctionSig] = {}

    def check(self) -> None:
        self._collect_functions()
        for fn in self.prog.functions:
            self._check_function(fn)

    def _collect_functions(self) -> None:
        for fn in self.prog.functions:
            ret = fn.return_type or "void"
            params: List[TypeName] = []
            for p in fn.params:
                if not p.type_name:
                    raise TypeError(f"Parameter '{p.name}' in {fn.name} must have a type")
                params.append(normalize_type(p.type_name))
            self.funcs[fn.name] = FunctionSig(params, normalize_type(ret))

    def _check_function(self, fn: ast.FunctionDef) -> None:
        scope: Dict[str, TypeName] = {}
        for p in fn.params:
            scope[p.name] = normalize_type(p.type_name or "void")
        ret_type = normalize_type(fn.return_type or "void")
        self._check_block(fn.body, scope, ret_type)

    def _check_block(self, block: ast.Block, scope: Dict[str, TypeName], ret_type: TypeName) -> None:
        for stmt in block.statements:
            self._check_stmt(stmt, scope, ret_type)

    def _check_stmt(self, stmt: ast.Stmt, scope: Dict[str, TypeName], ret_type: TypeName) -> None:
        if isinstance(stmt, ast.LetStmt):
            expr_type = self._check_expr(stmt.expr, scope)
            if stmt.type_name:
                declared = normalize_type(stmt.type_name)
                if declared != expr_type:
                    raise TypeError(f"Type mismatch in let {stmt.name}: {declared} vs {expr_type}")
                scope[stmt.name] = declared
            else:
                scope[stmt.name] = expr_type
            return
        if isinstance(stmt, ast.AssignStmt):
            if stmt.name not in scope:
                raise TypeError(f"Unknown variable {stmt.name}")
            expr_type = self._check_expr(stmt.expr, scope)
            if scope[stmt.name] != expr_type:
                raise TypeError(f"Type mismatch in assignment to {stmt.name}")
            return
        if isinstance(stmt, ast.IfStmt):
            cond_type = self._check_expr(stmt.cond, scope)
            if cond_type != "bool":
                raise TypeError("If condition must be bool")
            then_scope = scope.copy()
            self._check_block(stmt.then_block, then_scope, ret_type)
            if stmt.else_block:
                else_scope = scope.copy()
                self._check_block(stmt.else_block, else_scope, ret_type)
            return
        if isinstance(stmt, ast.WhileStmt):
            cond_type = self._check_expr(stmt.cond, scope)
            if cond_type != "bool":
                raise TypeError("While condition must be bool")
            body_scope = scope.copy()
            self._check_block(stmt.body, body_scope, ret_type)
            return
        if isinstance(stmt, ast.ReturnStmt):
            if ret_type == "void":
                if stmt.expr is not None:
                    raise TypeError("Void function cannot return a value")
            else:
                if stmt.expr is None:
                    raise TypeError("Non-void function must return a value")
                expr_type = self._check_expr(stmt.expr, scope)
                if expr_type != ret_type:
                    raise TypeError(f"Return type mismatch: expected {ret_type}, got {expr_type}")
            return
        if isinstance(stmt, ast.ExprStmt):
            self._check_expr(stmt.expr, scope)
            return
        raise TypeError(f"Unhandled statement {stmt}")

    def _check_expr(self, expr: ast.Expr, scope: Dict[str, TypeName]) -> TypeName:
        if isinstance(expr, ast.IntLiteral):
            expr.inferred_type = "int"
            return "int"
        if isinstance(expr, ast.BoolLiteral):
            expr.inferred_type = "bool"
            return "bool"
        if isinstance(expr, ast.StringLiteral):
            expr.inferred_type = "string"
            return "string"
        if isinstance(expr, ast.VarRef):
            if expr.name not in scope:
                raise TypeError(f"Unknown variable {expr.name}")
            expr.inferred_type = scope[expr.name]
            return expr.inferred_type
        if isinstance(expr, ast.UnaryOp):
            inner = self._check_expr(expr.expr, scope)
            if expr.op == "-":
                if inner != "int":
                    raise TypeError("Unary - expects int")
                expr.inferred_type = "int"
                return "int"
            if expr.op == "!":
                if inner != "bool":
                    raise TypeError("Unary ! expects bool")
                expr.inferred_type = "bool"
                return "bool"
        if isinstance(expr, ast.BinaryOp):
            left = self._check_expr(expr.left, scope)
            right = self._check_expr(expr.right, scope)
            if expr.op in {"+", "-", "*", "/"}:
                if left != "int" or right != "int":
                    raise TypeError("Arithmetic expects ints")
                expr.inferred_type = "int"
                return "int"
            if expr.op in {"<", ">", "<=", ">="}:
                if left != "int" or right != "int":
                    raise TypeError("Comparison expects ints")
                expr.inferred_type = "bool"
                return "bool"
            if expr.op in {"==", "!="}:
                if left != right:
                    raise TypeError("Equality operands must match")
                expr.inferred_type = "bool"
                return "bool"
            if expr.op in {"&&", "||"}:
                if left != "bool" or right != "bool":
                    raise TypeError("Logical ops expect bool")
                expr.inferred_type = "bool"
                return "bool"
        if isinstance(expr, ast.Call):
            sig = self._resolve_func(expr.callee, len(expr.args))
            for arg_expr, expected in zip(expr.args, sig.params):
                got = self._check_expr(arg_expr, scope)
                if got != expected:
                    raise TypeError(f"Arg type mismatch in call to {expr.callee}")
            expr.inferred_type = sig.ret
            return sig.ret
        raise TypeError(f"Unhandled expression {expr}")

    def _resolve_func(self, name: str, argc: int) -> FunctionSig:
        if name in BUILTINS:
            for sig in BUILTINS[name]:
                if len(sig.params) == argc:
                    return sig
        if name in self.funcs:
            sig = self.funcs[name]
            if len(sig.params) != argc:
                raise TypeError(f"Arity mismatch for {name}")
            return sig
        raise TypeError(f"Unknown function {name}")


def normalize_type(name: str) -> TypeName:
    lowered = name.lower()
    if lowered in ("int", "bool", "string", "void"):
        return lowered
    return lowered
