# Hot count sites — final

Use only after the counting/output gate qualifies this tag. Totals include inlined source origins. The read_constant execution denominator sums read_constant and read_string function calls, as at M0; if later inlining changes those call boundaries, inspect LLVM and the full count sites before interpreting a per-call ratio.

## Lox

| cell | read_constant executions, including read_string | retains | releases | retains / execution | releases / execution |
|---|---:|---:|---:|---:|---:|
| lox-vm-invocation-1500000 | 97,500,072 | 0 | 0 | 0.000 | 0.000 |
| lox-vm-method_call-500000 | 95,333,377 | 0 | 0 | 0.000 | 0.000 |

The complete nonzero record-copy source-site list for these two cells is in hot-counts.json. U2 can identify the frame sites by path and line rather than treating all record traffic as frames.

## EDA P6

| design | parse_list record-push copied bytes |
|---|---:|
| eda-Cyclops-Flex | 7,707,312 |
| eda-adf5901 | 8,419,920 |
| eda-barracuda-base | 19,137,024 |
| eda-barracuda-via-fence | 15,893,136 |
| eda-barracuda | 17,973,888 |
| eda-black-canyon+flat | 11,910,960 |
| eda-black-canyon | 12,337,008 |
| eda-blinky-breakout | 686,784 |
| eda-cyclops-analog+no-vendor-symbols | 8,118,672 |
| eda-cyclops-analog | 15,403,632 |
| eda-cyclops-breakout | 9,049,632 |
| eda-cyclops-digital-pcb | 15,650,688 |
| eda-cyclops-interposer | 11,583,744 |
| eda-cyclops-kband-breakout | 12,294,960 |
| eda-cyclops-kband-pcb | 12,660,240 |
| eda-cyclops-kband | 14,536,080 |
| eda-cyclops-xband-sip | 11,315,136 |
| eda-dual-flash | 8,195,808 |
| eda-labstation+no-vendor-symbols | 15,110,976 |
| eda-labstation | 22,813,920 |
| eda-lmk05318b-clock | 9,853,968 |
| eda-max860-inverter | 7,902,000 |
| eda-poe-pd-flyback-tps23757 | 9,269,136 |
| eda-rds3+flat | 23,911,344 |
| eda-rds3-rf-selector | 7,973,472 |
| eda-rds3 | 27,653,712 |
| eda-remora-base | 14,430,720 |
| eda-remora-rf | 13,852,752 |
| eda-rf-switch-8way | 8,892,528 |
| eda-rf-switch-eval | 9,339,168 |
| eda-stm32n6 | 18,406,752 |
| eda-straps-base | 18,333,696 |
| eda-straps | 14,343,360 |
| eda-w55rp20 | 9,871,344 |

All 34 designs: **444,833,472 bytes** copied by parse_list record pushes. R4's ≥90% reduction is measured against M0/hot-counts.json and each representative cell. List-growth movement is a separate counter and is not added to P6. Inspect attribution when construction moves to a new site.
