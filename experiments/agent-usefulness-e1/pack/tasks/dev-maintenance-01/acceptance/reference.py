#!/usr/bin/env python3
"""The independent CPython oracle for the order-tiers rule (dev-maintenance-01).

This is a second implementation of the rule the brief states, written in Python
from the brief rather than from the candidate's mylang source. The acceptance
checker compares the candidate program's printed lines with ``expected_lines()``
here, so a candidate that re-implements the rule differently but behaves
correctly still passes, and a candidate that merely compiles does not.

The rule (brief.md, "The rule as it must now behave"):

* quantity >= 20 -> 500 basis points; quantity >= 5 -> 200 basis points; else 0.
* total_cents = unit_price * quantity less the rate, truncated toward zero.
* small_order is 1 exactly when the rate is 0.
* the band is "top" for >= 20, "mid" for >= 5, "none" otherwise.
* report.line is "<sku> <total_cents> <small_order_flag> <band>".
"""
from __future__ import annotations

TOP_TIER_QUANTITY = 20
MID_TIER_QUANTITY = 5
TOP_TIER_RATE_BPS = 500
MID_TIER_RATE_BPS = 200

RATE_QUANTITIES = (4, 5, 19, 20, 49, 50)
FLAG_QUANTITIES = (4, 5, 19, 20)
BAND_QUANTITIES = (4, 5, 19, 20)
# (unit_price_cents, quantity) for the direct total_cents calls.
TOTAL_ORDERS = ((250, 4), (250, 5), (333, 20), (999, 49))
# (sku, unit_price_cents, quantity) — hidden from the brief and from main.my.
ORDERS = (
    ("H-001", 250, 4),
    ("H-002", 250, 5),
    ("H-003", 333, 20),
    ("H-004", 999, 49),
    ("H-005", 1, 1000),
)


def rate_bps(quantity: int) -> int:
    """The volume discount in basis points for one quantity."""
    if quantity >= TOP_TIER_QUANTITY:
        return TOP_TIER_RATE_BPS
    if quantity >= MID_TIER_QUANTITY:
        return MID_TIER_RATE_BPS
    return 0


def total_cents(unit_price: int, quantity: int) -> int:
    """The discounted order total in whole cents, truncated toward zero."""
    return (unit_price * quantity * (10000 - rate_bps(quantity))) // 10000


def small_order(quantity: int) -> int:
    """1 when the quantity gets no discount, else 0."""
    return 1 if rate_bps(quantity) == 0 else 0


def band(quantity: int) -> str:
    """``top``, ``mid`` or ``none`` for one quantity."""
    if quantity >= TOP_TIER_QUANTITY:
        return 'top'
    if quantity >= MID_TIER_QUANTITY:
        return 'mid'
    return 'none'


def line(sku: str, unit_price: int, quantity: int) -> str:
    """One report line exactly as report.line must compose it."""
    return f'{sku} {total_cents(unit_price, quantity)} {small_order(quantity)} {band(quantity)}'


def expected_lines() -> list[str]:
    """Every line the hidden probe must print, in order."""
    lines = [f'rate {quantity} {rate_bps(quantity)}' for quantity in RATE_QUANTITIES]
    lines += [f'flag {quantity} {small_order(quantity)}' for quantity in FLAG_QUANTITIES]
    lines += [f'band {quantity} {band(quantity)}' for quantity in BAND_QUANTITIES]
    lines += [f'total {quantity} {total_cents(unit_price, quantity)}'
              for unit_price, quantity in TOTAL_ORDERS]
    lines += [line(sku, unit_price, quantity) for sku, unit_price, quantity in ORDERS]
    return lines


if __name__ == '__main__':
    for expected in expected_lines():
        print(expected)
