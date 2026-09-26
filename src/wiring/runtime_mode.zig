//! Resolved process selection. Production command startup sets it once before
//! checking or native cache lookup; tests restore the prior selection.
const contract = @import("runtime_contract");

/// Experimental RC is disabled until its separate acceptance gate completes.
pub var selection: contract.Selection = .gc;
