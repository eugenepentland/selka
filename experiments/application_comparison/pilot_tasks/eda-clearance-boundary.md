# Restore exact-clearance acceptance

The inspector has a regression: components exactly at the required clearance are
sometimes reported as violating it. Restore the v1 rule: report when squared
rectangle-gap distance is strictly less than squared clearance, or when interiors
overlap with positive area on both axes. Equality passes.

At zero clearance, touching edges/corners pass but positive-area overlap still
fails. Preserve exact integer micrometer conversion and arithmetic; do not add a
floating-point epsilon or reduce the configured clearance. Keep the result ordering,
net reports, SVG and other validation/design rules unchanged.

