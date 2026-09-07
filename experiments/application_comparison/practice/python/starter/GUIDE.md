# Python preparation utility

Run `python3 main.py` and provide exact bytes on stdin. For example,
`printf d | python3 main.py` exercises the diagnostic branch. A final newline
in the input changes the input, so use `printf` rather than `echo`.

Repair the diagnostic branch first, then the helper call and failure handling.
Python resolves a name when that expression executes: an undeclared identifier
raises `NameError`, with a traceback naming the file and source line. Constants
are ordinary names conventionally written in uppercase. Type annotations do not
enforce types at runtime.

`from helper import multiply_by_six` imports a function from the neighboring
`helper.py` file. Calls use positional arguments inside parentheses. The helper
multiplies its argument by six; choose its argument according to the shared contract.

`parse_digit` accepts exactly one ASCII digit as bytes and raises `ValueError`
for anything else. Handle that failure with `try` / `except ValueError` and
return the required failure result. Avoid catching unrelated exceptions, which
would hide diagnostic or implementation errors.

The expected results are `m` → 42, `d` → 9, and `f0` … `f9` → the digit's
integer value. Every other input returns -1, including malformed `f` inputs,
empty input, and inputs longer than 256 bytes. Output must be one JSON integer
and a newline. Input remains bytes; do not decode or strip whitespace.

Use the preparation check tool to run the supplied public cases. You can also
check an individual case with `printf f7 | python3 main.py`. Editing Python
source requires no compiler rebuild. Only Python's standard library and local
modules may be used.
