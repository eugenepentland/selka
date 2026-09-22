#!/usr/bin/env python3
"""A task-level budget envelope, shared by both strategies and every candidate.

The unit is *generated tokens* (completion tokens, with reasoning counted once
because the provider reports reasoning inside completion). Input volume is
recorded separately as cached + uncached, and never charged twice: the provider's
`inputTokens` already excludes cache hits, so input volume is their sum.

An envelope is per task and repetition, not per candidate. A repair session, each
independent candidate, every restart and the selection step all charge the same
envelope, and a charge that would exceed the cap is refused rather than truncated
— an incomplete candidate is finished as incomplete, never extended.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class Usage:
    """One model call's usage, normalized without duplication."""
    input_tokens: int = 0          # excludes cache hits, as the provider reports it
    cache_read_tokens: int = 0
    output_tokens: int = 0         # includes reasoning tokens
    reasoning_tokens: int = 0      # a detail of output_tokens

    @property
    def input_volume(self) -> int:
        return self.input_tokens + self.cache_read_tokens

    @property
    def generated(self) -> int:
        return self.output_tokens

    def as_dict(self) -> dict:
        return {"input_tokens": self.input_tokens, "cache_read_tokens": self.cache_read_tokens,
                "input_volume": self.input_volume, "output_tokens": self.output_tokens,
                "reasoning_tokens": self.reasoning_tokens, "generated": self.generated}


@dataclass
class Envelope:
    cap: int
    spent: int = 0
    charges: list[dict] = field(default_factory=list)

    def remaining(self) -> int:
        return self.cap - self.spent

    def can_afford(self, amount: int) -> bool:
        return amount <= self.remaining()

    def charge(self, usage: Usage, label: str, allowance: int | None = None) -> dict:
        """Charge one call with what it actually generated.

        A call that overshoots the allowance it was given cannot be un-spent, so
        the charge stands and the overshoot is recorded. The caller must treat a
        nonzero overshoot as the end of the candidate: refusing the charge and
        retrying would spin, because the budget is already gone.
        """
        amount = usage.generated
        overshoot = max(0, amount - allowance) if allowance is not None else max(0, amount - self.remaining())
        self.spent += amount
        entry = {"label": label, "requested": amount, "charged": amount, "allowance": allowance,
                 "overshoot": overshoot, "refused": overshoot > 0, "usage": usage.as_dict()}
        self.charges.append(entry)
        return entry

    def totals(self) -> dict:
        return {"cap": self.cap, "spent": self.spent, "remaining": self.remaining(),
                "charges": len(self.charges), "refused": sum(1 for charge in self.charges if charge["refused"]),
                "overshoot": sum(charge["overshoot"] for charge in self.charges),
                "input_volume": sum(charge["usage"]["input_volume"] for charge in self.charges),
                "generated": self.spent}
