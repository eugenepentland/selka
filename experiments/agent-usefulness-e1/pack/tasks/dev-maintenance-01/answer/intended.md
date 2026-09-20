# The intended answer — held separately from the brief

The rule change is one edit in each of three modules, and the three boundaries
are spelled differently, so a solver that greps for one spelling finds only one
site:

| File | Old | New |
| --- | --- | --- |
| `tiers.my` | `if quantity >= 50: return 500` / `if quantity >= 10: return 200` | `>= 20` / `>= 5` |
| `bands.my` | `if quantity >= 50: return "top"` / `if quantity >= 10: return "mid"` | `>= 20` / `>= 5` |
| `audit.my` | `if quantity < 10: return 1` | `if quantity < 5: return 1` |

`orders.my`, `report.my` and `main.my` need no edit: `total_cents` reads the rate
from `tiers`, and `report.line` composes the same four fields. A solver that
instead centralises the boundaries (for example by making `audit.small_order`
and `bands.name` derive from `tiers.rate_bps`) also passes: the acceptance check
is behavioural and never inspects which lines changed.

`files/` mirrors the project layout; the reference solver copies every file in
it over the candidate tree.
