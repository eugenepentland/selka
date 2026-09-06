# Embedded verbatim in generated modules; no compiler/runtime package dependency.
class CodecError(ValueError):
    def __init__(self, code, path=''):
        self.code = code
        self.path = path
        super().__init__(code + (f' at {path}' if path else ''))


@dataclass(frozen=True, slots=True)
class Limits:
    max_bytes: int = 1024 * 1024
    max_values: int = 65536
    max_tokens: int = 262144
    max_depth: int = 64

    def __post_init__(self):
        if any(type(x) is not int or x <= 0 for x in (self.max_bytes, self.max_values, self.max_tokens, self.max_depth)) or self.max_depth > 128:
            raise CodecError('InvalidCodecLimits')


class _Budget:
    def __init__(self, limits):
        self.limits = limits
        self.values = 0

    def take(self, depth, path):
        if depth > self.limits.max_depth:
            raise CodecError('CodecDepthLimit', path)
        if self.values == self.limits.max_values:
            raise CodecError('CodecValueLimit', path)
        self.values += 1


def _path(parent, key):
    return parent + '/' + str(key).replace('~', '~0').replace('/', '~1')


def _unique(pairs):
    output = {}
    for key, value in pairs:
        if key in output:
            raise CodecError('DuplicateField')
        output[key] = value
    return output


def _invalid_constant(value):
    raise CodecError('SyntaxError')


class _Number(str):
    # JSON numbers remain distinguishable from the required decimal strings.
    pass


def _scan(text, limits):
    """Count complete-input Zig scanner tokens/fragments before JSON DOM parsing."""
    index = depth = tokens = 0

    def token():
        nonlocal tokens
        tokens += 1
        if tokens > limits.max_tokens:
            raise CodecError('CodecTokenLimit')

    while index < len(text):
        char = text[index]
        if char in ' \t\r\n,:':
            index += 1
        elif char in '{}[]':
            token()
            depth += 1 if char in '{[' else -1
            if depth < 0:
                raise CodecError('SyntaxError')
            if depth > limits.max_depth + 1:
                raise CodecError('CodecDepthLimit')
            index += 1
        elif char == '"':
            index += 1
            plain = False
            while index < len(text) and text[index] != '"':
                char = text[index]
                if ord(char) < 32:
                    raise CodecError('SyntaxError')
                if char != '\\':
                    plain = True
                    index += 1
                    continue
                if plain:
                    token()
                index += 1
                if index == len(text):
                    raise CodecError('SyntaxError')
                escaped = text[index]
                index += 1
                if escaped in '"\\/':
                    plain = True
                elif escaped in 'bfnrt':
                    token()
                    plain = False
                elif escaped == 'u':
                    digits = text[index:index + 4]
                    if len(digits) != 4 or not re.fullmatch('[0-9a-fA-F]{4}', digits):
                        raise CodecError('SyntaxError')
                    code = int(digits, 16)
                    index += 4
                    if 0xD800 <= code <= 0xDBFF:
                        low = text[index + 2:index + 6]
                        if text[index:index + 2] != '\\u' or not re.fullmatch('[0-9a-fA-F]{4}', low) or not 0xDC00 <= int(low, 16) <= 0xDFFF:
                            raise CodecError('SyntaxError')
                        index += 6
                    elif 0xDC00 <= code <= 0xDFFF:
                        raise CodecError('SyntaxError')
                    token()
                    plain = False
                else:
                    raise CodecError('SyntaxError')
            if index == len(text):
                raise CodecError('SyntaxError')
            token()  # Final .string, even after an escape or for an empty string.
            index += 1
        else:
            token()
            while index < len(text) and text[index] not in ' \t\r\n,:{}[]"':
                index += 1
    if depth != 0:
        raise CodecError('SyntaxError')


def _keys(value, expected, path):
    if type(value) is not dict:
        raise CodecError('ValueTypeMismatch', path)
    if set(value) != set(expected):
        code = 'UnexpectedCodecField' if len(value) > len(expected) else 'IncompleteCodecValue'
        raise CodecError(code, path)


def _convert(name, value, encode, budget, depth, path):
    budget.take(depth, path)
    definition = _DEFINITIONS[name]
    kind = definition['kind']
    if kind == 'integer':
        if encode:
            if type(value) is not int:
                raise CodecError('ValueTypeMismatch', path)
            number = value
        else:
            if type(value) is not str:
                raise CodecError('ValueTypeMismatch', path)
            if len(value) > 20 or not re.fullmatch('0|-?[1-9][0-9]*', value):
                raise CodecError('InvalidCodecInteger', path)
            number = int(value)
        if not int(definition['minimum']) <= number <= int(definition['maximum']):
            raise CodecError('CodecIntegerOutOfRange', path)
        return str(number) if encode else number
    if kind == 'boolean':
        if type(value) is not bool:
            raise CodecError('ValueTypeMismatch', path)
        return value
    if kind == 'enumeration':
        if encode:
            if type(value) is not TYPES[name]:
                raise CodecError('ValueTypeMismatch', path)
            return value.value
        if type(value) is not str:
            raise CodecError('ValueTypeMismatch', path)
        try:
            return TYPES[name](value)
        except ValueError:
            raise CodecError('UnknownCodecCase', path) from None
    if kind in ('tagged_union', 'result'):
        if encode:
            identity = _CASE_NAMES.get(type(value))
            if identity is None or identity[0] != name:
                raise CodecError('ValueTypeMismatch', path)
            case_name = identity[1]
        else:
            if type(value) is not dict or 'case' not in value:
                raise CodecError('IncompleteCodecValue' if type(value) is dict else 'ValueTypeMismatch', path)
            case_name = value['case']
            if type(case_name) is not str:
                raise CodecError('ValueTypeMismatch', _path(path, 'case'))
        case = _CASES[name].get(case_name)
        if case is None:
            raise CodecError('UnknownCodecCase', _path(path, 'case'))
        has_payload = 'payload' in case
        if not encode:
            _keys(value, ('case', 'value') if has_payload else ('case',), path)
        if has_payload:
            child = value.value if encode else value['value']
            payload = _convert(case['payload'], child, encode, budget, depth + 1, _path(path, 'value'))
            return {'case': case_name, 'value': payload} if encode else CASES[name][case_name](payload)
        return {'case': case_name} if encode else CASES[name][case_name]()
    if kind == 'record':
        fields = definition['fields']
        if encode:
            if type(value) is not TYPES[name]:
                raise CodecError('ValueTypeMismatch', path)
        else:
            _keys(value, [field['name'] for field in fields], path)
        if len(fields) > budget.limits.max_values - budget.values:
            raise CodecError('CodecValueLimit', path)
        output = {}
        for field in fields:
            key = field['name']
            attribute = FIELDS[name][key]
            child = getattr(value, attribute) if encode else value[key]
            output[key if encode else attribute] = _convert(field['type'], child, encode, budget, depth + 1, _path(path, key))
        return output if encode else TYPES[name](**output)
    length = definition['length']
    if kind == 'array':
        if type(value) is not (tuple if encode else list):
            raise CodecError('ValueTypeMismatch', path)
        if len(value) != length:
            raise CodecError('IncompleteCodecValue', path)
        if length > budget.limits.max_values - budget.values:
            raise CodecError('CodecValueLimit', path)
        output = [_convert(definition['element'], child, encode, budget, depth + 1, _path(path, index)) for index, child in enumerate(value)]
        return output if encode else tuple(output)
    if kind == 'table':
        key_type = TYPES[definition['key']]
        keys = [case['name'] for case in _DEFINITIONS[definition['key']]['cases']]
        if encode:
            if not isinstance(value, Mapping) or any(type(key) is not key_type for key in value):
                raise CodecError('ValueTypeMismatch', path)
            if set(value) != {key_type(key) for key in keys}:
                raise CodecError('IncompleteCodecValue', path)
        else:
            _keys(value, keys, path)
        if length > budget.limits.max_values - budget.values:
            raise CodecError('CodecValueLimit', path)
        output = {}
        for key in keys:
            child = value[key_type(key) if encode else key]
            output[key if encode else key_type(key)] = _convert(definition['element'], child, encode, budget, depth + 1, _path(path, key))
        return output if encode else MappingProxyType(output)
    raise CodecError('NoImplicitCodec', path)


def _supported(name):
    if type(name) is not str:
        raise CodecError('ValueTypeMismatch', '/type')
    if name not in _DEFINITIONS:
        raise CodecError('UnknownCodecType')
    if name in UNSUPPORTED_TYPES:
        raise CodecError('NoImplicitCodec')


def loads(data, *, expected_type=None, limits=Limits()):
    """Decode a typed-json-v1 envelope into generated nominal Python values."""
    try:
        if type(data) is bytes:
            if len(data) > limits.max_bytes:
                raise CodecError('CodecByteLimit')
            text = data.decode('utf-8')
        elif type(data) is str:
            if len(data) > limits.max_bytes:
                raise CodecError('CodecByteLimit')
            text = data
        else:
            raise TypeError('loads expects str or UTF-8 bytes')
        if len(text.encode('utf-8')) > limits.max_bytes:
            raise CodecError('CodecByteLimit')
    except UnicodeError:
        raise CodecError('SyntaxError') from None
    _scan(text, limits)
    try:
        document = json.loads(text, object_pairs_hook=_unique, parse_int=_Number, parse_float=_Number, parse_constant=_invalid_constant)
    except (json.JSONDecodeError, RecursionError):
        raise CodecError('SyntaxError') from None
    _keys(document, ('version', 'type', 'value'), '')
    if document['version'] != 'typed-json-v1':
        raise CodecError('UnsupportedCodecVersion')
    name = document['type']
    if type(name) is not str or (expected_type is not None and name != expected_type):
        raise CodecError('ValueTypeMismatch', '/type')
    _supported(name)
    return _convert(name, document['value'], False, _Budget(limits), 1, '/value')


def dumps(value, *, type_name=None, limits=Limits()):
    """Validate Python values and emit canonical typed-json-v1 without mutation."""
    name = type_name if type_name is not None else _TYPE_NAMES.get(type(value))
    if name is None:
        raise TypeError('type_name is required for scalar and structural root values')
    _supported(name)
    document = {'version': 'typed-json-v1', 'type': name, 'value': _convert(name, value, True, _Budget(limits), 1, '/value')}
    chunks = []
    count = 0
    for chunk in json.JSONEncoder(ensure_ascii=False, allow_nan=False, separators=(',', ':')).iterencode(document):
        count += len(chunk.encode('utf-8'))
        if count > limits.max_bytes:
            raise CodecError('CodecByteLimit')
        chunks.append(chunk)
    text = ''.join(chunks)
    _scan(text, limits)
    return text
