# Validate driver and input roles

Each component may optionally contain `pin_roles`: at most 32 objects, each having
exactly `pin` (a declared pin identifier on that component) and `role` (one of
`passive`, `input`, `output`). Unlisted pins default to passive. Repeated assignments,
unknown local pins, unsupported roles or incorrect fields/types are invalid-board
schema errors. All original component fields remain required and other extras reject.

After successful v1 reference validation, add these findings per net:

- `multiple-drivers`, subjects [net ID], when at least two member pins are outputs.
- `undriven-input-net`, subjects [net ID], when any member pin is an input and none
  is an output. A passive pin does not count as a driver.

Emit at most one of each finding per net and merge findings using the existing
code/subjects ordering. Preserve existing underconnected/unconnected findings,
geometry rules, net member/span reports and SVG exactly. Do not infer electrical
roles from names or report a net-rule finding for a pin that belongs to no net.
Original inputs, with no roles specified, must produce exactly their v1 results.
