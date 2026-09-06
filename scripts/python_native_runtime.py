# Embedded in generated bindings alongside the ordinary data/CLI runtime.
import ctypes as _ctypes


class _NativeFrame(_ctypes.Structure):
    _fields_ = [('function', _ctypes.c_char_p), ('path', _ctypes.c_char_p),
                ('line', _ctypes.c_size_t), ('column', _ctypes.c_size_t)]


class _NativeExecution(_ctypes.Structure):
    _fields_ = [('status', _ctypes.c_int), ('value', _ctypes.c_int64), ('steps', _ctypes.c_uint64),
                ('code', _ctypes.c_char_p), ('path', _ctypes.c_char_p),
                ('line', _ctypes.c_size_t), ('column', _ctypes.c_size_t),
                ('frame_count', _ctypes.c_size_t), ('omitted_frames', _ctypes.c_size_t),
                ('frames', _NativeFrame * 16)]


class _NativeOptions(_ctypes.Structure):
    _fields_ = [('max_steps', _ctypes.c_uint64), ('max_frames', _ctypes.c_uint64),
                ('providers', _ctypes.c_void_p)]


class _NativeNode(_ctypes.Structure):
    _fields_ = [('type', _ctypes.c_char_p), ('bits', _ctypes.c_uint64), ('children', _ctypes.c_size_t)]


class _NativeResult(_ctypes.Structure):
    _fields_ = [('execution', _NativeExecution), ('node_count', _ctypes.c_size_t)]


@dataclass(frozen=True, slots=True)
class NativeLimits:
    max_steps: int = 1000000
    max_frames: int = 256
    max_nodes: int = 65536
    max_depth: int = 128

    def __post_init__(self):
        if any(type(n) is not int or not 0 < n <= 18446744073709551615 for n in (self.max_steps, self.max_frames)):
            raise CodecError('InvalidNativeLimits')
        if type(self.max_nodes) is not int or not 0 < self.max_nodes <= 100000:
            raise CodecError('InvalidNativeLimits')
        if type(self.max_depth) is not int or not 0 < self.max_depth <= 128:
            raise CodecError('InvalidNativeLimits')


NATIVE_FUNCTION_NAMES = tuple(name for name in FUNCTION_NAMES
    if all(ty not in UNSUPPORTED_TYPES for ty in
           [_FUNCTIONS[name]['result'], *(p['type'] for p in _FUNCTIONS[name]['parameters'])]))
_NATIVE_TYPE_BYTES = {name: name.encode('utf-8') for name in _DEFINITIONS}
_NATIVE_TAGS = {name: {case['name']: i for i, case in enumerate(definition['cases'])}
                for name, definition in _DEFINITIONS.items() if 'cases' in definition}


def _native_flatten(name, value, output):
    definition = _DEFINITIONS[name]
    kind = definition['kind']
    children = []
    bits = 0
    if kind == 'integer':
        bits = int(value) & 18446744073709551615
    elif kind == 'boolean':
        bits = int(value)
    elif kind == 'record':
        children = [(f['type'], value[f['name']]) for f in definition['fields']]
    elif kind == 'array':
        children = [(definition['element'], child) for child in value]
    elif kind == 'table':
        children = [(definition['element'], value[case['name']]) for case in _DEFINITIONS[definition['key']]['cases']]
    elif kind == 'enumeration':
        bits = _NATIVE_TAGS[name][value]
    else:
        bits = _NATIVE_TAGS[name][value['case']]
        case = definition['cases'][bits]
        if 'payload' in case:
            children = [(case['payload'], value['value'])]
    output.append((_NATIVE_TYPE_BYTES[name], bits, len(children)))
    for child, item in children:
        _native_flatten(child, item, output)


def _native_expand(name, nodes, count, cursor, depth, limits):
    if depth > limits.max_depth:
        raise CodecError('CodecDepthLimit', '/result')
    if cursor[0] >= count:
        raise CallError('InvalidNativeResult')
    node = nodes[cursor[0]]
    cursor[0] += 1
    if node.type != _NATIVE_TYPE_BYTES[name]:
        raise CallError('InvalidNativeResult')
    definition = _DEFINITIONS[name]
    kind = definition['kind']
    if node.children > count - cursor[0]:
        raise CallError('InvalidNativeResult')
    children = []
    if kind in ('integer', 'boolean', 'enumeration'):
        if node.children:
            raise CallError('InvalidNativeResult')
        if kind == 'integer':
            number = node.bits - (18446744073709551616 if definition['signed'] and node.bits >> 63 else 0)
            return str(number)
        if kind == 'boolean':
            if node.bits > 1:
                raise CallError('InvalidNativeResult')
            return bool(node.bits)
        if node.bits >= len(definition['cases']):
            raise CallError('InvalidNativeResult')
        return definition['cases'][node.bits]['name']
    if kind == 'record':
        if node.children != len(definition['fields']):
            raise CallError('InvalidNativeResult')
        children = [(f['name'], f['type']) for f in definition['fields']]
    elif kind == 'array':
        if node.children != definition['length']:
            raise CallError('InvalidNativeResult')
        children = [(i, definition['element']) for i in range(definition['length'])]
    elif kind == 'table':
        if node.children != len(_DEFINITIONS[definition['key']]['cases']):
            raise CallError('InvalidNativeResult')
        children = [(c['name'], definition['element']) for c in _DEFINITIONS[definition['key']]['cases']]
    else:
        if node.bits >= len(definition['cases']):
            raise CallError('InvalidNativeResult')
        case = definition['cases'][node.bits]
        children = [('value', case['payload'])] if 'payload' in case else []
    if node.children != len(children) or (kind in ('record', 'array', 'table') and node.bits):
        raise CallError('InvalidNativeResult')
    values = {key: _native_expand(child, nodes, count, cursor, depth+1, limits) for key, child in children}
    if kind == 'array':
        return list(values.values())
    if kind in ('tagged_union', 'result'):
        values['case'] = case['name']
    return values


class NativeClient:
    """Load an explicitly selected trusted native library and verify its public schema.

    Calls are synchronous and bounded by steps, frames and value nodes; they do
    not provide the subprocess Client's wall-clock timeout or process isolation.
    """
    def __init__(self, library, *, limits=NativeLimits()):
        import hashlib
        from pathlib import Path
        if type(limits) is not NativeLimits:
            raise CodecError('InvalidNativeLimits')
        self.limits = limits
        self.library = str(Path(library).expanduser().resolve())
        try:
            self._library = _ctypes.CDLL(self.library)
            schema = self._library.mylang_native_schema_json_v1
            digest = self._library.mylang_native_schema_sha256_v1
            for query in (schema, digest):
                query.argtypes = []
                query.restype = _ctypes.c_char_p
            document, identity = schema(), digest()
            if not document or not identity:
                raise CallError('NativeSchemaUnavailable')
            if identity != SCHEMA_SHA256.encode('ascii') or hashlib.sha256(document).hexdigest() != SCHEMA_SHA256:
                raise CallError('NativeSchemaMismatch')
            call = self._library.mylang_native_call_values_v1
            call.argtypes = [_ctypes.c_char_p, _ctypes.POINTER(_NativeNode), _ctypes.c_size_t,
                             _ctypes.POINTER(_NativeNode), _ctypes.c_size_t,
                             _ctypes.POINTER(_NativeOptions), _ctypes.POINTER(_NativeResult)]
            call.restype = _ctypes.c_int
            self._call = call
        except OSError as error:
            raise CallError('NativeLibraryIO', str(error)) from error
        except AttributeError as error:
            raise CallError('NativeABIUnavailable', str(error)) from error

    def call(self, name, /, **arguments):
        if type(name) is not str or name not in _FUNCTIONS:
            raise CodecError('UnknownFunction')
        if name not in NATIVE_FUNCTION_NAMES:
            raise CodecError('UnsupportedFunction')
        function = _FUNCTIONS[name]
        _keys(arguments, [p['name'] for p in function['parameters']], '/arguments')
        limits = self.limits
        if type(limits) is not NativeLimits:
            raise CodecError('InvalidNativeLimits')
        codec_limits = Limits(max_values=limits.max_nodes, max_depth=limits.max_depth)
        budget = _Budget(codec_limits)
        flat = []
        for parameter in function['parameters']:
            value = _convert(parameter['type'], arguments[parameter['name']], True, budget, 1, _path('/arguments', parameter['name']))
            _native_flatten(parameter['type'], value, flat)
        inputs = (_NativeNode * len(flat))(*[_NativeNode(*node) for node in flat])
        output = (_NativeNode * limits.max_nodes)()
        options = _NativeOptions(limits.max_steps, limits.max_frames, None)
        result = _NativeResult()
        status = self._call(name.encode('utf-8'), inputs, len(flat), output, len(output), _ctypes.byref(options), _ctypes.byref(result))
        execution = result.execution
        if status not in (0, 1, 2) or status != execution.status:
            raise CallError('InvalidNativeResult')
        if status:
            code = execution.code.decode('utf-8', 'replace') if execution.code else 'NativeFailure'
            location = (execution.path.decode('utf-8', 'replace') + f':{execution.line}:{execution.column}') if execution.path else ''
            frames = []
            if execution.frame_count > 16:
                raise CallError('InvalidNativeResult')
            for frame in execution.frames[:execution.frame_count]:
                frames.append((frame.function or b'?').decode('utf-8', 'replace'))
            detail = '; '.join(filter(None, [location, ' -> '.join(frames),
                f'required output nodes: {result.node_count}' if code == 'OutputTooSmall' else '']))
            raise CallError(code, detail, status)
        if not 0 < result.node_count <= len(output):
            raise CallError('InvalidNativeResult')
        cursor = [0]
        wire = _native_expand(function['result'], output, result.node_count, cursor, 1, limits)
        if cursor[0] != result.node_count:
            raise CallError('InvalidNativeResult')
        return _convert(function['result'], wire, False, _Budget(codec_limits), 1, '/result')
