"""Bounded canonical identities for actual loaded Python code, never later source.

Marshal serializes reference-sharing details, so equal code can acquire different
bytes under different loaders or reference counts. This encoder deliberately
binds code attributes and typed constant values, without object-reference IDs.
"""
from __future__ import annotations

import hashlib
import importlib.util
import struct
import sys
from types import CodeType


_LOADED_CODE_OBJECT = sys._getframe().f_code
FORMAT_VERSION = 1
_DOMAIN = b'mylang-verification-loaded-code-v1\0'
_TEXT_CHUNK = 8192
_MAX_AUTH_SOURCE_BYTES = 1 << 20
_CODE_ATTRIBUTES = (
    'co_argcount', 'co_posonlyargcount', 'co_kwonlyargcount', 'co_nlocals',
    'co_stacksize', 'co_flags', 'co_code', 'co_consts', 'co_names', 'co_varnames',
    'co_freevars', 'co_cellvars', 'co_filename', 'co_name', 'co_qualname',
    'co_firstlineno', 'co_linetable', 'co_exceptiontable',
)


class CodeIdentityError(ValueError):
    """Unknown code values or exhausted bounds cannot authorize reusable evidence."""


class CodeLimits:
    """Immutable encoding ceilings; smaller limits refuse work, not change hashes."""
    __slots__ = ('max_depth', 'max_nodes', 'max_bytes')

    def __init__(self, max_depth=128, max_nodes=1_000_000, max_bytes=64 * 1024 * 1024):
        object.__setattr__(self, 'max_depth', max_depth)
        object.__setattr__(self, 'max_nodes', max_nodes)
        object.__setattr__(self, 'max_bytes', max_bytes)
        self._validate()

    def __setattr__(self, _name, _value):
        raise CodeIdentityError('code identity limits are immutable')

    def _validate(self):
        for value, ceiling in ((self.max_depth, 128), (self.max_nodes, 1_000_000),
                               (self.max_bytes, 64 * 1024 * 1024)):
            if type(value) is not int or not 1 <= value <= ceiling:
                raise CodeIdentityError('code identity limits must be positive integers within supported ceilings')


class _Encoder:
    def __init__(self, limits):
        self.limits = limits
        self.nodes = 0
        self.bytes = 0
        self.digest = hashlib.sha256()
        self.sink = self.digest.update

    def emit(self, value):
        if len(value) > self.limits.max_bytes - self.bytes:
            raise CodeIdentityError('code identity encoded byte bound exceeded')
        self.bytes += len(value)
        self.sink(value)

    def header(self, tag, count):
        self.emit(tag)
        self.emit(struct.pack('>Q', count))

    def text(self, value):
        # Count and emit in bounded chunks, including lone surrogate constants.
        size = 0
        for start in range(0, len(value), _TEXT_CHUNK):
            size += len(value[start:start + _TEXT_CHUNK].encode('utf-8', 'surrogatepass'))
            if size > self.limits.max_bytes - self.bytes:
                raise CodeIdentityError('code identity encoded byte bound exceeded')
        self.header(b's', size)
        for start in range(0, len(value), _TEXT_CHUNK):
            self.emit(value[start:start + _TEXT_CHUNK].encode('utf-8', 'surrogatepass'))

    def capture(self, value, depth):
        buffer = bytearray()
        previous = self.sink
        self.sink = buffer.extend
        try:
            self.value(value, depth)
        finally:
            self.sink = previous
        return bytes(buffer)

    def value(self, value, depth=0):
        if depth > self.limits.max_depth:
            raise CodeIdentityError('code identity nesting bound exceeded')
        if self.nodes >= self.limits.max_nodes:
            raise CodeIdentityError('code identity node bound exceeded')
        self.nodes += 1
        kind = type(value)
        if value is None:
            self.emit(b'n')
        elif value is Ellipsis:
            self.emit(b'e')
        elif kind is bool:
            self.emit(b't' if value else b'f')
        elif kind is int:
            size = (value.bit_length() + 7) // 8
            # Check before allocating a potentially large integer payload.
            if size + 9 > self.limits.max_bytes - self.bytes:
                raise CodeIdentityError('code identity encoded byte bound exceeded')
            self.header(b'-' if value < 0 else b'+', size)
            self.emit(abs(value).to_bytes(size, 'big'))
        elif kind is float:
            self.emit(b'd' + struct.pack('>d', value))
        elif kind is complex:
            self.emit(b'j' + struct.pack('>dd', value.real, value.imag))
        elif kind is str:
            self.text(value)
        elif kind is bytes:
            self.header(b'b', len(value))
            self.emit(value)
        elif kind is tuple:
            self.header(b'(', len(value))
            for item in value:
                self.value(item, depth + 1)
        elif kind is frozenset:
            self.header(b'{', len(value))
            elements = [self.capture(item, depth + 1) for item in value]
            for encoded in sorted(elements):
                # Capture already charged both nodes and emitted bytes. Replay
                # only their canonical ordering, never their object-sharing IDs.
                self.sink(encoded)
        elif kind is slice:
            self.emit(b':')
            self.value(value.start, depth + 1)
            self.value(value.stop, depth + 1)
            self.value(value.step, depth + 1)
        elif kind is CodeType:
            self.header(b'c', len(_CODE_ATTRIBUTES))
            for name in _CODE_ATTRIBUTES:
                self.value(name, depth + 1)
                try:
                    attribute = getattr(value, name)
                except AttributeError as error:
                    raise CodeIdentityError('unsupported Python code attribute') from error
                self.value(attribute, depth + 1)
        else:
            raise CodeIdentityError('unsupported loaded-code constant type')


def loaded_code_sha256(code: CodeType, *, limits: CodeLimits | None = None) -> str:
    """Hash loaded executable code and exact constants within explicit bounds.

    Filename/location metadata stays significant. Python bytecode compatibility
    and optimization are domain inputs. Unknown values and exhausted bounds
    raise CodeIdentityError; callers must refuse reuse rather than hash source.
    """
    if type(code) is not CodeType:
        raise CodeIdentityError('expected an actual loaded Python code object')
    if limits is None:
        limits = CodeLimits()
    if type(limits) is not CodeLimits:
        raise CodeIdentityError('unsupported code identity limits')
    limits._validate()
    encoder = _Encoder(limits)
    encoder.emit(_DOMAIN)
    encoder.value((sys.implementation.name, sys.implementation.cache_tag,
                   tuple(sys.version_info[:3]), importlib.util.MAGIC_NUMBER,
                   sys.flags.optimize))
    encoder.value(code)
    return encoder.digest.hexdigest()


def authenticate_code_source(source: bytes, expected: CodeType) -> None:
    """Compare watched source with immutable loaded code; perform no file reads.

    Callers must bind these exact bytes to a current watched content digest and
    retain that watch through use/publication. This proves code equivalence only,
    never filesystem authority. Unsupported or stale source raises an error.
    """
    if type(source) is not bytes or type(expected) is not CodeType:
        raise CodeIdentityError('unsupported source authentication inputs')
    if len(source) > _MAX_AUTH_SOURCE_BYTES:
        raise CodeIdentityError('bootstrap source byte bound exceeded')
    try:
        compiled = compile(source, expected.co_filename, 'exec', dont_inherit=True,
                           optimize=sys.flags.optimize)
    except (SyntaxError, ValueError, OverflowError, RecursionError) as error:
        raise CodeIdentityError('watched bootstrap source cannot compile') from error
    if loaded_code_sha256(compiled) != loaded_code_sha256(expected):
        raise CodeIdentityError('loaded bootstrap code does not match watched source')


# Bind the encoder's own loaded implementation for explicit consumer identity and
# bootstrap authentication against watched bytes; never reread source for this.
LOADED_CODE_SHA256 = loaded_code_sha256(_LOADED_CODE_OBJECT)
