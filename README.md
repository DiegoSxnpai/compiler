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

## Assembly-to-high-level translator (NASM, Windows x64)
- File: `asm_to_lang.asm` — reads x86-64 assembly (subset) and prints a C-like rendition.
- Supported patterns: labels, `mov`, `add`, `sub`, `cmp`, `jmp`, `je/jne/jl/jg/jle/jge` (register/immediate, no memory indirection). Other lines are ignored.
- Build (Visual Studio Developer Command Prompt, with NASM):  
  `nasm -f win64 asm_to_lang.asm -o asm_to_lang.obj`  
  `link /subsystem:console asm_to_lang.obj msvcrt.lib`
- Run: `asm_to_lang.exe input.asm`
- Output examples:  
  `mov rax, 5` -> `let rax = 5;`  
  `add rax, 3` -> `rax = rax + 3;`  
  `cmp rax, rbx` + `je done` -> `if (rax == rbx) goto done;`
- Notes: uses `fopen/fgets/printf`; requires Windows x64 ABI. Extend by adding new opcode strings and printf formats in `asm_to_lang.asm`.
