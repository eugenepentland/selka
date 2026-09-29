#!/usr/bin/env python3
"""Reference implementation of the T2 `calc` task (hidden from trial agents)."""
import sys


class CalcError(Exception):
    def __init__(self, col, msg):
        self.col = col
        self.msg = msg


def tokenize(line):
    toks = []
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if c in " \t":
            i += 1
        elif c.isascii() and c.isdigit():
            j = i
            while j < n and line[j].isascii() and line[j].isdigit():
                j += 1
            toks.append(("int", line[i:j], i + 1))
            i = j
        elif c.isascii() and (c.isalpha() or c == "_"):
            j = i
            while j < n and line[j].isascii() and (line[j].isalnum() or line[j] == "_"):
                j += 1
            toks.append(("name", line[i:j], i + 1))
            i = j
        elif c in "+-*/%()=":
            toks.append((c, c, i + 1))
            i += 1
        else:
            raise CalcError(i + 1, f"unexpected character '{c}'")
    toks.append(("eol", "", n + 1))
    return toks


class Parser:
    def __init__(self, toks):
        self.toks = toks
        self.pos = 0

    def peek(self):
        return self.toks[self.pos]

    def advance(self):
        t = self.toks[self.pos]
        self.pos += 1
        return t

    def statement(self):
        t = self.peek()
        if t[0] == "name" and t[1] == "let":
            self.advance()
            name = self.advance()
            if name[0] != "name":
                raise CalcError(name[2], "unexpected token")
            eq = self.advance()
            if eq[0] != "=":
                raise CalcError(eq[2], "unexpected token")
            e = self.expr()
            stmt = ("let", name[1], e)
        elif t[0] == "name" and t[1] == "print":
            self.advance()
            stmt = ("print", self.expr())
        else:
            raise CalcError(t[2], "unexpected token")
        end = self.peek()
        if end[0] != "eol":
            raise CalcError(end[2], "unexpected token")
        return stmt

    def expr(self):
        left = self.term()
        while self.peek()[0] in ("+", "-"):
            op = self.advance()
            right = self.term()
            left = ("bin", op[0], op[2], left, right)
        return left

    def term(self):
        left = self.unary()
        while self.peek()[0] in ("*", "/", "%"):
            op = self.advance()
            right = self.unary()
            left = ("bin", op[0], op[2], left, right)
        return left

    def unary(self):
        if self.peek()[0] == "-":
            op = self.advance()
            return ("neg", op[2], self.unary())
        return self.primary()

    def primary(self):
        t = self.peek()
        if t[0] == "int":
            self.advance()
            return ("int", int(t[1]))
        if t[0] == "name":
            self.advance()
            return ("var", t[1], t[2])
        if t[0] == "(":
            self.advance()
            e = self.expr()
            close = self.peek()
            if close[0] != ")":
                raise CalcError(close[2], "expected ')'")
            self.advance()
            return e
        raise CalcError(t[2], "expected expression")


def trunc_div(a, b):
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


def evaluate(node, env):
    kind = node[0]
    if kind == "int":
        return node[1]
    if kind == "var":
        if node[1] not in env:
            raise CalcError(node[2], f"undefined variable '{node[1]}'")
        return env[node[1]]
    if kind == "neg":
        return -evaluate(node[2], env)
    _, op, col, l, r = node
    a = evaluate(l, env)
    b = evaluate(r, env)
    if op == "+":
        return a + b
    if op == "-":
        return a - b
    if op == "*":
        return a * b
    if b == 0:
        raise CalcError(col, "division by zero")
    q = trunc_div(a, b)
    if op == "/":
        return q
    return a - b * q


def main():
    if len(sys.argv) != 2:
        print("usage: calc FILE", file=sys.stderr)
        return 2
    try:
        with open(sys.argv[1], "rb") as f:
            text = f.read().decode("utf-8")
    except OSError:
        print(f"error: cannot read {sys.argv[1]}", file=sys.stderr)
        return 2
    env = {}
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    for lineno, line in enumerate(lines, 1):
        stripped = line.strip(" \t")
        if stripped == "" or stripped.startswith("#"):
            continue
        try:
            stmt = Parser(tokenize(line)).statement()
            if stmt[0] == "let":
                env[stmt[1]] = evaluate(stmt[2], env)
            else:
                print(evaluate(stmt[1], env))
        except CalcError as e:
            print(f"error: line {lineno} col {e.col}: {e.msg}")
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
