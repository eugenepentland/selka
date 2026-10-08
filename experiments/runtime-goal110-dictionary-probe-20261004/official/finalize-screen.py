from pathlib import Path
import sys,json,argparse
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'benchmarks/runtime'));import runner
sys.path.insert(0,str(ROOT/'benchmarks/runtime/expanded'));from verify import verify
p=argparse.ArgumentParser();p.add_argument('--raw',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();report=json.loads(a.raw.read_text());assert report.pop('analysis_pending') is True and report['summary']==[];report['summary']=runner.summarize(report);report['raw_capture']={'path':str(a.raw.resolve()),'sha256':runner.digest(a.raw)};verify(report,artifacts=True,focused=True)
with a.output.open('x') as out:out.write(json.dumps(report,indent=2)+'\n')
print('PASS finalized six-arm raw report with artifact checks')
