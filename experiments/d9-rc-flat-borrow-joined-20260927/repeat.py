"""Repeat the unchanged schematic process; verify each invocation independently."""
import hashlib,os,subprocess,sys
from pathlib import Path
count=int(sys.argv[1]);expected=sys.argv[2];command=sys.argv[3:]
for _ in range(count):
 run=subprocess.run(command,capture_output=True,check=True)
 assert run.stdout in (b'',b'0\n') and not run.stderr
 output=Path(os.environ['MYLANG_SCHEMATIC_OUTPUT'])
 issue=Path(os.environ['MYLANG_SCHEMATIC_ISSUE'])
 assert hashlib.sha256(output.read_bytes()).hexdigest()==expected
 assert not issue.exists() or not issue.read_bytes()
