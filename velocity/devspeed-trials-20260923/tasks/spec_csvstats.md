## Task: `csvstats`

Write a CSV summarizer. Arguments: a CSV file, the name of a grouping column and the
name of a numeric column.

- The first record is the header. Fields are separated by commas. A field may be
  enclosed in double quotes; inside quotes, commas and line breaks are literal and `""`
  stands for one `"`. Records end with `\n` or `\r\n`; the last record may lack a line
  terminator. Quotes are only special at the start of a field.
- If either column name is not in the header, print `error: no column 'NAME'` to
  standard error and exit with status 2 (check the grouping column first).
- Data records are numbered from 1 (the header is not counted). A record with a
  different number of fields than the header: print
  `error: row R: expected K fields` (K = header field count) to standard error, exit 1.
- The numeric field matches `-?[0-9]+(\.[0-9]+)?`. An empty numeric field means the
  record is skipped. Anything else: print `error: row R: bad number 'TEXT'` to standard
  error and exit with status 1.
- For each distinct value of the grouping column, in order of first appearance among
  the non-skipped records, print one line:
  `GROUP: count=N sum=S mean=M min=A max=B`
  where S, M, A and B are computed with 64-bit floating point and printed with exactly
  two digits after the decimal point, rounded as C's `printf("%.2f")` does.
- Errors are detected in record order; nothing is printed to standard output if an
  error occurs.
- If the file cannot be read, print `error: cannot read <path>` to standard error and
  exit with status 2. With the wrong number of arguments, print
  `usage: csvstats FILE GROUP VALUE` to standard error and exit with status 2.
- A 200,000-record file must be summarized in well under 10 seconds.
- Include unit tests for the CSV parsing and the statistics.
