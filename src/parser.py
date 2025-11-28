from __future__ import annotations

from typing import List, Optional

from . import ast
from .errors import ParseError
from .tokens import Token


class Parser:
    def __init__(self, tokens: List[Token]):
        self.tokens = tokens
        self.pos = 0

    def current(self) -> Token:
        return self.tokens[self.pos]

    def consume(self, type_: str, msg: str) -> Token:
        if self.current().type == type_:
            tok = self.current()
            self.pos += 1
            return tok
        raise ParseError(msg + f" (found {self.current().type} at line {self.current().line})")

    def match(self, *types: str) -> Optional[Token]:
        if self.current().type in types:
            tok = self.current()
            self.pos += 1
            return tok
        return None

    def parse(self) -> ast.Program:
        funcs: List[ast.FunctionDef] = []
        while self.current().type != "EOF":
            funcs.append(self.parse_function())
        return ast.Program(funcs)

    def parse_function(self) -> ast.FunctionDef:
        self.consume("FN", "Expected 'fn'")
        name_tok = self.consume("IDENT", "Expected function name")
        self.consume("LPAREN", "Expected '('")
        params = []
        if self.current().type != "RPAREN":
            params.append(self.parse_param())
            while self.match("COMMA"):
                params.append(self.parse_param())
        self.consume("RPAREN", "Expected ')'")
        ret_type = None
        if self.match("->"):
            ret_type = self.parse_type()
        body = self.parse_block()
        return ast.FunctionDef(name_tok.value, params, ret_type, body)

    def parse_param(self) -> ast.Param:
        name_tok = self.consume("IDENT", "Expected parameter name")
        type_name = None
        if self.match("COLON"):
            type_name = self.parse_type()
        return ast.Param(name_tok.value, type_name)

    def parse_type(self) -> str:
        tok = self.current()
        if tok.type in ("IDENT", "INT", "BOOL", "STRING", "VOID"):
            self.pos += 1
            return tok.value if tok.value else tok.type.lower()
        raise ParseError(f"Expected type at line {tok.line}")

    def parse_block(self) -> ast.Block:
        self.consume("LBRACE", "Expected '{'")
        statements: List[ast.Stmt] = []
        while self.current().type != "RBRACE":
            statements.append(self.parse_statement())
        self.consume("RBRACE", "Expected '}'")
        return ast.Block(statements)

    def parse_statement(self) -> ast.Stmt:
        tok = self.current()
        if tok.type == "LET":
            return self.parse_let()
        if tok.type == "IF":
            return self.parse_if()
        if tok.type == "WHILE":
            return self.parse_while()
        if tok.type == "RETURN":
            return self.parse_return()
        # assignment lookahead
        if tok.type == "IDENT" and self.tokens[self.pos + 1].type == "ASSIGN":
            name = tok.value
            self.pos += 2  # consume ident and '='
            expr = self.parse_expression()
            self.consume("SEMICOLON", "Expected ';'")
            return ast.AssignStmt(name, expr)
        expr = self.parse_expression()
        self.consume("SEMICOLON", "Expected ';'")
        return ast.ExprStmt(expr)

    def parse_let(self) -> ast.Stmt:
        self.consume("LET", "Expected 'let'")
        name_tok = self.consume("IDENT", "Expected identifier after 'let'")
        type_name = None
        if self.match("COLON"):
            type_name = self.parse_type()
        self.consume("ASSIGN", "Expected '=' in let binding")
        expr = self.parse_expression()
        self.consume("SEMICOLON", "Expected ';'")
        return ast.LetStmt(name_tok.value, type_name, expr)

    def parse_if(self) -> ast.Stmt:
        self.consume("IF", "Expected 'if'")
        self.consume("LPAREN", "Expected '(' after if")
        cond = self.parse_expression()
        self.consume("RPAREN", "Expected ')' after condition")
        then_block = self.parse_block()
        else_block = None
        if self.match("ELSE"):
            else_block = self.parse_block()
        return ast.IfStmt(cond, then_block, else_block)

    def parse_while(self) -> ast.Stmt:
        self.consume("WHILE", "Expected 'while'")
        self.consume("LPAREN", "Expected '(' after while")
        cond = self.parse_expression()
        self.consume("RPAREN", "Expected ')' after condition")
        body = self.parse_block()
        return ast.WhileStmt(cond, body)

    def parse_return(self) -> ast.Stmt:
        self.consume("RETURN", "Expected 'return'")
        if self.current().type == "SEMICOLON":
            self.consume("SEMICOLON", "Expected ';'")
            return ast.ReturnStmt(None)
        expr = self.parse_expression()
        self.consume("SEMICOLON", "Expected ';'")
        return ast.ReturnStmt(expr)

    def parse_expression(self) -> ast.Expr:
        return self.parse_logical_or()

    def parse_logical_or(self) -> ast.Expr:
        expr = self.parse_logical_and()
        while self.match("||"):
            right = self.parse_logical_and()
            expr = ast.BinaryOp(expr, "||", right)
        return expr

    def parse_logical_and(self) -> ast.Expr:
        expr = self.parse_equality()
        while self.match("&&"):
            right = self.parse_equality()
            expr = ast.BinaryOp(expr, "&&", right)
        return expr

    def parse_equality(self) -> ast.Expr:
        expr = self.parse_comparison()
        while True:
            if self.match("=="):
                right = self.parse_comparison()
                expr = ast.BinaryOp(expr, "==", right)
            elif self.match("!="):
                right = self.parse_comparison()
                expr = ast.BinaryOp(expr, "!=", right)
            else:
                break
        return expr

    def parse_comparison(self) -> ast.Expr:
        expr = self.parse_term()
        while True:
            if self.match("LT"):
                right = self.parse_term()
                expr = ast.BinaryOp(expr, "<", right)
            elif self.match("GT"):
                right = self.parse_term()
                expr = ast.BinaryOp(expr, ">", right)
            elif self.match("<="):
                right = self.parse_term()
                expr = ast.BinaryOp(expr, "<=", right)
            elif self.match(">="):
                right = self.parse_term()
                expr = ast.BinaryOp(expr, ">=", right)
            else:
                break
        return expr

    def parse_term(self) -> ast.Expr:
        expr = self.parse_factor()
        while True:
            if self.match("PLUS"):
                right = self.parse_factor()
                expr = ast.BinaryOp(expr, "+", right)
            elif self.match("MINUS"):
                right = self.parse_factor()
                expr = ast.BinaryOp(expr, "-", right)
            else:
                break
        return expr

    def parse_factor(self) -> ast.Expr:
        expr = self.parse_unary()
        while True:
            if self.match("STAR"):
                right = self.parse_unary()
                expr = ast.BinaryOp(expr, "*", right)
            elif self.match("SLASH"):
                right = self.parse_unary()
                expr = ast.BinaryOp(expr, "/", right)
            else:
                break
        return expr

    def parse_unary(self) -> ast.Expr:
        if self.match("MINUS"):
            return ast.UnaryOp("-", self.parse_unary())
        if self.match("BANG"):
            return ast.UnaryOp("!", self.parse_unary())
        return self.parse_call()

    def parse_call(self) -> ast.Expr:
        expr = self.parse_primary()
        while self.match("LPAREN"):
            args = []
            if self.current().type != "RPAREN":
                args.append(self.parse_expression())
                while self.match("COMMA"):
                    args.append(self.parse_expression())
            self.consume("RPAREN", "Expected ')' after arguments")
            if isinstance(expr, ast.VarRef):
                expr = ast.Call(expr.name, args)
            else:
                raise ParseError("Can only call identifiers")
        return expr

    def parse_primary(self) -> ast.Expr:
        tok = self.current()
        if tok.type == "INT":
            self.pos += 1
            return ast.IntLiteral(int(tok.value))
        if tok.type == "TRUE":
            self.pos += 1
            return ast.BoolLiteral(True)
        if tok.type == "FALSE":
            self.pos += 1
            return ast.BoolLiteral(False)
        if tok.type == "STRING":
            self.pos += 1
            return ast.StringLiteral(tok.value or "")
        if tok.type == "IDENT":
            self.pos += 1
            return ast.VarRef(tok.value)
        if tok.type == "LPAREN":
            self.pos += 1
            expr = self.parse_expression()
            self.consume("RPAREN", "Expected ')'")
            return expr
        raise ParseError(f"Unexpected token {tok.type} at line {tok.line}")


def parse_tokens(tokens: List[Token]) -> ast.Program:
    return Parser(tokens).parse()
