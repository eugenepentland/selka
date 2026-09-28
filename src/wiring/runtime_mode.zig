//! Resolved process selection. Production command startup sets it once before
//! checking or native cache lookup; tests restore the prior selection.
const contract = @import("runtime_contract");

/// Starts at the process default (`RC-DEFAULT-1`), which is what an empty
/// `MYLANG_RUNTIME` decodes to, so in-process emission and native linking agree.
pub var selection: contract.Selection = contract.default;
