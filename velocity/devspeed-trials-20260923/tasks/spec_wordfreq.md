## Task: `wordfreq`

Write a command-line program that takes two arguments: a path to a text file (UTF-8)
and a count N.

- A **word** is a maximal run of ASCII letters and digits (`A-Z`, `a-z`, `0-9`). Every
  other byte (spaces, punctuation, apostrophes, non-ASCII characters) separates words.
  Words are compared case-insensitively: lowercase them.
- Print the N most frequent words, one per line, as `<word> <count>`, ordered by count
  descending and then by word ascending (byte order). If there are fewer than N
  distinct words, print them all. Exit status 0.
- N must be a positive integer written with decimal digits only. Otherwise print
  `error: bad count` to standard error and exit with status 2.
- If the file cannot be read, print `error: cannot read <path>` to standard error and
  exit with status 1.
- With the wrong number of arguments, print `usage: wordfreq FILE N` to standard error
  and exit with status 2.
- It must handle a 10 MB input file in well under 10 seconds.
- Include unit tests for the word splitting and the ranking.
