# Checked project documentation (internals)

Implementation detail moved out of the user guide, verbatim, under the same headings.

## Generate and check the overview

The summary's flat module table names each module's purpose (its docstring's
first sentence), imports, public declaration count and private function count.
Each public-declaration row carries the linked name, the first sentence of its
docstring, and compact markers: `mut` when the function writes a parameter, each
capability it holds, and `fails E`. It is built from declarations and syntax, so
it can be generated before every body checks. Private declarations are counted in
the module table; their implementations are never shown.

Empty facts are never printed. A fact appears only when it has content, so
`Status: implemented` is gone, `Contracts: none` and `Tested directly by: none`
do not exist, a hole reads `hole`, and an absent section is omitted rather than
announced. Signatures, full docstrings, examples, field tables, tests and
per-declaration decisions live in the reference, which keeps the summary close to
a tenth of the project's source lines. A body-only change to a non-test function
changes neither output. A direct test call, docstring, example, hole or decision
change changes one of them; a reference-only edit still fails `--check`.
