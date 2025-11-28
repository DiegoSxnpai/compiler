from __future__ import annotations

import string
from typing import List

from .errors import LexError
from .tokens import KEYWORDS, Token


def tokenize(source: str) -> List[Token]:
    tokens: List[Token] = []
    i = 0
    line = 1
    col = 1

    def advance(n: int = 1):
        nonlocal i, line, col
        for _ in range(n):
            if source[i] == "\n":
                line += 1
                col = 1
            else:
                col += 1
            i += 1

    while i < len(source):
        ch = source[i]
        if ch in " \t\r":
            advance()
            continue
        if ch == "\n":
            advance()
            continue
        if ch == "/" and i + 1 < len(source) and source[i + 1] == "/":
            while i < len(source) and source[i] != "\n":
                advance()
            continue
        if ch.isdigit():
            start_col = col
            num = ch
            advance()
            while i < len(source) and source[i].isdigit():
                num += source[i]
                advance()
            tokens.append(Token("INT", num, line, start_col))
            continue
        if ch == '"' or ch == "'":
            quote = ch
            start_col = col
            advance()
            val = ""
            while i < len(source) and source[i] != quote:
                if source[i] == "\\" and i + 1 < len(source):
                    nxt = source[i + 1]
                    if nxt == "n":
                        val += "\n"
                    elif nxt == "t":
                        val += "\t"
                    else:
                        val += nxt
                    advance(2)
                else:
                    val += source[i]
                    advance()
            if i >= len(source) or source[i] != quote:
                raise LexError(f"Unterminated string at line {line}, col {start_col}")
            advance()  # consume closing quote
            tokens.append(Token("STRING", val, line, start_col))
            continue
        if ch in string.ascii_letters or ch == "_":
            start_col = col
            ident = ch
            advance()
            while i < len(source) and (source[i].isalnum() or source[i] == "_"):
                ident += source[i]
                advance()
            if ident in KEYWORDS:
                tokens.append(Token(ident.upper(), ident, line, start_col))
            else:
                tokens.append(Token("IDENT", ident, line, start_col))
            continue
        # multi-char operators
        two = source[i : i + 2]
        if two in ("==", "!=", "<=", ">=", "&&", "||", "->"):
            tokens.append(Token(two, two, line, col))
            advance(2)
            continue
        # single-char
        single = {
            "+": "PLUS",
            "-": "MINUS",
            "*": "STAR",
            "/": "SLASH",
            "<": "LT",
            ">": "GT",
            "=": "ASSIGN",
            "(": "LPAREN",
            ")": "RPAREN",
            "{": "LBRACE",
            "}": "RBRACE",
            ",": "COMMA",
            ";": "SEMICOLON",
            ":": "COLON",
            "!": "BANG",
        }
        if ch in single:
            tokens.append(Token(single[ch], ch, line, col))
            advance()
            continue
        raise LexError(f"Unexpected character '{ch}' at line {line}, col {col}")

    tokens.append(Token("EOF", None, line, col))
    return tokens
