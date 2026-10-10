# X gap — final against M0 and paired base

Final/base uses base and final interleaved within each CPU-10 session. M0 columns retain the original baseline comparison. Rows preserve the median of three within-batch ratios after startup subtraction; all other cells use their session medians.

A dash denotes an unavailable reference. Lox, EDA and rows have plain Rust references; they do not establish a checked-Rust result. The available gate tests Zig RS and checked Rust wherever present. Reference-free binary_trees_recursive remains unavailable. Every final/base result above 1.03 requires the separate CPU-8 review.

## Parity

| cell | M0/RS | M0/checked | paired base/RS | final/base | final/RS | final/checked | final/RF | final/Rust | final/Go | limit | available gate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| alloc_churn/my | 0.7522 | 0.6378 | 0.7630 | 1.0023 | 0.7648 | 0.6575 | 0.8274 | 0.6555 | — | 1.1000 | met |
| alloc_churn/my-arena | 0.7583 | 0.6430 | 0.7634 | 1.0019 | 0.7648 | 0.6575 | 0.8275 | 0.6555 | — | 1.1000 | met |
| binary_trees/my | 0.8839 | 0.5693 | 0.8584 | 1.0124 | 0.8691 | 0.5743 | 0.9435 | 0.5902 | — | 1.1000 | met |
| binary_trees/my-arena | 0.8864 | 0.5709 | 0.8611 | 1.0086 | 0.8685 | 0.5739 | 0.9429 | 0.5898 | — | 1.1000 | met |
| binary_trees_recursive/my | — | — | — | 1.0086 | — | — | — | — | — | 1.1000 | unavailable |
| bytes_scan/my | 0.3416 | 0.3059 | 0.3540 | 0.9872 | 0.3495 | 0.2948 | 0.4347 | 1.1852 | — | 1.1000 | met |
| bytes_scan/my-wrapping | 0.3416 | 0.3058 | 0.3549 | 0.9896 | 0.3512 | 0.2963 | 0.4368 | 1.1910 | — | 1.1000 | met |
| calls/my | 0.9939 | 1.2385 | 0.9850 | 1.0004 | 0.9853 | 1.2366 | 1.0093 | 1.2714 | — | 1.1000 | over |
| dict_count/my | 0.2698 | 0.1699 | 0.2732 | 1.0175 | 0.2780 | 0.1711 | 0.3694 | 0.1728 | — | 1.1000 | met |
| fannkuch_redux/my | 0.6783 | 0.8030 | 0.6794 | 0.9984 | 0.6783 | 0.8081 | 0.8105 | 0.7787 | — | 1.1000 | met |
| fannkuch_redux/my-array | 2.6685 | 3.1592 | 2.6777 | 0.2943 | 0.7881 | 0.9388 | 0.9416 | 0.9047 | — | 1.1000 | met |
| fannkuch_redux/my-tuned | 2.2551 | 2.6698 | 2.2419 | 0.3244 | 0.7272 | 0.8663 | 0.8688 | 0.8348 | — | 1.1000 | met |
| fib/my | 0.9123 | 0.8074 | 0.9085 | 1.0070 | 0.9149 | 0.8011 | 1.8501 | 1.6816 | — | 1.1000 | met |
| float_loop/my | 0.9937 | 0.9890 | 1.0046 | 0.9997 | 1.0043 | 0.9970 | 1.0051 | 0.9965 | — | 1.1000 | met |
| intloop/my | 1.0452 | 1.2255 | 1.0272 | 1.0010 | 1.0281 | 1.2158 | 1.0374 | 1.0745 | — | 1.1000 | over |
| knucleotide/my | 0.8845 | 0.7284 | 0.9174 | 1.0049 | 0.9218 | 0.7644 | 1.0365 | 0.7679 | — | 1.1000 | met |
| knucleotide/my-arena | 0.9044 | 0.7448 | 0.9156 | 1.0091 | 0.9239 | 0.7661 | 1.0388 | 0.7697 | — | 1.1000 | met |
| knucleotide/my-tuned | 0.5909 | 0.4866 | 0.6079 | 0.9922 | 0.6032 | 0.5002 | 0.6783 | 0.5025 | — | 1.1000 | met |
| list_append_sum/my | 0.9515 | 0.9055 | 0.9274 | 0.9996 | 0.9271 | 0.8744 | 0.9797 | 0.9156 | — | 1.1000 | met |
| list_records/my | 1.0463 | 1.0086 | 1.0574 | 1.0095 | 1.0675 | 0.9952 | 1.1516 | 1.2218 | — | 1.1000 | met |
| list_records/my-wrapping | 0.8275 | 0.7977 | 0.8571 | 1.0013 | 0.8582 | 0.8001 | 0.9259 | 0.9822 | — | 1.1000 | met |
| mandelbrot/my | 1.0043 | 0.9733 | 1.0022 | 1.0013 | 1.0035 | 0.9740 | 1.0064 | 0.9855 | — | 1.1000 | met |
| matmul/my | 0.3246 | 0.1867 | 0.3380 | 0.9839 | 0.3325 | 0.1795 | 0.5082 | 0.2420 | — | 1.1000 | met |
| matmul/my-flat | 0.3181 | 0.1830 | 0.3245 | 0.9983 | 0.3239 | 0.1749 | 0.4950 | 0.2357 | — | 1.1000 | met |
| matmul/my-tuned | 1.6449 | 0.9461 | 1.6870 | 1.0045 | 1.6946 | 0.9149 | 2.5898 | 1.2333 | — | 1.1000 | over |
| nbody/my | 1.3322 | 1.1591 | 1.3741 | 1.0021 | 1.3770 | 1.1886 | 1.3779 | 1.1898 | — | 1.1000 | over |
| nbody/my-class | 1.3366 | 1.1630 | 1.3741 | 1.0020 | 1.3768 | 1.1885 | 1.3777 | 1.1896 | — | 1.1000 | over |
| raytrace/my | 1.0125 | 1.0581 | 1.0154 | 1.0014 | 1.0168 | 1.0721 | 1.0705 | 1.0903 | — | 1.1000 | met |
| raytrace/my-tuned | 1.0171 | 1.0629 | 1.0157 | 1.0003 | 1.0160 | 1.0713 | 1.0697 | 1.0895 | — | 1.1000 | met |
| records/my | 0.9043 | 1.0901 | 0.9071 | 0.9991 | 0.9063 | 1.1009 | 0.8231 | 0.9828 | — | 1.1000 | over |
| scan_count/my | 0.4766 | — | 0.4815 | 0.8211 | 0.3953 | — | 1.1808 | — | — | 1.1000 | met |
| scan_replace/my | 0.2659 | — | 0.2683 | 0.8669 | 0.2326 | — | 0.4127 | — | — | 1.1000 | met |
| scan_split/my | 1.4040 | — | 1.4260 | 0.3146 | 0.4486 | — | 0.6632 | — | — | 1.1000 | met |
| sieve/my | 0.7894 | 0.8994 | 0.8025 | 0.9970 | 0.8001 | 0.9040 | 1.0804 | 1.0625 | — | 1.1000 | met |
| sieve/my-tuned | 0.7944 | 0.9051 | 0.7990 | 1.0012 | 0.7999 | 0.9038 | 1.0801 | 1.0622 | — | 1.1000 | met |
| sort_builtin/my | 0.4410 | 1.6907 | 0.4368 | 0.3633 | 0.1587 | 0.6172 | 0.1842 | 0.6115 | — | 1.1000 | met |
| sort_quick/my | 0.9763 | 1.1925 | 0.9472 | 0.9982 | 0.9455 | 1.1749 | 1.1188 | 1.1997 | — | 1.1000 | over |
| sort_records/my | 0.2355 | 0.7074 | 0.2322 | 1.0019 | 0.2327 | 0.7119 | 0.2718 | 0.7059 | — | 1.1000 | met |
| sort_records/my-keyed | 0.2331 | 0.7002 | 0.2316 | 1.0044 | 0.2326 | 0.7115 | 0.2716 | 0.7056 | — | 1.1000 | met |
| sort_records/my-sorted | 0.2341 | 0.7032 | 0.2316 | 0.9998 | 0.2315 | 0.7082 | 0.2704 | 0.7023 | — | 1.1000 | met |
| spectral_norm/my | 0.7509 | 0.8720 | 0.7260 | 1.0004 | 0.7263 | 0.8495 | 0.9956 | 0.9981 | — | 1.1000 | met |
| spectral_norm/my-tuned | 0.7351 | 0.8536 | 0.7259 | 1.0014 | 0.7269 | 0.8502 | 0.9964 | 0.9990 | — | 1.1000 | met |
| str_build/my | 0.7727 | 0.8985 | 0.7712 | 1.0023 | 0.7730 | 0.9010 | 0.9752 | 0.9060 | — | 1.1000 | met |
| text_ops/my | 2.6593 | 1.3998 | 2.6482 | 0.6868 | 1.8189 | 0.9609 | 1.4904 | 0.9716 | — | 1.1000 | over |
| text_ops/my-tuned | 0.9080 | 0.4779 | 0.8923 | 1.0493 | 0.9362 | 0.4946 | 0.7671 | 0.5001 | — | 1.1000 | met |

Geomeans: `{"cells": 45, "final_over_base": 0.8921460889527496, "rust": 0.8154952781063312, "rust-checked": 0.7160071977310488, "zig-fast": 0.8080790915701532, "zig-safe": 0.6727736267106788}`.

## Lox

| cell | M0/RS | M0/checked | paired base/RS | final/base | final/RS | final/checked | final/RF | final/Rust | final/Go | limit | available gate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| tree/binary_trees | 0.8623 | — | 0.8764 | 1.0082 | 0.8836 | — | 1.7996 | 1.4239 | 1.2238 | 1.1000 | met |
| tree/closures | 1.0103 | — | 0.9979 | 1.0161 | 1.0140 | — | 1.7077 | 1.1872 | 1.3020 | 1.1000 | met |
| tree/equality | 1.4154 | — | 1.3830 | 0.9913 | 1.3710 | — | 1.5064 | 1.4808 | 1.7898 | 1.1000 | over |
| tree/fib | 0.8565 | — | 0.8581 | 0.9926 | 0.8517 | — | 1.4573 | 0.9999 | 1.2027 | 1.1000 | met |
| tree/instantiation | 0.7196 | — | 0.7415 | 1.0001 | 0.7415 | — | 1.3357 | 1.2203 | 0.9189 | 1.1000 | met |
| tree/invocation | 0.6807 | — | 0.6874 | 1.0242 | 0.7040 | — | 1.2484 | 1.1691 | 0.9113 | 1.1000 | met |
| tree/method_call | 1.0065 | — | 0.9870 | 1.0181 | 1.0049 | — | 1.6442 | 1.4438 | 1.1212 | 1.1000 | met |
| tree/properties | 0.8305 | — | 0.8326 | 1.0129 | 0.8434 | — | 1.4190 | 1.2262 | 1.0640 | 1.1000 | met |
| tree/string_equality | 2.4202 | — | 2.3804 | 0.8943 | 2.1289 | — | 2.6772 | 1.0187 | 2.2958 | 1.1000 | over |
| tree/strings | 0.9481 | — | 0.9588 | 0.9567 | 0.9173 | — | 1.5950 | 1.1224 | 1.2297 | 1.1000 | met |
| tree/trees | 1.0032 | — | 0.9898 | 0.9945 | 0.9844 | — | 1.4938 | 1.4217 | 1.2076 | 1.1000 | met |
| tree/zoo | 0.8212 | — | 0.8167 | 1.0208 | 0.8337 | — | 1.4006 | 1.1043 | 0.9499 | 1.1000 | met |
| tree/zoo_batch | 0.8476 | — | 0.8459 | 1.0168 | 0.8600 | — | 1.3723 | 1.1508 | 0.9658 | 1.1000 | met |
| vm/binary_trees | 0.8975 | — | 0.8880 | 0.9326 | 0.8282 | — | 1.9374 | 1.5261 | 1.2715 | 1.5000 | met |
| vm/closures | 1.3163 | — | 1.3010 | 0.9404 | 1.2235 | — | 1.8088 | 1.4524 | 1.4997 | 1.5000 | met |
| vm/equality | 1.7214 | — | 1.6844 | 0.8198 | 1.3809 | — | 1.4713 | 1.3001 | 1.2625 | 1.5000 | met |
| vm/fib | 1.8784 | — | 1.8464 | 0.9027 | 1.6667 | — | 2.0732 | 1.4988 | 1.8345 | 1.5000 | over |
| vm/instantiation | 1.7597 | — | 1.6954 | 0.9562 | 1.6211 | — | 2.3047 | 1.4050 | 1.2216 | 1.5000 | over |
| vm/invocation | 2.0536 | — | 2.0136 | 0.9284 | 1.8695 | — | 3.1177 | 1.6276 | 1.9324 | 1.5000 | over |
| vm/method_call | 1.8611 | — | 1.8263 | 0.8998 | 1.6433 | — | 2.3078 | 1.5399 | 1.7274 | 1.5000 | over |
| vm/properties | 1.8613 | — | 1.8056 | 0.9155 | 1.6531 | — | 2.5322 | 1.4908 | 1.7106 | 1.5000 | over |
| vm/string_equality | 1.8829 | — | 1.8677 | 0.9755 | 1.8219 | — | 2.3206 | 1.4132 | 1.1367 | 1.5000 | over |
| vm/strings | 0.9055 | — | 0.9184 | 0.8691 | 0.7982 | — | 1.5422 | 1.4122 | 1.2406 | 1.5000 | met |
| vm/trees | 1.6738 | — | 1.6515 | 0.8861 | 1.4633 | — | 2.1645 | 1.4324 | 1.6153 | 1.5000 | met |
| vm/zoo | 1.7770 | — | 1.7375 | 0.9025 | 1.5681 | — | 2.3971 | 1.3682 | 1.6668 | 1.5000 | over |
| vm/zoo_batch | 1.7817 | — | 1.7485 | 0.8950 | 1.5649 | — | 2.2991 | 1.3809 | 1.6647 | 1.5000 | over |

Geomeans: `{"cells": 26, "final_over_base": 0.9510004284898375, "go": 1.3417357686801394, "rust": 1.3280904664290267, "zig-fast": 1.8245449139248315, "zig-safe": 1.173439653882892}`.

## Eda

| cell | M0/RS | M0/checked | paired base/RS | final/base | final/RS | final/checked | final/RF | final/Rust | final/Go | limit | available gate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Cyclops-Flex | 1.1720 | — | 1.1864 | 0.9352 | 1.1095 | — | 1.2311 | 1.0585 | 0.4516 | 1.1000 | over |
| adf5901 | 1.2040 | — | 1.1650 | 0.9438 | 1.0995 | — | 1.2100 | 1.0713 | 0.4697 | 1.1000 | met |
| barracuda | 1.1039 | — | 1.0874 | 0.9585 | 1.0422 | — | 1.1477 | 1.1047 | 0.4596 | 1.1000 | met |
| barracuda-base | 1.0969 | — | 1.0624 | 0.9630 | 1.0231 | — | 1.1249 | 1.0971 | 0.4517 | 1.1000 | met |
| barracuda-via-fence | 1.1413 | — | 1.1047 | 0.9602 | 1.0608 | — | 1.1682 | 1.0991 | 0.4507 | 1.1000 | met |
| black-canyon | 1.0687 | — | 1.0559 | 0.9532 | 1.0065 | — | 1.0899 | 1.0874 | 0.4466 | 1.1000 | met |
| black-canyon+flat | 1.0995 | — | 1.0929 | 0.9540 | 1.0426 | — | 1.1526 | 1.0953 | 0.4456 | 1.1000 | met |
| blinky-breakout | 1.5378 | — | 1.5431 | 0.9529 | 1.4703 | — | 1.6062 | 1.1372 | 0.5445 | 1.1000 | over |
| cyclops-analog | 1.1634 | — | 1.1421 | 0.9578 | 1.0939 | — | 1.2011 | 1.1039 | 0.4361 | 1.1000 | met |
| cyclops-analog+no-vendor-symbols | 1.1733 | — | 1.1434 | 0.9571 | 1.0943 | — | 1.2046 | 1.1199 | 0.4812 | 1.1000 | met |
| cyclops-breakout | 1.2278 | — | 1.2079 | 0.9476 | 1.1446 | — | 1.2671 | 1.0790 | 0.4444 | 1.1000 | over |
| cyclops-digital-pcb | 1.3296 | — | 1.3131 | 0.9722 | 1.2766 | — | 1.4195 | 1.1794 | 0.4959 | 1.1000 | over |
| cyclops-interposer | 1.0796 | — | 1.0663 | 0.9588 | 1.0224 | — | 1.1012 | 1.0909 | 0.4434 | 1.1000 | met |
| cyclops-kband | 1.1529 | — | 1.1423 | 0.9610 | 1.0977 | — | 1.2034 | 1.1094 | 0.4480 | 1.1000 | met |
| cyclops-kband-breakout | 1.0604 | — | 1.0544 | 0.9548 | 1.0068 | — | 1.0931 | 1.0918 | 0.4333 | 1.1000 | met |
| cyclops-kband-pcb | 1.2051 | — | 1.1936 | 0.9617 | 1.1480 | — | 1.2469 | 1.1317 | 0.4733 | 1.1000 | over |
| cyclops-xband-sip | 1.1536 | — | 1.1325 | 0.9534 | 1.0797 | — | 1.1815 | 1.0784 | 0.4330 | 1.1000 | met |
| dual-flash | 1.2224 | — | 1.1844 | 0.9430 | 1.1169 | — | 1.2493 | 1.0602 | 0.3797 | 1.1000 | over |
| labstation | 1.0921 | — | 1.0702 | 0.9707 | 1.0388 | — | 1.1420 | 1.1240 | 0.4571 | 1.1000 | met |
| labstation+no-vendor-symbols | 1.0934 | — | 1.0883 | 0.9748 | 1.0609 | — | 1.1527 | 1.1526 | 0.5039 | 1.1000 | met |
| lmk05318b-clock | 1.1952 | — | 1.1736 | 0.9482 | 1.1128 | — | 1.2346 | 1.0606 | 0.4359 | 1.1000 | over |
| max860-inverter | 1.2425 | — | 1.2345 | 0.9337 | 1.1526 | — | 1.2725 | 1.0493 | 0.4501 | 1.1000 | over |
| poe-pd-flyback-tps23757 | 1.1450 | — | 1.1296 | 0.9409 | 1.0629 | — | 1.1827 | 1.0675 | 0.3788 | 1.1000 | met |
| rds3 | 1.0691 | — | 1.0457 | 0.9708 | 1.0152 | — | 1.1221 | 1.1241 | 0.4664 | 1.1000 | met |
| rds3+flat | 1.2616 | — | 1.2592 | 0.9812 | 1.2355 | — | 1.3566 | 1.1996 | 0.5413 | 1.1000 | over |
| rds3-rf-selector | 1.1676 | — | 1.1608 | 0.9433 | 1.0949 | — | 1.2069 | 1.0536 | 0.4580 | 1.1000 | met |
| remora-base | 1.1540 | — | 1.1306 | 0.9581 | 1.0833 | — | 1.1838 | 1.0866 | 0.4360 | 1.1000 | met |
| remora-rf | 1.1308 | — | 1.1148 | 0.9578 | 1.0678 | — | 1.1870 | 1.1032 | 0.4517 | 1.1000 | met |
| rf-switch-8way | 1.2223 | — | 1.1897 | 0.9387 | 1.1167 | — | 1.2513 | 1.0633 | 0.3812 | 1.1000 | over |
| rf-switch-eval | 1.2254 | — | 1.2031 | 0.9493 | 1.1421 | — | 1.2617 | 1.0725 | 0.4536 | 1.1000 | over |
| stm32n6 | 1.1503 | — | 1.1318 | 0.9656 | 1.0929 | — | 1.2032 | 1.1196 | 0.4461 | 1.1000 | met |
| straps | 1.1498 | — | 1.1417 | 0.9556 | 1.0910 | — | 1.2045 | 1.1078 | 0.4420 | 1.1000 | met |
| straps-base | 1.2689 | — | 1.2496 | 0.9632 | 1.2036 | — | 1.3413 | 1.1668 | 0.4824 | 1.1000 | over |
| w55rp20 | 1.1493 | — | 1.1256 | 0.9482 | 1.0673 | — | 1.1675 | 1.0599 | 0.4339 | 1.1000 | met |

Geomeans: `{"cells": 34, "final_over_base": 0.9554679209062071, "go": 0.4517883427344212, "rust": 1.0995843304989836, "zig-fast": 1.2130752596470171, "zig-safe": 1.1019775282515165}`.

## Rows

| cell | M0/RS | M0/checked | paired base/RS | final/base | final/RS | final/checked | final/RF | final/Rust | final/Go | limit | available gate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| alloc_retained/4096 | 0.4513 | — | 0.4682 | 0.9858 | 0.4595 | — | 0.4893 | 0.4635 | 0.3117 | 1.1000 | met |
| alloc_retained/64 | 0.4584 | — | 0.4582 | 1.0128 | 0.4636 | — | 0.4746 | 0.4418 | 0.3073 | 1.1000 | met |
| alloc_short/4096 | 0.2193 | — | 0.2198 | 0.9822 | 0.2172 | — | 1060.4190 | 0.9441 | 0.5848 | 1.1000 | met |
| alloc_short/64 | 0.2290 | — | 0.2296 | 1.0019 | 0.2300 | — | 20.4939 | 0.9441 | 0.5224 | 1.1000 | met |
| binary_search/4096 | 0.2278 | — | 0.2269 | 0.9664 | 0.2192 | — | 0.5409 | 0.7994 | 0.2910 | 1.1000 | met |
| binary_search/64 | 0.6572 | — | 0.6581 | 0.9984 | 0.6571 | — | 0.6482 | 0.9369 | 0.5365 | 1.1000 | met |
| branch_mixed/4096 | 0.0427 | — | 0.0429 | 0.9965 | 0.0428 | — | 0.0792 | 0.0813 | 0.0475 | 1.1000 | met |
| branch_mixed/64 | 0.0553 | — | 0.0553 | 1.0005 | 0.0553 | — | 0.1083 | 0.1102 | 0.0677 | 1.1000 | met |
| branch_predictable/4096 | 0.0511 | — | 0.0511 | 1.0008 | 0.0512 | — | 0.1236 | 0.1236 | 0.0587 | 1.1000 | met |
| branch_predictable/64 | 0.0627 | — | 0.0625 | 1.0032 | 0.0627 | — | 0.1506 | 0.1527 | 0.0744 | 1.1000 | met |
| buffer_write/4096 | 0.6653 | — | 0.6365 | 1.0004 | 0.6362 | — | — | 0.7587 | 0.8180 | 1.1000 | met |
| buffer_write/64 | 0.6671 | — | 0.6661 | 0.9997 | 0.6659 | — | — | 0.7437 | 0.8230 | 1.1000 | met |
| bytes_scan/4096 | 0.0394 | — | 0.0380 | 1.0158 | 0.0385 | — | 0.0731 | 0.0473 | 0.0514 | 1.1000 | met |
| bytes_scan/64 | 0.1336 | — | 0.1400 | 1.0087 | 0.1419 | — | 0.3078 | 0.2026 | 0.1325 | 1.1000 | met |
| call_direct/4096 | 0.0997 | — | 0.0995 | 1.0015 | 0.0997 | — | 0.1490 | 0.1493 | 0.0895 | 1.1000 | met |
| call_direct/64 | 0.0781 | — | 0.0779 | 1.0013 | 0.0780 | — | 0.1001 | 0.1093 | 0.0760 | 1.1000 | met |
| call_indirect/4096 | 0.0335 | — | 0.0335 | 1.0032 | 0.0336 | — | 0.0503 | 0.0418 | 0.0367 | 1.1000 | met |
| call_indirect/64 | 0.0329 | — | 0.0331 | 0.9931 | 0.0329 | — | 0.0468 | 0.0409 | 0.0357 | 1.1000 | met |
| csv_aggregate/4096 | 1.1255 | — | 1.1163 | 0.9749 | 1.0845 | — | 1.2922 | 0.9740 | 0.8286 | 1.1000 | met |
| csv_aggregate/64 | 1.1316 | — | 1.1274 | 0.9702 | 1.0930 | — | 1.3428 | 1.0077 | 0.8297 | 1.1000 | met |
| dict_lookup/4096 | 0.2957 | — | 0.2967 | 1.0027 | 0.2973 | — | 0.3665 | 0.3693 | 0.4969 | 1.1000 | met |
| dict_lookup/64 | 0.4939 | — | 0.4923 | 1.0001 | 0.4924 | — | 0.9435 | 0.3743 | 0.5476 | 1.1000 | met |
| dict_lookup_str/4096 | 0.3636 | — | 0.3672 | 1.0085 | 0.3714 | — | 0.4714 | 0.3810 | 0.5673 | 1.1000 | met |
| dict_lookup_str/64 | 0.6052 | — | 0.6052 | 1.0023 | 0.6066 | — | 0.7706 | 0.3356 | 0.5611 | 1.1000 | met |
| dict_update/4096 | 0.3491 | — | 0.3491 | 0.9820 | 0.3428 | — | 0.4897 | 0.4551 | 0.3729 | 1.1000 | met |
| dict_update/64 | 0.6099 | — | 0.6065 | 0.9691 | 0.5883 | — | 1.1220 | 0.4558 | 0.3435 | 1.1000 | met |
| dict_update_str/4096 | 0.3857 | — | 0.3871 | 0.9662 | 0.3748 | — | 0.4368 | 0.2978 | 0.4108 | 1.1000 | met |
| dict_update_str/64 | 0.6387 | — | 0.6374 | 0.9666 | 0.6165 | — | 0.8022 | 0.2879 | 0.4069 | 1.1000 | met |
| float_format/4096 | 0.7373 | — | 0.7380 | 1.0150 | 0.7491 | — | — | 0.7467 | 1.1752 | 1.1000 | met |
| float_format/64 | 0.7359 | — | 0.7366 | 1.0101 | 0.7442 | — | — | 0.7854 | 1.1602 | 1.1000 | met |
| float_math/4096 | 0.2402 | — | 0.2404 | 0.9999 | 0.2403 | — | 0.3629 | 0.2244 | 0.2399 | 1.1000 | met |
| float_math/64 | 0.2424 | — | 0.2426 | 0.9990 | 0.2423 | — | 0.3632 | 0.2326 | 0.2457 | 1.1000 | met |
| grid_dp/4096 | 0.7255 | — | 0.7377 | 1.0107 | 0.7456 | — | — | 0.8763 | 0.5895 | 1.1000 | met |
| grid_dp/64 | 0.9441 | — | 0.9433 | 0.9564 | 0.9032 | — | — | 0.9576 | 0.4779 | 1.1000 | met |
| int_format/4096 | 0.2890 | — | 0.2887 | 0.9991 | 0.2884 | — | 0.3272 | 0.9759 | 0.8716 | 1.1000 | met |
| int_format/64 | 0.2873 | — | 0.2881 | 1.0001 | 0.2882 | — | 0.3434 | 0.9378 | 0.8640 | 1.1000 | met |
| int_math/4096 | 0.0457 | — | 0.0456 | 1.0035 | 0.0457 | — | 0.0508 | 0.0626 | 0.0474 | 1.1000 | met |
| int_math/64 | 0.0597 | — | 0.0597 | 0.9996 | 0.0596 | — | 0.0665 | 0.0802 | 0.0619 | 1.1000 | met |
| int_parse/4096 | 0.9359 | — | 0.9303 | 1.0013 | 0.9369 | — | 1.0643 | 1.1515 | 0.2526 | 1.1000 | met |
| int_parse/64 | 1.0468 | — | 1.0463 | 0.9907 | 1.0366 | — | 1.1074 | 1.3131 | 0.2579 | 1.1000 | met |
| json_transform/4096 | 0.9338 | — | 0.9316 | 0.9784 | 0.9105 | — | 1.1803 | 1.4519 | 0.3130 | 1.1000 | met |
| json_transform/64 | 0.9536 | — | 0.9555 | 0.9547 | 0.9122 | — | 1.2042 | 1.3196 | 0.3424 | 1.1000 | met |
| list_append/4096 | 0.5268 | — | 0.5275 | 0.9886 | 0.5223 | — | 1.1701 | 1.0361 | 0.5463 | 1.1000 | met |
| list_append/64 | 0.3949 | — | 0.3920 | 0.9950 | 0.3899 | — | 0.8905 | 0.6437 | 0.4472 | 1.1000 | met |
| list_filter/4096 | 0.6847 | — | 0.6845 | 1.0015 | 0.6852 | — | 0.9690 | 1.2640 | 0.6347 | 1.1000 | met |
| list_filter/64 | 0.5761 | — | 0.5796 | 1.0096 | 0.5848 | — | 0.8704 | 0.8094 | 0.4396 | 1.1000 | met |
| list_scan/4096 | 0.8403 | — | 0.8407 | 1.0003 | 0.8398 | — | 1.0671 | 1.4201 | 1.2345 | 1.1000 | met |
| list_scan/64 | 0.8335 | — | 0.8346 | 0.9993 | 0.8343 | — | 1.0523 | 1.3923 | 1.1287 | 1.1000 | met |
| lox_eval/4096 | 0.3614 | — | 0.3607 | 1.0018 | 0.3611 | — | 0.3672 | 1.1179 | 0.8842 | 1.1000 | met |
| lox_eval/64 | 0.3640 | — | 0.3641 | 1.0006 | 0.3646 | — | 0.3706 | 1.1100 | 0.9609 | 1.1000 | met |
| mutate_nested/4096 | 0.1475 | — | 0.1513 | 1.0696 | 0.1613 | — | 0.1792 | 0.1489 | 0.1548 | 1.1000 | met |
| mutate_nested/64 | 0.1791 | — | 0.1796 | 1.0538 | 0.1899 | — | 0.2108 | 0.1950 | 0.1869 | 1.1000 | met |
| mutate_shared/4096 | 0.6412 | — | 0.6414 | 1.0031 | 0.6470 | — | 0.8998 | 1.0131 | 0.2006 | 1.1000 | met |
| mutate_shared/64 | 0.6516 | — | 0.6521 | 0.9918 | 0.6467 | — | 1.0218 | 0.9892 | 0.1457 | 1.1000 | met |
| mutate_unique/4096 | 0.8598 | — | 0.8600 | 0.9999 | 0.8599 | — | 0.8876 | 1.1056 | 0.9527 | 1.1000 | met |
| mutate_unique/64 | 0.8605 | — | 0.8571 | 1.0001 | 0.8582 | — | 0.8966 | 1.1058 | 0.9649 | 1.1000 | met |
| option_handle/4096 | 0.3068 | — | 0.3047 | 1.0003 | 0.3056 | — | 0.3790 | 0.8321 | 0.3112 | 1.1000 | met |
| option_handle/64 | 0.3421 | — | 0.3407 | 0.9912 | 0.3344 | — | 0.4606 | 0.7846 | 0.3782 | 1.1000 | met |
| packet_decode/4096 | 0.7999 | — | 0.8049 | 0.9757 | 0.7902 | — | 1.7148 | 1.4629 | 0.5415 | 1.1000 | met |
| packet_decode/64 | 0.7679 | — | 0.7957 | 0.9806 | 0.7728 | — | 1.6373 | 1.4191 | 0.5398 | 1.1000 | met |
| record_construct/4096 | 0.2194 | — | 0.2193 | 0.9999 | 0.2193 | — | 0.2603 | 0.3337 | 0.2403 | 1.1000 | met |
| record_construct/64 | 0.2174 | — | 0.2174 | 0.9998 | 0.2174 | — | 0.2621 | 0.3272 | 0.2410 | 1.1000 | met |
| record_pass/4096 | 0.6637 | — | 0.6641 | 0.9998 | 0.6637 | — | — | 1.0213 | 0.2551 | 1.1000 | met |
| record_pass/64 | 0.6834 | — | 0.6821 | 1.0033 | 0.6836 | — | — | 1.0513 | 0.2711 | 1.1000 | met |
| record_reads/4096 | 0.7410 | — | 0.7401 | 1.0007 | 0.7406 | — | 0.8278 | 1.0147 | 0.8506 | 1.1000 | met |
| record_reads/64 | 0.7286 | — | 0.7282 | 1.0002 | 0.7284 | — | 0.7851 | 1.0095 | 0.8414 | 1.1000 | met |
| record_update/4096 | 0.2064 | — | 0.2064 | 1.0002 | 0.2065 | — | 0.2607 | 0.3340 | 0.2369 | 1.1000 | met |
| record_update/64 | 0.2061 | — | 0.2061 | 1.0000 | 0.2061 | — | 0.2622 | 0.3272 | 0.2391 | 1.1000 | met |
| result_propagate/4096 | 0.4802 | — | 0.4811 | 1.0495 | 0.5115 | — | 0.7161 | 1.0326 | 0.4447 | 1.1000 | met |
| result_propagate/64 | 0.4538 | — | 0.4534 | 1.0214 | 0.4631 | — | 0.7241 | 0.8202 | 0.3927 | 1.1000 | met |
| set_dedup/4096 | 0.3016 | — | 0.3016 | 0.9931 | 0.2998 | — | 0.4237 | 0.3878 | 0.3546 | 1.1000 | met |
| set_dedup/64 | 0.7546 | — | 0.7546 | 1.0143 | 0.7660 | — | 1.5118 | 0.4611 | 0.3918 | 1.1000 | met |
| sort_int/4096 | 0.6913 | — | 0.6918 | 0.3985 | 0.2757 | — | 0.3936 | 0.2658 | 0.0777 | 1.1000 | met |
| sort_int/64 | 0.5722 | — | 0.5631 | 2.0829 | 1.1755 | — | 1.9279 | 1.3513 | 0.3093 | 1.1000 | over |
| sort_records/4096 | 0.3217 | — | 0.3280 | 1.0033 | 0.3292 | — | 0.4092 | 0.8463 | 0.0311 | 1.1000 | met |
| sort_records/64 | 0.7338 | — | 0.7335 | 1.0328 | 0.7576 | — | 1.0663 | 0.8595 | 0.0834 | 1.1000 | met |
| string_equal/4096 | 0.1818 | — | 0.1817 | 1.0004 | 0.1817 | — | 0.2314 | 0.3748 | 0.3221 | 1.1000 | met |
| string_equal/64 | 0.8819 | — | 0.9068 | 0.9909 | 0.8936 | — | 0.9242 | 1.1830 | 0.7380 | 1.1000 | met |
| string_join/4096 | 0.2525 | — | 0.2549 | 0.9963 | 0.2533 | — | 0.2708 | 0.3272 | 0.1773 | 1.1000 | met |
| string_join/64 | 0.2685 | — | 0.2684 | 0.9868 | 0.2693 | — | 0.3119 | 0.3738 | 0.2092 | 1.1000 | met |
| string_search/4096 | 0.0325 | — | 0.0325 | 1.0080 | 0.0328 | — | 0.0372 | 0.0759 | 0.1453 | 1.1000 | met |
| string_search/64 | 0.2100 | — | 0.2081 | 0.8517 | 0.1774 | — | 0.2177 | 0.3748 | 0.6343 | 1.1000 | met |
| string_split/4096 | 0.9424 | — | 0.9327 | 0.9513 | 0.8881 | — | 0.9402 | 2.1043 | 0.8736 | 1.1000 | met |
| string_split/64 | 0.9976 | — | 0.9908 | 0.9260 | 0.9176 | — | 0.9862 | 1.7937 | 0.9415 | 1.1000 | met |
| tagged_stack/4096 | 0.6908 | — | 0.6912 | 0.9999 | 0.6912 | — | 0.6848 | 1.2758 | 1.2167 | 1.1000 | met |
| tagged_stack/64 | 0.6920 | — | 0.6919 | 1.0000 | 0.6919 | — | 0.6847 | 1.2753 | 1.2168 | 1.1000 | met |
| tree_build_walk/4096 | 0.6813 | — | 0.6770 | 1.0261 | 0.6947 | — | — | 0.7393 | 0.8789 | 1.1000 | met |
| tree_build_walk/64 | 0.6968 | — | 0.6959 | 0.9983 | 0.6947 | — | — | 0.7649 | 0.9841 | 1.1000 | met |
| union_find/4096 | 1.0900 | — | 1.0914 | 0.9976 | 1.0889 | — | — | 1.0853 | 0.9181 | 1.1000 | met |
| union_find/64 | 0.9488 | — | 0.9477 | 1.0071 | 0.9543 | — | — | 1.0683 | 0.7035 | 1.1000 | met |
| word_count/4096 | 0.7010 | — | 0.6961 | 1.0263 | 0.7144 | — | 0.9092 | 0.5328 | 0.2208 | 1.1000 | met |
| word_count/64 | 0.9099 | — | 0.9134 | 0.9533 | 0.8721 | — | 1.1172 | 0.6641 | 0.2663 | 1.1000 | met |

Geomeans: `{"cells": 92, "final_over_base": 0.9936840435956045, "go": 0.3349992324123585, "rust": 0.5286097427444278, "zig-fast": 0.5231217270552224, "zig-safe": 0.36845568658783584}`.

## Remaining cells and next levers

- **eda/Cyclops-Flex** (over): Coordinator review pending; no final next-lever claim yet.
- **eda/blinky-breakout** (over): Coordinator review pending; no final next-lever claim yet.
- **eda/cyclops-breakout** (over): Coordinator review pending; no final next-lever claim yet.
- **eda/cyclops-digital-pcb** (over): Coordinator review pending; no final next-lever claim yet.
- **eda/cyclops-kband-pcb** (over): Coordinator review pending; no final next-lever claim yet.
- **eda/dual-flash** (over): Coordinator review pending; no final next-lever claim yet.
- **eda/lmk05318b-clock** (over): Coordinator review pending; no final next-lever claim yet.
- **eda/max860-inverter** (over): Coordinator review pending; no final next-lever claim yet.
- **eda/rds3+flat** (over): Coordinator review pending; no final next-lever claim yet.
- **eda/rf-switch-8way** (over): Coordinator review pending; no final next-lever claim yet.
- **eda/rf-switch-eval** (over): Coordinator review pending; no final next-lever claim yet.
- **eda/straps-base** (over): Coordinator review pending; no final next-lever claim yet.
- **lox/tree/equality** (over): Coordinator review pending; no final next-lever claim yet.
- **lox/tree/string_equality** (over): Coordinator review pending; no final next-lever claim yet.
- **lox/vm/fib** (over): Coordinator review pending; no final next-lever claim yet.
- **lox/vm/instantiation** (over): Coordinator review pending; no final next-lever claim yet.
- **lox/vm/invocation** (over): Coordinator review pending; no final next-lever claim yet.
- **lox/vm/method_call** (over): Coordinator review pending; no final next-lever claim yet.
- **lox/vm/properties** (over): Coordinator review pending; no final next-lever claim yet.
- **lox/vm/string_equality** (over): Coordinator review pending; no final next-lever claim yet.
- **lox/vm/zoo** (over): Coordinator review pending; no final next-lever claim yet.
- **lox/vm/zoo_batch** (over): Coordinator review pending; no final next-lever claim yet.
- **parity/binary_trees_recursive/my** (unavailable): Coordinator review pending; no final next-lever claim yet.
- **parity/calls/my** (over): Coordinator review pending; no final next-lever claim yet.
- **parity/intloop/my** (over): Coordinator review pending; no final next-lever claim yet.
- **parity/matmul/my-tuned** (over): Coordinator review pending; no final next-lever claim yet.
- **parity/nbody/my** (over): Coordinator review pending; no final next-lever claim yet.
- **parity/nbody/my-class** (over): Coordinator review pending; no final next-lever claim yet.
- **parity/records/my** (over): Coordinator review pending; no final next-lever claim yet.
- **parity/sort_quick/my** (over): Coordinator review pending; no final next-lever claim yet.
- **parity/text_ops/my** (over): Coordinator review pending; no final next-lever claim yet.
- **rows/sort_int/64** (over): Coordinator review pending; no final next-lever claim yet.
