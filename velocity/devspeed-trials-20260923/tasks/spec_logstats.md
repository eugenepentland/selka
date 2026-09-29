## Task: `logstats`

Write an access-log summarizer. Arguments: a log file path and a count K.

- Each non-blank line should have exactly this shape (single spaces between fields):
  `IP IDENT USER [TIMESTAMP] "METHOD PATH PROTOCOL" STATUS BYTES DURATION`
  - IP, IDENT, USER, METHOD, PATH and PROTOCOL are non-empty runs of non-space
    characters; TIMESTAMP is any non-empty text without `]`;
  - STATUS is exactly three decimal digits whose first digit is 1–5;
  - BYTES is decimal digits or `-` (meaning 0); DURATION (milliseconds) is decimal
    digits; nothing may follow DURATION.
  Example: `10.0.0.1 - - [10/Oct/2026:13:55:36 +0000] "GET /index HTTP/1.1" 200 512 12`
- A non-blank line that does not match is **malformed**: count it and skip it. Blank
  lines are ignored entirely. Lines end with `\n` or `\r\n`; the last may lack one.
- Print, in this order:
  ```
  lines <non-blank lines>
  malformed <malformed lines>
  status 1xx=<n> 2xx=<n> 3xx=<n> 4xx=<n> 5xx=<n>
  path <PATH> count=<n> p50=<ms> p95=<ms> bytes=<total>     (one line per path)
  top_ip <IP> <n>                                          (at most K lines)
  ```
  Path lines are ordered by count descending, then path ascending (byte order). p50 and
  p95 use the nearest-rank method over that path's durations: sort ascending and take
  the element at 1-based rank ceil(p/100 × n). top_ip lines are the K most frequent
  IPs by count descending, then IP ascending as a string (byte order).
- K must be a positive integer written with decimal digits only; otherwise print
  `error: bad k` to standard error and exit with status 2.
- If the file cannot be read, print `error: cannot read <path>` to standard error and
  exit with status 2. With the wrong number of arguments, print
  `usage: logstats FILE K` to standard error and exit with status 2.
- A 500,000-line log must be summarized in well under 10 seconds.
- Include unit tests for line parsing and the percentile computation.
