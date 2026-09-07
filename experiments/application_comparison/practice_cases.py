"""Public onboarding checks, separate from all application/pilot grading material."""
import base64


def cases():
    examples = [('module-call', b'm', 42), ('diagnostic-repair', b'd', 9)]
    examples += [(f'digit-{digit}', f'f{digit}'.encode(), digit) for digit in range(10)]
    examples += [(name, raw, -1) for name, raw in [
        ('failed-parse', b'fx'), ('missing-digit', b'f'), ('extra-digit', b'f12'),
        ('invalid-utf8', b'f\xff'), ('empty', b''), ('unknown-command', b'x'),
        ('whitespace-not-trimmed', b'm\n'), ('at-byte-limit', b'm' + b' ' * 255),
        ('over-byte-limit', b'm' + b' ' * 256)]]
    return [{'name': name, 'case': {'request_base64': base64.b64encode(raw).decode('ascii'), 'expected': expected}}
            for name, raw, expected in examples]
