# Common-002 assessment

The target remains incomplete: four of six cells have paired confidence intervals below one against every foreign arm. JSON large is uncertain against Rust; JSON small remains above Rust. All samples are retained.

| Cell | Candidate / original C0 | Candidate / common-001 | Closest foreign comparison | All foreign upper bounds below 1 |
| --- | --- | --- | --- | --- |
| csv_aggregate/large | 0.6726 [0.6587, 0.6830] | 0.9466 [0.9288, 0.9717] | zig-fast: 0.8684 [0.8573, 0.8892] | True |
| csv_aggregate/small | 0.6756 [0.6656, 0.6892] | 0.9844 [0.9672, 0.9988] | zig-fast: 0.9725 [0.9616, 0.9926] | True |
| json_transform/large | 0.4823 [0.4697, 0.4920] | 0.9521 [0.9271, 0.9635] | rust: 1.0145 [0.9333, 1.0285] | False |
| json_transform/small | 0.5069 [0.5025, 0.5132] | 0.9423 [0.9335, 0.9621] | rust: 1.0359 [1.0111, 1.0577] | False |
| string_split/large | 0.4039 [0.3996, 0.4086] | 0.9987 [0.9915, 1.0058] | rust: 0.9686 [0.9561, 0.9816] | True |
| string_split/small | 0.4071 [0.4022, 0.4090] | 0.9981 [0.9872, 1.0014] | rust: 0.8474 [0.8399, 0.8579] | True |
