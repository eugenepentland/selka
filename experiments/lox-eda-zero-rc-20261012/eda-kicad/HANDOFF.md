# KiCad and compositor ownership migration

Own scope: 44 export_kicad*/kicad_* modules and tests, excluding export_kicad_sch.my and its test, transferred to the provider worker. render_* transferred to the EVAL worker. Non-owned dependencies are diagnostic snapshots and are excluded from this commit.

Stored/returned borrowed values acquire explicit snapshots; dictionary insertion copies reused keys. Immutable queries keep direct borrowed arguments. Mutating a parent while iterating its fields uses ordered index iteration and an owned entry snapshot, or a local map and final writeback. Computed scalar fields are read before moving their containing record; conditional value swaps delay final moves into their selected branch.

The native lowering boundary for nested child assignment now copies the selected child, changes its rectangle, and publishes the whole child back. This preserves layout arithmetic and child order. composer-child-writeback.patch records this final correction.

Common compiler: e2893d2707cbe057a09abf94e04c4b12d16b7b8b, binary SHA256 6e7938a14ad4abc46b76c149ef12551b170f6c7e6f462beec2f81db18d40a83d. Earlier pass01–04 and solve01 use the older 941 compiler only for diagnostic migration; final source checks and builds use the common compiler.

The source archive/manifest is pre-format. Canonical EDA owner reformats the integration and records its separate final manifest; these hashes must not be mistaken for that final formatted candidate. Root reported all121 source modules checking successfully after integration before the nested child native lowering fix. The compositor and its tests passed standalone common-compiler checking before that lowering fix. Native final310 tests and34 output goldens are owned by the canonical EDA worker. Provider schematic RC control28 passed; pre-fix zero-RC2 passed/26 build failures at the child lowering boundary. These preliminary results are not final native qualification.

Guardian feedback logging is not requested and is not modified.
