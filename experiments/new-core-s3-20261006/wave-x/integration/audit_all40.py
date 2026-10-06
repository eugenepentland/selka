#!/usr/bin/env python3
"""Apply the inherited natural-loop RC audit to S3's exact 40-row registry.

Caller-visible count stores/checks and opaque runtime/callee sites retain the
inherited audit's separate scopes. This is not a dynamic allocation/count proof.
"""
import importlib.util
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]

def module(name,path):
 spec=importlib.util.spec_from_file_location(name,path)
 result=importlib.util.module_from_spec(spec); spec.loader.exec_module(result); return result

def main():
 rows=module('s3_rows',ROOT/'experiments/new-core-s3-20261006/wave-c/s3-a/measure_all40.py')
 if len(rows.UNITS)!=40: raise RuntimeError('S3 exit requires the complete 40-row registry')
 audit=module('s2_audit',ROOT/'experiments/new-core-s2-20261005/wave-b/integration/audit_all35.py')
 audit.ROWS=rows
 return audit.main()
if __name__=='__main__':raise SystemExit(main())
