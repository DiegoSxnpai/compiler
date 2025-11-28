from dataclasses import dataclass
from typing import Optional


@dataclass
class Token:
    type: str
    value: Optional[str]
    line: int
    column: int


KEYWORDS = {
    "fn",
    "let",
    "if",
    "else",
    "while",
    "return",
    "true",
    "false",
    "int",
    "bool",
    "string",
    "void",
}
