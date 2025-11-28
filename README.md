# Nova Compiler (prototype)

Minimal C-inspired language with automatic memory management and stronger strings. Targets x86-64 today, with an ARM64 backend stubbed for later.

## Status
- Frontend: lexer + recursive-descent parser + tiny type checker (ints, bools, strings, void).
- Codegen: x86-64 SysV assembly that uses libc `printf`/`puts` for IO. ARM64 scaffold included but not emitting yet.
- Runtime: strings are immutable literals for now; heap-managed strings and GC/refcounting are planned but not implemented.

## Language sketch
- Functions: `fn name(params) -> type { ... }`
- Variables: `let x = expr;` (type inferred from literals/ids); `let y: int = 3;` optional annotation.
- Statements: blocks `{ ... }`, `if/else`, `while`, expression statements, `return`.
- Expressions: literals (`123`, `"hi"`, `true`/`false`), identifiers, binary ops `+ - * / == != < <= > >= && ||`, unary `- !`, calls.
- Builtins: `print(expr)` handles `int` and `string`.
- Types: `int` (64-bit), `bool`, `string`, `void`.

## Quick start (needs Python 3 + assembler/linker)
1) Install Python 3 and a toolchain that can assemble x86-64 SysV (e.g., `gcc`/`clang` on Linux or WSL).  
2) `python compiler.py examples/hello.nv -o out.s`  
3) `gcc out.s -o out && ./out`

## Files
- `compiler.py` — CLI entry point.
- `src/lexer.py`, `src/parser.py`, `src/ast.py`, `src/typesys.py`, `src/codegen.py`, `src/errors.py` — compiler core.
- `examples/hello.nv` — sample program.

## Roadmap
- Implement heap strings with reference counting + copy-on-write.
- Add arrays/structs, slices, and first-class functions.
- Flesh out ARM64 backend.
- Add optimizer pass (constant folding, dead code).
