#!/usr/bin/env python3
"""Enforcement through the real adapter, demonstrated on a development case.

The scripted checks in `m2_smoke.py` establish the accounting design. This module
exercises the adapter contract the participants will actually run through: the
request carries the *remaining* generation allowance, exhaustion stops generation,
an incomplete candidate cannot reach selection, and an adapter that overshoots is
charged what it actually generated — refusing a call after it consumed tokens
cannot recover that budget, so the overshoot is recorded as expenditure.

    python3 experiments/diagnostic-feedback-m2/budget_adapter.py
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from budget import Envelope, Usage  # noqa: E402

DEV_CASE = {"id": "dev-generic", "brief": "print the largest of the three arguments",
            "commands": "bin/mylang check project/main.my; bin/mylang run project/main.my -- 1 3 2",
            "public": [{"args": ["1", "3", "2"], "stdout": "3"}]}


@dataclass
class Allowance:
    """What one model request was permitted and what it actually produced."""
    call: int
    allowance: int
    generated: int
    overshoot: int


class ScriptedAdapter:
    """Honours the allowance it is given; records every allowance for inspection."""

    def __init__(self, answers: list[str], per_call: int = 100):
        self.answers = answers
        self.per_call = per_call
        self.allowances: list[Allowance] = []

    def generate(self, context: str, allowance: int) -> tuple[str, Usage]:
        generated = min(self.per_call, max(allowance, 0))
        answer = self.answers[min(len(self.allowances), len(self.answers) - 1)]
        self.allowances.append(Allowance(len(self.allowances), allowance, generated, 0))
        return answer, Usage(input_tokens=40, cache_read_tokens=300, output_tokens=generated,
                             reasoning_tokens=generated // 2)


class OvershootingAdapter(ScriptedAdapter):
    """Ignores the allowance: the envelope must record what was really spent."""

    def generate(self, context: str, allowance: int) -> tuple[str, Usage]:
        generated = self.per_call + 60
        answer = self.answers[min(len(self.allowances), len(self.answers) - 1)]
        self.allowances.append(Allowance(len(self.allowances), allowance, generated,
                                         max(0, generated - allowance)))
        return answer, Usage(input_tokens=40, cache_read_tokens=300, output_tokens=generated,
                             reasoning_tokens=generated // 2)


def run_task(adapter: ScriptedAdapter, cap: int, minimum_call: int = 50) -> dict:
    """One development case under a task-level envelope, through the adapter."""
    envelope = Envelope(cap)
    candidates: list[dict] = []
    while envelope.remaining() >= minimum_call:
        allowance = envelope.remaining()
        candidate, usage = adapter.generate(DEV_CASE["brief"], allowance)
        entry = envelope.charge(usage, label=f"candidate-{len(candidates) + 1}", allowance=allowance)
        passes = all(example["stdout"] in candidate for example in DEV_CASE["public"])
        candidates.append({"candidate": candidate, "charged": entry["charged"], "overshoot": entry["overshoot"],
                           "passes_public": passes})
        if passes or entry["overshoot"] > 0:
            # An overshooting call ends the candidate: the budget is already spent.
            break
    selected = next((candidate for candidate in candidates if candidate["passes_public"]), None)
    return {"cap": cap, "envelope": envelope, "candidates": candidates, "selected": selected,
            "complete": selected is not None, "allowances": adapter.allowances}


def main() -> int:
    checks: list[tuple[str, bool, str]] = []

    def check(name: str, condition: bool, detail: str = "") -> None:
        checks.append((name, bool(condition), detail))
        print(f"  {'ok  ' if condition else 'FAIL'} {name}{'' if condition else '  ' + detail}")

    # the request carries the remaining allowance, and it shrinks as it is spent
    adapter = ScriptedAdapter(["nothing yet", "still wrong", "prints 3"], per_call=100)
    result = run_task(adapter, cap=250)
    check("each model request receives the remaining allowance",
          [entry.allowance for entry in result["allowances"]] == [250, 150, 50],
          str([entry.allowance for entry in result["allowances"]]))

    # exhaustion stops generation rather than issuing another call
    # 140 leaves 40 after one 100-token call: less than the 50 a further request
    # needs, so no further generation is attempted.
    starved = run_task(ScriptedAdapter(["wrong"], per_call=100), cap=140)
    check("exhaustion prevents further generation",
          len(starved["allowances"]) == 1 and starved["envelope"].remaining() == 40
          and starved["complete"] is False,
          f"calls={len(starved['allowances'])} remaining={starved['envelope'].remaining()}")

    # an incomplete candidate cannot enter selection
    check("an incomplete candidate cannot be selected",
          starved["selected"] is None and all(not candidate["passes_public"] for candidate in starved["candidates"]))

    # an overshooting adapter is charged what it actually generated
    overshoot = run_task(OvershootingAdapter(["wrong"], per_call=100), cap=100)
    charged = overshoot["envelope"].spent
    totals = overshoot["envelope"].totals()
    check("overshoot is recorded as actual expenditure, and stops the candidate",
          charged == 160 and totals["overshoot"] == 60 and len(overshoot["allowances"]) == 1
          and overshoot["complete"] is False,
          f"charged={charged} overshoot={totals['overshoot']} calls={len(overshoot['allowances'])}")

    print(f"\n{sum(1 for _, ok, _ in checks if ok)}/{len(checks)} adapter properties demonstrated")
    return 0 if all(ok for _, ok, _ in checks) else 1


if __name__ == "__main__":
    sys.exit(main())
