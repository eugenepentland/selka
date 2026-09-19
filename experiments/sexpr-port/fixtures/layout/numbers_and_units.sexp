; Numeric formatting stress: integers, decimals, mm/mil measures and SI-scaled
; literals, plus a form whose 72-column fit depends on the source spelling.
(integers 0 -5 42 2147483647 -2147483648)
(decimals 0.0 -0.0 1.0 -1.0 0.5 0.1 3.14159 1000000.0 0.000001 0.0000001 123456789.0 1000000000000.0)
(measures 1mm 10mil 2.5mm 0.0254mm 0.5mil 100mil)
(si 220k 4.7k 1M 2G 10u 100n 22p 100nF 1uH 10mA 3.3V 47R 10% 0.1%)
(width-check (aaaaaaaaaa 220k 100nF 4.7k 3.3V 10mA 5% 2.5mm bbbbbbbbbb cccccccccc))
