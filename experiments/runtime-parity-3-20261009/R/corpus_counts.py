#!/usr/bin/env python3
"""Use the complete frozen corpus; keep this lane's receipts under R."""
import pathlib,sys
ROOT=pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'experiments/runtime-parity-3-20261009/tools'))
import ce,corpus_counts
ce.AREA=ROOT/'experiments/runtime-parity-3-20261009/R'
ce.vp3_cells=corpus_counts.complete_cells
ce.main()
