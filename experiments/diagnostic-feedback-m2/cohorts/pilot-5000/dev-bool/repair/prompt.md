# Fix the program

`above` must print 1 when the first argument is larger than the second, and 0 otherwise.

You are working in `project/`. `bin/mylang` is the installed compiler:
`bin/mylang check project/main.my`, `bin/mylang run project/main.my -- <arguments>`.

The same behavior is required for every input, not only the examples in `public/`.
Read `public/expected.json` for the examples this task will be checked against, and run them however you like.

Constraints:

- Work only inside this directory; do not read or write anything outside it and do not spawn subagents.
- At most 20 compiler invocations are available for this attempt.
- You have 5000 generated (output) tokens for this task, reasoning included; the harness reads this session's log while it runs and terminates the attempt as soon as that budget is exceeded.
- Change only what the request requires.

When you are done, reply with a short final message: what you changed and the exact command you ran with its result.
