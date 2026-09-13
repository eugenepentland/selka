#!/usr/bin/env python3
"""Native file-surface parity: handles, whole-path helpers and command-line grants."""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from qbe_parity import ROOT, signature

GREETING = 'hello from a granted directory\n'
LINES = 'one\ntwo\nthree\n'


def cases():
    # Handles, whole-path reads and the documented error text.
    yield '''def count(fs: Filesystem) -> Result[int, str]:
    total = 0
    with open(fs, "lines.txt", "r")? as f:
        for line in f.readlines():
            total = total + 1
    return Ok(total)

def main(fs: Filesystem) -> int:
    print(read_text(fs, "greeting.txt"))
    print(exists(fs, "greeting.txt"), exists(fs, "absent.txt"))
    with open(fs, "greeting.txt", "rb") as f:
        print(f.read())
    match count(fs):
        case Ok(value):
            print(value)
        case Err(message):
            print(message)
    print(read_file(fs, "absent.txt"))
    return 0
''', []
    # Writing, appending, partial reads, explicit close, directories.
    yield '''def main(fs: Filesystem) -> int:
    print(write_text(fs, "out.txt", "first\\nsecond\\n"))
    with open(fs, "out.txt", "a") as f:
        print(f.write("third\\n"))
    print(read_text(fs, "out.txt"))
    with open(fs, "out.txt", "r") as f:
        print(f.readline(), f.read(3), f.read())
        f.flush()
        f.close()
    print(write_file(fs, "raw.bin", b"\\x00\\x01\\xff"))
    print(read_file(fs, "raw.bin"))
    print(mkdir(fs, "nested"), write_text(fs, "nested/inner.txt", "x"))
    print(read_text(fs, "nested/inner.txt"), exists(fs, "nested"))
    print(remove(fs, "nested/inner.txt"), remove(fs, "nested"), exists(fs, "nested"))
    print(remove(fs, "missing.txt"))
    print(write_text(fs, "out.txt", "again\\n"), read_text(fs, "out.txt"))
    return 0
''', []
    # A listing names every entry; order is the filesystem's, so compare the set.
    yield '''def main(fs: Filesystem) -> int:
    match listdir(fs, "."):
        case Ok(names):
            found = 0
            for name in names:
                if name == "greeting.txt" or name == "lines.txt":
                    found += 1
            print(len(names), found)
        case Err(message):
            print(message)
    print(listdir(fs, "absent"))
    return 0
''', []
    # A restricted run denies traversal and every writing mode without a grant.
    yield '''def main(fs: Filesystem) -> int:
    print(read_text(fs, "greeting.txt"))
    print(read_text(fs, "../escape"))
    print(write_text(fs, "new.txt", "x"))
    print(mkdir(fs, "fresh"))
    print(remove(fs, "greeting.txt"))
    return 0
''', ['--restrict', '--allow-read=.']
    # A restricted write grant permits the whole writing surface.
    yield '''def main(fs: Filesystem) -> int:
    print(write_text(fs, "kept.txt", "value"))
    print(read_text(fs, "kept.txt"))
    print(remove(fs, "kept.txt"))
    return 0
''', ['--restrict', '--allow-write=.']
    # A restricted run with no filesystem grant refuses the entry point.
    yield '''def main(fs: Filesystem) -> int:
    print(exists(fs, "greeting.txt"))
    return 0
''', ['--restrict']
    # `with open(...)` traps when the file cannot be opened.
    yield '''def main(fs: Filesystem) -> int:
    with open(fs, "absent.txt", "r") as f:
        print(f.read())
    return 0
''', []
    # A method on a closed handle traps with R_FILE.
    yield '''def main(fs: Filesystem) -> int:
    with open(fs, "greeting.txt", "r") as f:
        f.close()
        print(f.read())
    return 0
''', []
    # `?` propagation and loop exits both leave the scope closed exactly once.
    yield '''def first(fs: Filesystem, path: str) -> Result[int, str]:
    with open(fs, path, "r")? as f:
        return Ok(len(f.readline()))

def main(fs: Filesystem) -> int:
    total = 0
    for round in range(4):
        with open(fs, "lines.txt", "r") as f:
            if round == 1:
                continue
            if round == 3:
                break
            total = total + len(f.readline())
    match first(fs, "greeting.txt"):
        case Ok(value):
            total = total + value
        case Err(message):
            total = total - len(message)
    match first(fs, "absent.txt"):
        case Ok(value):
            print(value)
        case Err(message):
            print(message)
    print(total)
    return 0
''', []
    # A file scope nested inside an arena releases both resources.
    yield '''def main(fs: Filesystem) -> int:
    kept: list[str] = []
    with arena() as scratch:
        with open(fs, "lines.txt", "r") as f:
            lines = f.readlines()
            kept = scratch.escape(lines)
    print(len(kept), kept[0])
    return 0
''', []
    # A grant naming a directory that cannot be opened refuses the whole run.
    yield '''def main(fs: Filesystem) -> int:
    print(exists(fs, "greeting.txt"))
    return 0
''', ['--restrict', '--allow-read=absent-directory']
    # A repeated authority option is a command-line usage error.
    yield '''def main() -> int:
    return 7
''', ['--allow-clock', '--allow-clock']
    # Unrestricted runs grant every capability without naming one.
    yield '''def main(fs: Filesystem, clock: Clock, entropy: Entropy, names: Environment) -> int:
    print(exists(fs, "greeting.txt"))
    return 0
''', []
    # A text handle rejects bytes that are not valid UTF-8.
    yield '''def main(fs: Filesystem) -> int:
    print(write_file(fs, "broken.bin", b"\\xff\\xfe"))
    print(read_text(fs, "broken.bin"))
    print(read_file(fs, "broken.bin"))
    print(remove(fs, "broken.bin"))
    return 0
''', []


def prepare(directory):
    """Materialise the fixture tree every case reads from."""
    (directory / 'greeting.txt').write_text(GREETING)
    (directory / 'lines.txt').write_text(LINES)


def run(command, cwd):
    return subprocess.run(list(map(str, command)), capture_output=True, timeout=180, cwd=cwd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--qbe', default='qbe')
    parser.add_argument('--zig', default='zig')
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    with tempfile.TemporaryDirectory(prefix='mylang-qbe-files-') as directory:
        temp = Path(directory)
        source, output = temp / 'case.my', temp / 'program'
        count = 0
        for text, options in cases():
            source.write_text(text)
            built = run([sys.executable, ROOT / 'scripts/qbe.py', source, '-o', output,
                         '--compiler', compiler, '--qbe', args.qbe, '--zig', args.zig,
                         '--cache-dir', temp / 'cache'], None)
            assert built.returncode == 0, (text, built.stderr.decode())
            outcomes = []
            for command in ([compiler, 'run', source, '--print-result', *options], [output, *options]):
                work = temp / 'work'
                shutil.rmtree(work, ignore_errors=True)
                work.mkdir()
                prepare(work)
                outcomes.append(signature(run(command, work)))
            assert outcomes[0] == outcomes[1], (text, options, outcomes)
            count += 1
    print(f'QBE file surface parity: {count} cases passed')


if __name__ == '__main__':
    main()
