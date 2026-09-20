#!/bin/sh
# A scripted stand-in for a solver session — NOT a model.
#
# It exists to exercise the harness end to end with a real event stream: it runs
# the compiler, sees the failure the task starts from, optionally reads the
# structured context the treatment arm's prompt names, applies the frozen
# intended answer, and runs the program again. A development pilot that used
# this solver is labelled `script:...` in its observation and is never quoted as
# a productivity result.
set -u

echo "scripted solver: checking the project as it stands"
mylang check main.my || echo "scripted solver: check failed as expected"

if [ "${E1_ARM:-plain}" = "focused-context" ] && [ -n "${E1_CONTEXT_SYMBOL:-}" ]; then
    echo "scripted solver: reading context for ${E1_CONTEXT_SYMBOL}"
    mylang context main.my --symbol="${E1_CONTEXT_SYMBOL}" --format=json >/dev/null \
        || echo "scripted solver: context query failed"
fi

echo "scripted solver: applying the intended answer"
cp -R "${E1_ANSWER}/files/." .

echo "scripted solver: running the project"
mylang run main.my
