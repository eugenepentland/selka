#!/usr/bin/env python3
"""The environment identity contract (ENV-IDENTITY-1, ENV-IDENTITY-2) in Python.

`src/environment_identity.zon` is the one definition of which environment
variables are keyed (their `NAME=VALUE` enters every identity), host (keyed by
host tooling only, never by a guest test receipt), placement (passed to
children, never keyed) or dropped (removed from children and from every key).
A digest has a scope: "guest" keys the keyed class, "host" keys keyed and host. The compiler imports it at compile time through
`src/environment_identity.zig`; this module reads the same file with a strict
parser for the small ZON subset the contract uses, and classifies, projects
and digests environments exactly as the Zig code does. The fixture under
`test/fixtures/environment-identity/` pins that both agree.

Precedence: an exact entry beats every prefix entry (`NAME*`), the longest
matching prefix beats a shorter one, and a name nothing matches is dropped.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import re
import struct
from typing import Mapping

CONTRACT_PATH = Path(__file__).resolve().parents[1] / "src" / "environment_identity.zon"
DOMAIN = "environment-identity-v1"
CLASSES = ("keyed", "host", "placement", "dropped")
SCOPES = ("guest", "host")

_TOKEN = re.compile(r'\s+|//[^\n]*|\.\{|\}|=|,|\.[A-Za-z_][A-Za-z0-9_]*|"[^"\\\n]*"')


class ContractError(ValueError):
    """The contract file is outside the accepted ZON subset or breaks a rule."""


def _tokens(text: str) -> list[str]:
    tokens, position = [], 0
    while position < len(text):
        match = _TOKEN.match(text, position)
        if match is None:
            raise ContractError(f"unexpected text at offset {position}: {text[position:position + 20]!r}")
        token = match.group(0)
        if not (token.isspace() or token.startswith("//")):
            tokens.append(token)
        position = match.end()
    return tokens


def parse(text: str) -> dict[str, list[str]]:
    """Parse contract text into {class: [entry, ...]}, validating every rule."""
    tokens = _tokens(text)
    index = 0

    def expect(wanted: str) -> None:
        nonlocal index
        if index >= len(tokens) or tokens[index] != wanted:
            found = tokens[index] if index < len(tokens) else "end of file"
            raise ContractError(f"expected {wanted!r}, found {found!r}")
        index += 1

    expect(".{")
    classes: dict[str, list[str]] = {}
    while tokens[index:index + 1] != ["}"]:
        if index >= len(tokens) or not tokens[index].startswith(".") or tokens[index] == ".{":
            raise ContractError(f"expected a field name, found {tokens[index] if index < len(tokens) else 'end of file'!r}")
        name = tokens[index][1:]
        index += 1
        if name not in CLASSES or name in classes:
            raise ContractError(f"unknown or repeated field .{name}")
        expect("=")
        expect(".{")
        entries: list[str] = []
        while tokens[index:index + 1] != ["}"]:
            token = tokens[index] if index < len(tokens) else ""
            if not token.startswith('"'):
                raise ContractError(f"expected a string in .{name}, found {token or 'end of file'!r}")
            entries.append(token[1:-1])
            index += 1
            if tokens[index:index + 1] == [","]:
                index += 1
            elif tokens[index:index + 1] != ["}"]:
                raise ContractError(f"expected ',' or '}}' in .{name}")
        expect("}")
        classes[name] = entries
        if tokens[index:index + 1] == [","]:
            index += 1
        elif tokens[index:index + 1] != ["}"]:
            raise ContractError("expected ',' or '}' after a field")
    expect("}")
    if index != len(tokens):
        raise ContractError("text after the contract")
    if set(classes) != set(CLASSES):
        raise ContractError(f"the contract needs exactly the fields {', '.join(CLASSES)}")
    seen: set[str] = set()
    for name in CLASSES:
        for entry in classes[name]:
            if entry in ("", "*") or "*" in entry[:-1]:
                raise ContractError(f"invalid entry {entry!r}: '*' only ends a non-empty prefix")
            if entry in seen:
                raise ContractError(f"duplicate entry {entry!r}")
            seen.add(entry)
    return classes


class Contract:
    """A parsed contract: classify, project and digest environments."""

    def __init__(self, classes: Mapping[str, list[str]]):
        self.exact: dict[str, str] = {}
        self.prefixes: list[tuple[str, str]] = []
        for name in CLASSES:
            for entry in classes[name]:
                if entry.endswith("*"):
                    self.prefixes.append((entry[:-1], name))
                else:
                    self.exact[entry] = name
        self.prefixes.sort(key=lambda item: -len(item[0]))

    def classify(self, name: str) -> str:
        """'keyed', 'host', 'placement' or 'dropped' for the variable `name`."""
        if name in self.exact:
            return self.exact[name]
        for prefix, kind in self.prefixes:
            if name.startswith(prefix):
                return kind
        return "dropped"

    def host_keyed(self, name: str) -> bool:
        """Whether host tooling keys `name` (the keyed and host classes)."""
        return self.classify(name) in ("keyed", "host")

    def project(self, env: Mapping[str, str]) -> dict[str, str]:
        """The environment a child receives: keyed, host and placement kept, dropped removed."""
        return {name: value for name, value in env.items() if self.classify(name) != "dropped"}

    def digest(self, env: Mapping[str, str], tools: Mapping[str, str], scope: str = "guest") -> str:
        """Lowercase hex SHA-256 of the variables `scope` keys and the tool digests (see the Zig `digest`)."""
        if scope not in SCOPES:
            raise ValueError(f"unknown digest scope {scope!r}")
        included = ("keyed",) if scope == "guest" else ("keyed", "host")
        hash = hashlib.sha256()
        _field(hash, DOMAIN.encode())
        keyed = [(os.fsencode(name), os.fsencode(value)) for name, value in env.items() if self.classify(name) in included]
        for name, value in sorted(keyed):
            _field(hash, name)
            _field(hash, value)
        for name, digest in sorted((name.encode(), digest.encode()) for name, digest in tools.items()):
            _field(hash, b"tool:" + name)
            _field(hash, digest)
        return hash.hexdigest()


def _field(hash, data: bytes) -> None:
    hash.update(struct.pack("<Q", len(data)))
    hash.update(data)


def load(path: Path = CONTRACT_PATH) -> Contract:
    """Read and validate the contract file."""
    return Contract(parse(Path(path).read_text(encoding="utf-8")))


CONTRACT = load()


def classify(name: str) -> str:
    """'keyed', 'host', 'placement' or 'dropped' for `name` under the checked-in contract."""
    return CONTRACT.classify(name)


def host_keyed(name: str) -> bool:
    """Whether host tooling keys `name` under the checked-in contract."""
    return CONTRACT.host_keyed(name)


def project(env: Mapping[str, str]) -> dict[str, str]:
    """The child environment under the checked-in contract."""
    return CONTRACT.project(env)


def digest(env: Mapping[str, str], tools: Mapping[str, str], scope: str = "guest") -> str:
    """The environment digest for `scope` under the checked-in contract; identical to the Zig one."""
    return CONTRACT.digest(env, tools, scope)
