#!/usr/bin/env python3
"""Run cf.py with a linear-size, function-local matcher for P1 count branches."""
import re
import cf

original_edit = cf.edit
BRANCH = re.compile(r'^  br i1 %rp[.\d]+, label %rc\.(?:inc|dec)[.\d]+, label %(rc\.slow[.\d]+), !prof !\d+$', re.M)
SLOW = re.compile(r'^(rc\.slow[.\d]+):\n(?:  .*\n)*?  br label %([.\w]+)$', re.M)


def edit(text, variant):
    parts = variant.split('+')
    if 'norc' not in parts:
        return original_edit(text, variant)
    filtered = '+'.join(part for part in parts if part != 'norc') or 'base'
    text = original_edit(text, filtered)
    original = text
    text = re.sub(r'^  br i1 (%rs[.\d]*), label %([.\w]+), label %rc\.(inc|dec)[.\d]*$',
                  r'  br label %\2', text, flags=re.M)
    functions = text.split('\n}\n')
    for index, function in enumerate(functions):
        joins = dict(SLOW.findall(function))
        def replace(match):
            try:
                return '  br label %' + joins[match.group(1)]
            except KeyError:
                raise RuntimeError('count slow-path join not found') from None
        functions[index] = BRANCH.sub(replace, function)
    text = '\n}\n'.join(functions)
    if text == original:
        raise RuntimeError('norc changed no count branches; update the probe before measuring')
    return text


if __name__ == '__main__':
    cf.edit = edit
    cf.main()
