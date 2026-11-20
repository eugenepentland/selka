"""Runtime-result signature shared by the integer boundary fixtures."""
import re


def signature(result):
    if result.returncode == 0:
        return (0, result.stdout)
    match = re.search(rb":(\d+):(\d+): error\[(R_[A-Z_]+)\]", result.stderr)
    assert result.returncode == 1 and match, result.stderr.decode(errors="replace")
    return (1, match.groups(), result.stdout)
