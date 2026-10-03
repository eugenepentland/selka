#!/usr/bin/env python3
"""Own the replay prefix and pin QBE without touching the selected prefix."""
from pathlib import Path
import hashlib, json, shutil

lane = Path(__file__).resolve().parents[2]
work = lane / '.tmp-lox-native-policy-20261003'
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
frozen = json.loads((work / 'frozen-source-v2.json').read_text())
assert all(sha(lane / p) == h for p, h in frozen['core'].items())
trial, final = work / 'compiler-trial-v2', work / 'compiler-final-v2'
assert not final.exists()
assert not any(p.is_symlink() for p in trial.rglob('*'))
selected = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release')
def mapping(root):
    return {str(p.relative_to(root)): sha(p) for sub in ['bin', 'lib']
            for p in sorted((root / sub).rglob('*')) if p.is_file()}
before = mapping(selected)
qbe = selected / 'bin/qbe'
assert sha(qbe) == '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
shutil.copytree(trial, final)
shutil.copyfile(qbe, final / 'bin/qbe')
assert not any(p.is_symlink() for p in final.rglob('*'))
assert mapping(selected) == before
descriptor = dict(compiler=str(final / 'bin/mylang'), compiler_sha256=sha(final / 'bin/mylang'),
                  qbe=str(final / 'bin/qbe'), qbe_sha256=sha(final / 'bin/qbe'),
                  owned_final_prefix=mapping(final), trial_install_prefix=mapping(trial),
                  no_symlinks=True, complete_source_descriptor_sha256=sha(work / 'frozen-source-v2.json'),
                  selected_prefix_unchanged=before)
(work / 'compiler-final-v2.json').write_text(json.dumps(descriptor, indent=2) + '\n')
print('Fresh owned replay prefix frozen', descriptor['compiler_sha256'])
