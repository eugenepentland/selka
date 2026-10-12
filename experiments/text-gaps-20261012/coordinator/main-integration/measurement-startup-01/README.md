# Expiry cleanup startup race

Gate 03 passed all 3,109 selected native tests and both formatting actions, but
failed `MeasurementWindow.test_owned_commands_execute_without_nested_admission_and_expiry_cleans_up`:
the 0.5-second deadline fired before the child wrote its PID file. The assertion
requiring that file was a startup-speed assumption, not an expiry-cleanup defect.

The test now has the child write and close its PID file before sending SIGALRM
to the coordinator. This invokes the real WindowExpired handler and supervised
cleanup. A 10-second watchdog bounds startup; other existing tests still check
real timer-driven expiry. The child-exited and admission-released assertions are
unchanged. Independent review found no issue.

The complete 12-test measurement suite passed. The affected test then passed ten
repetitions (two concurrent processes) with 0.75 seconds deliberately injected
before each admitted subprocess starts, longer than the old 0.5-second deadline.
Raw logs and the delay probe are retained here. A full gate follows this fix.
