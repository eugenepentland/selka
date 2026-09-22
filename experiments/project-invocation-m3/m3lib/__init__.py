"""Coordinator-side modules for the M3 project-invocation experiment.

`m3.py` is the runner described by the runbook; this package holds the pieces
that runner needs and nothing that a participant may read as a solution:
frozen-pack materialization, workspace construction, sealed grading, replay and
scoring. Nothing in here launches a model session except through `m3.py run`.
"""
