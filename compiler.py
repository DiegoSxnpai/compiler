import argparse
from pathlib import Path

from src.lexer import tokenize
from src.parser import parse_tokens
from src.codegen import generate_x86_64


def main():
    parser = argparse.ArgumentParser(description="Nova language compiler")
    parser.add_argument("input", type=Path, help="Source file (.nv)")
    parser.add_argument("-o", "--output", type=Path, default=Path("out.s"), help="Assembly output path")
    parser.add_argument("--target", choices=["x86_64", "arm64"], default="x86_64", help="Target ISA")
    args = parser.parse_args()

    source = args.input.read_text(encoding="utf-8")
    tokens = tokenize(source)
    prog = parse_tokens(tokens)

    if args.target == "x86_64":
        asm = generate_x86_64(prog)
    else:
        raise SystemExit("ARM64 backend not implemented yet")

    args.output.write_text(asm, encoding="utf-8")
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
