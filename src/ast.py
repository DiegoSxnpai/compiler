from __future__ import annotations

from dataclasses import dataclass
from typing import List, Optional


@dataclass
class Program:
    functions: List["FunctionDef"]


@dataclass
class FunctionDef:
    name: str
    params: List["Param"]
    return_type: Optional[str]
    body: "Block"


@dataclass
class Param:
    name: str
    type_name: Optional[str]


@dataclass
class Block:
    statements: List["Stmt"]


class Stmt:
    pass


@dataclass
class LetStmt(Stmt):
    name: str
    type_name: Optional[str]
    expr: "Expr"


@dataclass
class AssignStmt(Stmt):
    name: str
    expr: "Expr"


@dataclass
class IfStmt(Stmt):
    cond: "Expr"
    then_block: Block
    else_block: Optional[Block]


@dataclass
class WhileStmt(Stmt):
    cond: "Expr"
    body: Block


@dataclass
class ReturnStmt(Stmt):
    expr: Optional["Expr"]


@dataclass
class ExprStmt(Stmt):
    expr: "Expr"


class Expr:
    pass


@dataclass
class IntLiteral(Expr):
    value: int


@dataclass
class BoolLiteral(Expr):
    value: bool


@dataclass
class StringLiteral(Expr):
    value: str
    label: Optional[str] = None  # assigned during codegen


@dataclass
class VarRef(Expr):
    name: str


@dataclass
class UnaryOp(Expr):
    op: str
    expr: Expr


@dataclass
class BinaryOp(Expr):
    left: Expr
    op: str
    right: Expr


@dataclass
class Call(Expr):
    callee: str
    args: List[Expr]
