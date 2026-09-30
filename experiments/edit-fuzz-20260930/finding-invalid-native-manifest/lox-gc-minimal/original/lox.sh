#!/bin/sh
# The `lox` command for the mylang port. A mylang executable reads its own
# runtime controls (`--gc-stress`, `--print-result`, `--max-steps=`, ...)
# from the arguments before the first `--`, so a bare `lox --gc-stress x.lox`
# would switch on mylang's collector stress mode and hide the flag from Lox.
# Everything after `--` reaches `main` untouched.
exec "$(dirname "$0")/lox-native" -- "$@"
