class CompileError(Exception):
    pass


class LexError(CompileError):
    pass


class ParseError(CompileError):
    pass


class TypeError(CompileError):
    pass
