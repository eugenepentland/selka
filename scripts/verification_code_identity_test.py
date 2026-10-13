#!/usr/bin/env python3
"""Loaded-code identity safety and deterministic loader regressions; no builds."""
import hashlib
import importlib.machinery
import importlib.util
import json
import marshal
import os
from pathlib import Path
import py_compile
import struct
import subprocess
import sys
import tempfile
from types import CodeType
import unittest
from unittest.mock import patch

import verification_code_identity as identity
from verification_code_identity import CodeIdentityError, CodeLimits, loaded_code_sha256


ROOT = Path(__file__).resolve().parents[1]


class LoadedCodeIdentity(unittest.TestCase):
    def setUp(self):
        scratch = ROOT / '.tmp'
        scratch.mkdir(exist_ok=True)
        temporary = tempfile.TemporaryDirectory(prefix='code-identity-', dir=scratch)
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    @staticmethod
    def code(constant):
        return compile('value = None\n', 'fixture.py', 'exec').replace(co_consts=(constant,))

    def run_python(self, source, *arguments, seed='0', optimize=False, allow_pyc=False):
        environment = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', PYTHONHASHSEED=seed)
        environment['PYTHONPATH'] = str(ROOT / 'scripts')
        if allow_pyc:
            environment.pop('PYTHONPYCACHEPREFIX', None)
        else:
            environment['PYTHONPYCACHEPREFIX'] = '/dev/null'
        command = [sys.executable, *(['-O'] if optimize else []), '-c', source, *map(str, arguments)]
        process = subprocess.run(command, cwd=self.root, env=environment,
                                 text=True, capture_output=True, timeout=15)
        self.assertEqual(process.returncode, 0, process.stderr)
        return json.loads(process.stdout)

    def test_helper_binds_its_actual_loaded_root(self):
        self.assertIsInstance(identity._LOADED_CODE_OBJECT, CodeType)
        self.assertEqual(identity.LOADED_CODE_SHA256, loaded_code_sha256(identity._LOADED_CODE_OBJECT))
        self.assertEqual(len(identity.LOADED_CODE_SHA256), 64)
        self.assertEqual(identity.FORMAT_VERSION, 2)

    def test_reference_aliases_change_marshal_but_not_canonical_identity(self):
        source = 'a = "some constant"\ndef f(x):\n    return x + 1\n'
        code = compile(source, 'same.py', 'exec')
        peer = compile(source, 'same.py', 'exec')
        canonical = loaded_code_sha256(code)
        before = marshal.dumps(code)
        aliases = [code.co_consts[0]] * 100
        after = marshal.dumps(code)
        self.assertEqual(code, peer)
        self.assertNotEqual(before, after)
        self.assertEqual(loaded_code_sha256(code), canonical)
        self.assertEqual(loaded_code_sha256(peer), canonical)
        del aliases
        self.assertEqual(loaded_code_sha256(code), canonical)

    def test_every_code_attribute_is_bound(self):
        namespace = {}
        exec(compile('def f(a,b=3,*values,c=4,**named):\n    x=1\n    return a+b+x\n',
                     'same.py', 'exec'), namespace)
        code = namespace['f'].__code__
        changes = {
            'co_argcount': {'co_argcount': 1},
            'co_posonlyargcount': {'co_posonlyargcount': 1},
            'co_kwonlyargcount': {'co_kwonlyargcount': 0},
            'co_nlocals': {'co_nlocals': code.co_nlocals + 1, 'co_varnames': code.co_varnames + ('added',)},
            'co_stacksize': {'co_stacksize': code.co_stacksize + 1},
            'co_flags': {'co_flags': code.co_flags ^ 0x40},
            'co_code': {'co_code': code.co_code + b'\x09\x00'},
            'co_consts': {'co_consts': code.co_consts + ('changed',)},
            'co_names': {'co_names': code.co_names + ('changed',)},
            'co_varnames': {'co_varnames': (*code.co_varnames[:-1], 'renamed')},
            'co_freevars': {'co_freevars': code.co_freevars + ('changed',)},
            'co_cellvars': {'co_cellvars': code.co_cellvars + ('changed',)},
            'co_filename': {'co_filename': 'other.py'},
            'co_name': {'co_name': 'changed'},
            'co_qualname': {'co_qualname': 'changed.scope'},
            'co_firstlineno': {'co_firstlineno': code.co_firstlineno + 1},
            'co_linetable': {'co_linetable': code.co_linetable + b'\x00'},
            'co_exceptiontable': {'co_exceptiontable': code.co_exceptiontable + b'\x00'},
        }
        expected = loaded_code_sha256(code)
        self.assertEqual(set(changes), set(identity._CODE_ATTRIBUTES))
        for attribute, replacement in changes.items():
            with self.subTest(attribute=attribute):
                self.assertNotEqual(loaded_code_sha256(code.replace(**replacement)), expected)

    def test_relocated_copies_of_one_module_hash_identically(self):
        # Two checkouts of one module: only the directory differs. A changed
        # constant, statement or file base name still changes the identity.
        module = 'LIMIT = 4\ndef f(x):\n    return [x + LIMIT for _ in range(2)]\n'
        variants = {'first': ('one/scripts', 'loaded.py', module),
                    'second': ('two/deeper/checkout/scripts', 'loaded.py', module),
                    'constant': ('three/scripts', 'loaded.py', module.replace('LIMIT = 4', 'LIMIT = 5')),
                    'statement': ('four/scripts', 'loaded.py', module.replace('x + LIMIT', 'x - LIMIT')),
                    'renamed': ('five/scripts', 'other.py', module)}
        paths = {}
        for name, (directory, filename, text) in variants.items():
            path = self.root / directory / filename
            path.parent.mkdir(parents=True)
            path.write_text(text)
            paths[name] = path
        source = '''import importlib.util,json,sys
from verification_code_identity import loaded_code_sha256
result={}
for name,path in zip(sys.argv[1::2],sys.argv[2::2]):
    loader=importlib.util.spec_from_file_location('loaded_'+name,path).loader
    result[name]=loaded_code_sha256(loader.get_code('loaded_'+name))
print(json.dumps(result))'''
        digests = self.run_python(source, *[item for pair in paths.items() for item in pair])
        self.assertEqual(digests['first'], digests['second'])
        for changed in ('constant', 'statement', 'renamed'):
            with self.subTest(changed=changed):
                self.assertNotEqual(digests[changed], digests['first'])

    def test_relocation_probe_moves_every_nested_file_name_and_detects_path_identities(self):
        code = compile('def f():\n    def g():\n        return 1\n    return g\n', '/checkout/scripts/m.py', 'exec')
        moved = identity.relocated(code, '/probe')
        nested = [item for item in moved.co_consts if isinstance(item, CodeType)]
        inner = [item for item in nested[0].co_consts if isinstance(item, CodeType)]
        self.assertEqual([moved.co_filename, nested[0].co_filename, inner[0].co_filename],
                         ['/probe/checkout/scripts/m.py'] * 3)
        self.assertEqual(loaded_code_sha256(moved), loaded_code_sha256(code))
        self.assertEqual(identity.relocated(compile('pass', 'relative.py', 'exec'), '/probe').co_filename, 'relative.py')
        self.assertRaises(CodeIdentityError, identity.relocated, code, 'relative')
        # A format-1 style identity (the whole file name significant) is caught.
        with patch.object(identity, '_relocatable_filename', lambda filename: filename):
            self.assertNotEqual(loaded_code_sha256(moved), loaded_code_sha256(code))

    def test_nested_function_semantics_and_defaults_invalidate(self):
        base = compile('def f(x=1):\n    return x+2\n', 'same.py', 'exec')
        body = compile('def f(x=1):\n    return x+3\n', 'same.py', 'exec')
        default = compile('def f(x=4):\n    return x+2\n', 'same.py', 'exec')
        self.assertNotEqual(loaded_code_sha256(base), loaded_code_sha256(body))
        self.assertNotEqual(loaded_code_sha256(base), loaded_code_sha256(default))

    def test_constant_types_and_sequence_frames_do_not_collide(self):
        values = [None, Ellipsis, True, 1, 1.0, 1 + 0j, 'a', b'a', (), (1,),
                  frozenset(), frozenset({1}), slice(None), slice(1),
                  ('ab', 'c'), ('a', 'bc'), ('\ud800',)]
        digests = [loaded_code_sha256(self.code(value)) for value in values]
        self.assertEqual(len(set(digests)), len(values))

    def test_signed_zero_complex_components_and_nan_payload_bits_are_bound(self):
        nan1 = struct.unpack('>d', bytes.fromhex('7ff8000000000001'))[0]
        nan2 = struct.unpack('>d', bytes.fromhex('7ff8000000000002'))[0]
        values = [0.0, -0.0, complex(0.0, 0.0), complex(-0.0, 0.0),
                  complex(0.0, -0.0), nan1, nan2]
        digests = [loaded_code_sha256(self.code(value)) for value in values]
        self.assertEqual(len(set(digests)), len(values))
        self.assertEqual(loaded_code_sha256(self.code(nan1)), loaded_code_sha256(self.code(nan1)))

    def test_frozenset_order_hash_seeds_and_helper_identity_are_stable(self):
        source = '''import json
import verification_code_identity as identity
code=compile("def f(x):\\n    return x in {'alpha','beta','gamma'}\\n",'same.py','exec')
print(json.dumps([identity.loaded_code_sha256(code),identity.LOADED_CODE_SHA256]))'''
        first = self.run_python(source, seed='0')
        second = self.run_python(source, seed='1')
        third = self.run_python(source, seed='17')
        self.assertEqual(first, second)
        self.assertEqual(second, third)

    def test_nested_frozenset_and_slice_constants_are_deterministic(self):
        first = frozenset({('x', 4), ('y', frozenset({1, 2})), ('z', slice(1, 8, 2))})
        second = frozenset({('z', slice(1, 8, 2)), ('y', frozenset({2, 1})), ('x', 4)})
        self.assertEqual(loaded_code_sha256(self.code(first)), loaded_code_sha256(self.code(second)))
        self.assertNotEqual(loaded_code_sha256(self.code(slice(1, 8, 2))),
                            loaded_code_sha256(self.code(slice(1, 8, 3))))

    def test_unknown_mutable_and_subclass_constants_fail_closed(self):
        class IntegerSubclass(int):
            pass
        for value in [[], {}, set(), object(), IntegerSubclass(1)]:
            with self.subTest(kind=type(value).__name__):
                self.assertRaisesRegex(CodeIdentityError, 'unsupported', loaded_code_sha256, self.code(value))
        self.assertRaises(CodeIdentityError, loaded_code_sha256, 'source text')
        self.assertRaises(CodeIdentityError, loaded_code_sha256, self.code(None), limits={})

    def test_bounds_refuse_without_returning_a_weaker_digest(self):
        code = self.code('payload')
        for limits, reason in [(CodeLimits(max_depth=1), 'nesting'),
                               (CodeLimits(max_nodes=1), 'node'),
                               (CodeLimits(max_bytes=1), 'byte')]:
            with self.subTest(reason=reason):
                self.assertRaisesRegex(CodeIdentityError, reason, loaded_code_sha256, code, limits=limits)
        self.assertEqual(loaded_code_sha256(code, limits=CodeLimits(max_bytes=4096)), loaded_code_sha256(code))

    def test_large_integer_text_and_sorted_constants_respect_byte_bound(self):
        values = [-(1 << 20000), '🦜' * 10000, b'x' * 10000,
                  frozenset({str(index) * 100 for index in range(40)})]
        for value in values:
            with self.subTest(kind=type(value).__name__):
                self.assertRaisesRegex(CodeIdentityError, 'byte', loaded_code_sha256,
                                       self.code(value), limits=CodeLimits(max_bytes=1024))
        large = self.code(('x' * 16000, 1 << 12000))
        self.assertEqual(loaded_code_sha256(large), loaded_code_sha256(large))

    def test_limit_configuration_rejects_bool_zero_negative_and_unbounded_values(self):
        for keyword, value in [('max_depth', True), ('max_nodes', 0), ('max_bytes', -1),
                               ('max_depth', 129), ('max_nodes', 1_000_001),
                               ('max_bytes', 64 * 1024 * 1024 + 1)]:
            with self.subTest(keyword=keyword, value=value):
                self.assertRaises(CodeIdentityError, CodeLimits, **{keyword: value})

    def test_python_compatibility_and_optimization_domain_changes_invalidate(self):
        code = self.code(None)
        before = loaded_code_sha256(code)
        with patch.object(importlib.util, 'MAGIC_NUMBER', b'changed'):
            self.assertNotEqual(loaded_code_sha256(code), before)
        source = '''import json
from verification_code_identity import loaded_code_sha256
print(json.dumps(loaded_code_sha256(compile('pass','same.py','exec'))))'''
        self.assertNotEqual(self.run_python(source), self.run_python(source, optimize=True))

    def test_source_after_import_does_not_replace_actual_loaded_identity(self):
        path = self.root / 'loaded.py'
        original = "VALUE='old'\n"
        path.write_text(original)
        code = compile(original, str(path), 'exec')
        before = loaded_code_sha256(code)
        path.write_text("VALUE='new'\n")
        self.assertEqual(loaded_code_sha256(code), before)
        self.assertNotEqual(loaded_code_sha256(compile(path.read_bytes(), str(path), 'exec')), before)

    def test_pyc_source_only_and_import_order_routes_agree_for_same_loaded_code(self):
        path = self.root / 'loaded.py'
        path.write_text('VALUE = "same"\ndef f(x):\n    return x + 1\n')
        bytecode = self.root / '__pycache__' / ('loaded.' + sys.implementation.cache_tag + '.pyc')
        bytecode.parent.mkdir()
        py_compile.compile(str(path), cfile=str(bytecode), doraise=True)
        source = '''import importlib.machinery,json,sys
from verification_code_identity import loaded_code_sha256
path=sys.argv[1]
loader=importlib.machinery.SourceFileLoader('loaded',path)
code=loader.get_code('loaded')
fresh=loader.source_to_code(loader.get_data(path),path)
import collections, decimal
print(json.dumps([loaded_code_sha256(code),loaded_code_sha256(fresh)]))'''
        result = self.run_python(source, path, allow_pyc=True)
        self.assertEqual(result[0], result[1])

    def test_stale_timestamp_pyc_cannot_equal_new_source_identity(self):
        path = self.root / 'loaded.py'
        path.write_text('VALUE = "old"\n')
        metadata = path.stat()
        bytecode = self.root / '__pycache__' / ('loaded.' + sys.implementation.cache_tag + '.pyc')
        bytecode.parent.mkdir()
        py_compile.compile(str(path), cfile=str(bytecode), doraise=True,
                           invalidation_mode=py_compile.PycInvalidationMode.TIMESTAMP)
        path.write_text('VALUE = "new"\n')
        os.utime(path, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
        source = '''import importlib.machinery,json,sys
from verification_code_identity import loaded_code_sha256
path=sys.argv[1]
loader=importlib.machinery.SourceFileLoader('loaded',path)
stale=loader.get_code('loaded')
fresh=loader.source_to_code(loader.get_data(path),path)
print(json.dumps([stale.co_consts[0],fresh.co_consts[0],loaded_code_sha256(stale),loaded_code_sha256(fresh)]))'''
        result = self.run_python(source, path, allow_pyc=True)
        self.assertEqual(result[:2], ['old', 'new'])
        self.assertNotEqual(result[2], result[3])

    def test_actual_module_cli_import_source_loader_and_pyc_routes_agree(self):
        path = self.root / 'loaded.py'
        path.write_text('import hashlib,json,marshal,sys\n'
                        'import verification_code_identity as identity\n'
                        '_LOADED_CODE_OBJECT=sys._getframe().f_code\n'
                        'CONSTANT="some constant"\n'
                        'SHA=identity.loaded_code_sha256(_LOADED_CODE_OBJECT)\n'
                        'RAW=hashlib.sha256(marshal.dumps(_LOADED_CODE_OBJECT)).hexdigest()\n'
                        'if __name__ == "__main__":\n'
                        '    print(json.dumps([SHA,identity.LOADED_CODE_SHA256]))\n')
        environment = dict(os.environ, PYTHONPATH=str(ROOT / 'scripts'),
                           PYTHONDONTWRITEBYTECODE='1', PYTHONPYCACHEPREFIX='/dev/null')
        direct = subprocess.run([sys.executable, str(path)], env=environment, cwd=self.root,
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(direct.returncode, 0, direct.stderr)
        imported = self.run_python('import loaded,json;import verification_code_identity as identity;'
                                   'print(json.dumps([loaded.SHA,identity.LOADED_CODE_SHA256]))')
        forced_source = self.run_python('import importlib.util,json,sys,cache_session;'
            'path=sys.argv[1];spec=importlib.util.spec_from_file_location("loaded",path,'
            'loader=cache_session._SourceLoader("loaded",path));'
            'module=importlib.util.module_from_spec(spec);sys.modules["loaded"]=module;'
            'spec.loader.exec_module(module);'
            'print(json.dumps([module.SHA,module.identity.LOADED_CODE_SHA256]))', path)
        bytecode = self.root / '__pycache__' / ('loaded.' + sys.implementation.cache_tag + '.pyc')
        bytecode.parent.mkdir(exist_ok=True)
        py_compile.compile(str(path), cfile=str(bytecode), doraise=True)
        cached = self.run_python('import loaded,json;import verification_code_identity as identity;'
                                'print(json.dumps([loaded.SHA,identity.LOADED_CODE_SHA256]))', allow_pyc=True)
        self.assertEqual(json.loads(direct.stdout), imported)
        self.assertEqual(imported, forced_source)
        self.assertEqual(forced_source, cached)

    def test_unknown_code_attribute_refuses_identity(self):
        with patch.object(identity, '_CODE_ATTRIBUTES', ('co_not_supported',)):
            self.assertRaisesRegex(CodeIdentityError, 'unsupported Python code attribute',
                                   loaded_code_sha256, self.code(None))

    def test_bootstrap_stale_and_detached_loaded_helper_code_are_distinct(self):
        source = Path(identity.__file__).read_bytes()
        filename = identity._LOADED_CODE_OBJECT.co_filename
        actual = loaded_code_sha256(identity._LOADED_CODE_OBJECT)
        old_source = source.replace(b'_TEXT_CHUNK = 8192', b'_TEXT_CHUNK = 8193')
        stale = compile(old_source, filename, 'exec', dont_inherit=True)
        detached = compile('pass', filename, 'exec', dont_inherit=True)
        self.assertNotEqual(loaded_code_sha256(stale), actual)
        self.assertNotEqual(loaded_code_sha256(detached), actual)
        self.assertEqual(loaded_code_sha256(compile(source, filename, 'exec', dont_inherit=True)), actual)

    def test_source_authentication_matches_actual_immutable_loaded_helper(self):
        source = Path(identity.__file__).read_bytes()
        self.assertIsNone(identity.authenticate_code_source(source, identity._LOADED_CODE_OBJECT))
        stale = source.replace(b'_TEXT_CHUNK = 8192', b'_TEXT_CHUNK = 8193')
        self.assertRaisesRegex(CodeIdentityError, 'does not match',
                               identity.authenticate_code_source, stale, identity._LOADED_CODE_OBJECT)
        detached = compile('pass', identity._LOADED_CODE_OBJECT.co_filename, 'exec')
        self.assertRaisesRegex(CodeIdentityError, 'does not match',
                               identity.authenticate_code_source, source, detached)

    def test_source_authentication_does_not_read_files_or_hash_later_source(self):
        source = Path(identity.__file__).read_bytes()
        before = identity.LOADED_CODE_SHA256
        with patch('builtins.open', side_effect=AssertionError('authentication file read')):
            self.assertIsNone(identity.authenticate_code_source(source, identity._LOADED_CODE_OBJECT))
            self.assertEqual(loaded_code_sha256(identity._LOADED_CODE_OBJECT), before)

    def test_source_authentication_unknown_syntax_and_bytes_fail_closed(self):
        code = self.code(None)
        self.assertRaisesRegex(CodeIdentityError, 'inputs', identity.authenticate_code_source, 'text', code)
        self.assertRaisesRegex(CodeIdentityError, 'inputs', identity.authenticate_code_source, b'pass', None)
        self.assertRaisesRegex(CodeIdentityError, 'cannot compile', identity.authenticate_code_source, b'invalid +', code)
        self.assertRaisesRegex(CodeIdentityError, 'byte bound', identity.authenticate_code_source,
                               b'#' * (identity._MAX_AUTH_SOURCE_BYTES + 1), code)

    def test_source_authentication_distinguishes_typed_equal_constant_values(self):
        code = compile('x=True', 'same.py', 'exec')
        self.assertEqual(code.co_consts[0], 1)
        self.assertRaisesRegex(CodeIdentityError, 'does not match',
                               identity.authenticate_code_source, b'x=1', code)

    def test_helper_implementation_changes_are_explicitly_bound(self):
        source = Path(identity.__file__).read_bytes()
        original = compile(source, identity._LOADED_CODE_OBJECT.co_filename, 'exec')
        modified = compile(source.replace(b'mylang-verification-loaded-code-v2',
                                          b'mylang-verification-loaded-code-x2'),
                           identity._LOADED_CODE_OBJECT.co_filename, 'exec')
        self.assertEqual(loaded_code_sha256(original), identity.LOADED_CODE_SHA256)
        self.assertNotEqual(loaded_code_sha256(modified), identity.LOADED_CODE_SHA256)


if __name__ == '__main__':
    unittest.main()
