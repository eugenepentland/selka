#!/usr/bin/env python3
"""Apply the inherited natural-loop RC audit to S3's exact 40-row registry.

Caller-visible count stores/checks and opaque runtime/callee sites retain the
inherited audit's separate scopes. This is not a dynamic allocation/count proof.
"""
import argparse
import importlib.util
import json
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]

def module(name,path):
 spec=importlib.util.spec_from_file_location(name,path)
 result=importlib.util.module_from_spec(spec); spec.loader.exec_module(result); return result

def main(argv=None):
 arguments=list(sys.argv[1:] if argv is None else argv)
 parser=argparse.ArgumentParser(add_help=False)
 parser.add_argument('--bin',type=Path)
 parser.add_argument('--rows')
 parser.add_argument('--json',type=Path)
 parser.add_argument('--reuse',action='store_true')
 parser.add_argument('--smoke-test',action='store_true')
 options,_=parser.parse_known_args(arguments)
 rows=module('s3_rows',ROOT/'experiments/new-core-s3-20261006/wave-c/s3-a/measure_all40.py')
 if len(rows.UNITS)!=40: raise RuntimeError('S3 exit requires the complete 40-row registry')
 audit=module('s2_audit',ROOT/'experiments/new-core-s2-20261005/wave-b/integration/audit_all35.py')
 audit.ROWS=rows
 if options.smoke_test or '--help' in arguments or '-h' in arguments:
  return audit.main(arguments)
 if options.bin is None: parser.error('pass --bin explicitly for the fresh final all40 artifacts')
 if options.reuse: parser.error('the S3 exit audit must compile fresh optimized artifacts; omit --reuse')
 selected=rows.row_names(options.rows if options.rows is not None else ','.join(rows.UNITS))
 if set(selected)!=set(rows.UNITS): parser.error('the S3 exit audit requires every one of the 40 registry rows')
 binary=rows.inside(options.bin)
 output=rows.inside(options.json if options.json is not None else binary/'count-audit.json')
 if output.exists(): parser.error('retain the existing audit receipt and choose a fresh output path')
 for row in selected:
  source=binary/'llvm'/f'{rows.stem(row)}.ll'
  if any(source.with_suffix(suffix).exists() for suffix in ('.opt.ll','.s')):
   parser.error('retain existing optimized artifacts and build a fresh final all40 directory')
 status=audit.main(arguments)
 if status: return status
 receipt=json.loads(output.read_text())
 if not receipt.get('valid') or set(receipt.get('rows',{}))!=set(rows.UNITS):
  raise RuntimeError('the emitted count receipt does not qualify the complete 40-row registry')
 return 0
if __name__=='__main__':raise SystemExit(main())
