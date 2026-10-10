#!/usr/bin/env python3
"""Force the old fixture's open-before-write window without scheduling guesses."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    writer_code = (
        'import json,sys\n'
        'with open(sys.argv[1],"w") as stream:\n'
        ' print("opened",flush=True)\n'
        ' sys.stdin.readline()\n'
        ' stream.write(json.dumps({"middle":1,"leaf":2}))\n'
    )
    reader_code = 'import json,sys; json.load(open(sys.argv[1]))'
    with tempfile.TemporaryDirectory(prefix='worker-readiness-repro-') as temporary:
        path = Path(temporary) / 'ready.json'
        writer = subprocess.Popen([sys.executable, '-c', writer_code, str(path)],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True)
        try:
            assert writer.stdout.readline().strip() == 'opened'
            assert path.exists() and path.read_bytes() == b''
            reader = subprocess.run([sys.executable, '-c', reader_code, str(path)],
                                    capture_output=True, text=True, timeout=5)
            writer.communicate('publish\n', timeout=5)
            result = {
                'version': 1,
                'legacy_public_path_existed_before_write': True,
                'legacy_reader_status': reader.returncode,
                'legacy_reader_error': reader.stderr,
                'closed_file_json': json.loads(path.read_text()),
                'meaning': 'Existence polling permits the native fixture reader to observe empty JSON.',
            }
            assert reader.returncode != 0 and 'JSONDecodeError' in reader.stderr
            Path(__file__).with_suffix('.json').write_text(json.dumps(result, indent=2) + '\n')
        finally:
            if writer.poll() is None:
                writer.kill()
            writer.wait(timeout=5)


if __name__ == '__main__':
    main()
