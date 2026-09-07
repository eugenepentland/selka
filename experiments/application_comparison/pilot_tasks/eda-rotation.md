# Support rotated rectangular footprints

Allow optional component `rotation`: integer 0, 90, 180 or 270 degrees; default 0.
Other values, booleans and floats are invalid-board schema errors. Existing required
fields remain required; unrelated extra fields still reject.

For this placement format, x/y always identify the **top-left of the occupied
axis-aligned box**, including after rotation. Width/height describe the unrotated
footprint. At 90/270 degrees, swap occupied width and height; at 0/180 retain them.
This is not rotation about the origin or the original rectangle center.

Use the occupied box consistently in board-boundary checks, clearance, doubled
component-center calculations/net spans, and SVG rectangle width/height. Keep SVG
serialization format/attribute order unchanged; no transform attribute is needed
for a plain rectangular footprint. The input rotation is not added to the output.
Preserve validation precedence, connectivity and finding order. Unrotated original
inputs retain exactly their previous output. Test asymmetric footprints, odd sizes,
board-edge placement and cases where rotation changes both clearance and net span.
