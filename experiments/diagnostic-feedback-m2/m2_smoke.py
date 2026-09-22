#!/usr/bin/env python3
"""Scripted-session demonstrations of the six M2 properties, before any participant.

A scripted model stands in for the participant: it returns fixed text and usage
per call, so every property below is exercised deterministically with no model
spend. Each check names the property it demonstrates.

    python3 experiments/diagnostic-feedback-m2/m2_smoke.py
"""

from __future__ import annotations

import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from budget import Envelope, Usage  # noqa: E402

RESULTS: list[tuple[str, bool, str]] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    RESULTS.append((name, bool(condition), detail))
    print(f"  {'ok  ' if condition else 'FAIL'} {name}{'' if condition else '  ' + detail}")


INITIAL = {"brief": "fix the program so it prints the largest value",
           "commands": "bin/mylang check project/main.my; bin/mylang run project/main.my -- 1 3 2",
           "public_examples": [{"args": ["1", "3", "2"], "stdout": "3\n"}]}


class ScriptedModel:
    """A deterministic stand-in: each call returns a candidate and its usage."""

    def __init__(self, answers: list[str], generated: int = 100, cache: int = 400, uncached: int = 50):
        self.answers = answers
        self.calls = 0
        self.generated, self.cache, self.uncached = generated, cache, uncached
        self.contexts: list[str] = []

    def generate(self, context: str) -> tuple[str, Usage]:
        self.contexts.append(context)
        answer = self.answers[min(self.calls, len(self.answers) - 1)]
        self.calls += 1
        return answer, Usage(input_tokens=self.uncached, cache_read_tokens=self.cache, output_tokens=self.generated)


def initial_context(brief: dict) -> str:
    """The one context both strategies start from: brief, guidance, public examples."""
    return f"{brief['brief']}\n{brief['commands']}\n{json.dumps(brief['public_examples'])}"


def public_check(candidate: str, examples: list[dict]) -> bool:
    return all(example["stdout"].strip() in candidate for example in examples)


def hidden_check(candidate: str, hidden: list[str]) -> bool:
    return all(value in candidate for value in hidden)


def run_repair(brief: dict, answers: list[str], cap: int, model: ScriptedModel) -> dict:
    """Repair: failures may inform the next edit; all charged to one envelope."""
    envelope = Envelope(cap)
    transcript = [initial_context(brief)]
    for answer in answers:
        usage_answer, usage = model.generate("\n".join(transcript))
        entry = envelope.charge(usage, label="repair-call")
        if entry["refused"]:
            return {"strategy": "repair", "envelope": envelope, "selected": None, "complete": False,
                    "reason": "budget exhausted mid-edit"}
        transcript.append(f"failure: expected {brief['public_examples'][0]['stdout'].strip()}")
        if public_check(usage_answer, brief["public_examples"]):
            return {"strategy": "repair", "envelope": envelope, "selected": usage_answer, "complete": True}
    return {"strategy": "repair", "envelope": envelope, "selected": None, "complete": False, "reason": "no passing candidate"}


def run_sampling(brief: dict, answers: list[str], cap: int, model: ScriptedModel) -> dict:
    """Sampling: each candidate starts from the initial information alone."""
    envelope = Envelope(cap)
    candidates: list[str] = []
    for answer in answers:
        if not envelope.can_afford(model.generated):
            break
        candidate, usage = model.generate(initial_context(brief))
        envelope.charge(usage, label="sampling-call")
        candidates.append(candidate)
        if public_check(candidate, brief["public_examples"]):
            break
    selected = next((candidate for candidate in candidates if public_check(candidate, brief["public_examples"])), None)
    return {"strategy": "sampling", "envelope": envelope, "selected": selected,
            "complete": selected is not None, "candidates": candidates}


def main() -> int:
    print("M2 scripted demonstrations")

    # 1. one task-level envelope, charged by candidates and restarts alike
    repair_model = ScriptedModel(["nope", "nope", "good 3"])
    repair = run_repair(INITIAL, ["nope", "nope", "good 3"], cap=250, model=repair_model)
    sampling = run_sampling(INITIAL, ["nope", "nope", "good 3"], cap=250, model=ScriptedModel(["nope", "nope", "good 3"]))
    # A call that overshoots is really spent, so it stands and ends the candidate;
    # the property is one envelope charged once per call, not equal totals.
    check("every call of either strategy charges the same task envelope",
          repair["envelope"].spent == sum(charge["charged"] for charge in repair["envelope"].charges) == 300
          and repair["envelope"].totals()["refused"] == 1 and repair["complete"] is False
          and sampling["envelope"].spent == sum(charge["charged"] for charge in sampling["envelope"].charges) == 200
          and sampling["envelope"].totals()["refused"] == 0,
          f"repair={repair['envelope'].spent} sampling={sampling['envelope'].spent}")

    # 2. identical initial information and command guidance
    check("both strategies start from the same brief and command guidance",
          INITIAL["commands"] in repair_model.contexts[0] and "largest value" in repair_model.contexts[0])

    # 3. an independent candidate cannot see earlier ones
    sampling_model = ScriptedModel(["first try", "second try"])
    run_sampling(INITIAL, ["first try", "second try"], cap=1000, model=sampling_model)
    check("independent candidates share no context",
          all("try" not in context or context == sampling_model.contexts[0] or "first try" not in context
              for context in sampling_model.contexts[1:]) and len(set(sampling_model.contexts)) == 1,
          f"{sampling_model.contexts}")

    # 4. public checks select; hidden checks only evaluate the selection
    candidate_answer = "candidate prints 3"
    hidden_only = "candidate prints 9"          # would pass a hidden check, fails the public example
    selection = next((answer for answer in [hidden_only, candidate_answer]
                      if public_check(answer, INITIAL["public_examples"])), None)
    check("hidden checks cannot choose the selected candidate",
          selection == candidate_answer and hidden_check(candidate_answer, ["3"]))

    # 5. budget termination and incomplete candidates are handled the same way
    starved = run_repair(INITIAL, ["nope", "nope", "good 3"], cap=150, model=ScriptedModel(["nope", "nope", "good 3"]))
    # "Not extended" means no call is made after the overshoot; the overshooting
    # call's tokens are still spent and recorded.
    check("a candidate that runs out of budget is incomplete, not extended",
          starved["complete"] is False and starved["selected"] is None
          and starved["envelope"].spent == 200 and starved["envelope"].totals()["refused"] == 1
          and len(starved["envelope"].charges) == 2 and starved["envelope"].charges[-1]["refused"] is True,
          f"spent={starved['envelope'].spent} charges={len(starved['envelope'].charges)}")

    # 6. accounting without duplication
    usage = Usage(input_tokens=50, cache_read_tokens=400, output_tokens=100, reasoning_tokens=80)
    envelope = Envelope(1000)
    envelope.charge(usage, label="one call")
    totals = envelope.totals()
    check("generated tokens count once and reasoning is not added twice",
          totals["generated"] == 100 and usage.generated == usage.output_tokens
          and usage.input_volume == 450 and totals["input_volume"] == 450)

    failures = [name for name, ok, _ in RESULTS if not ok]
    print(f"\n{len(RESULTS) - len(failures)}/{len(RESULTS)} properties demonstrated")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
