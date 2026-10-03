from pathlib import Path
import hashlib
lane=Path(__file__).resolve().parents[2];work=lane/'.tmp-lox-native-policy-20261003'
prefixes=[work/'compiler-final',Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release')]
def snapshot():
 out={}
 for root in prefixes:
  assert root.is_dir(),root
  out[str(root)]={str(f.relative_to(root)):hashlib.sha256(f.read_bytes()).hexdigest() for sub in ['bin','lib'] for f in sorted((root/sub).rglob('*')) if f.is_file()}
 return out
