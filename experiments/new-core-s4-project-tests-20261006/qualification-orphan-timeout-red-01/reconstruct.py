"""Invert the recorded supervisor patch; publish only on exact pre-repair SHA match."""
import hashlib
from pathlib import Path

area = Path(__file__).resolve().parent
source = (area.parent / "qualification-source-freeze-06/qualification_support.py.txt").read_text()
start = source.index("\ndef child_pids():")
end = source.index("\nclass Capture:", start)
source = source[:start] + source[end:]
source = source.replace('''        options["cwd"] = str(options.get("cwd") or self.cwd)
        options.pop("start_new_session", None)
        environment = options.pop("env", None)
        stdin = options.pop("stdin", None)
        input_pipe = stdin == subprocess.PIPE
''', '''        options["cwd"] = options.get("cwd", self.cwd)
        options["start_new_session"] = True
''')
start = source.index("        command = argv if isinstance(argv, str)")
end = source.index('        receipt = {"argv": argv', start)
source = source[:start] + '''        began, timed_out = time.monotonic(), False
        with subprocess.Popen(argv, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT if err == subprocess.STDOUT else subprocess.PIPE,
                              **options) as process:
            try:
                stdout, stderr = process.communicate(data, timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                children = kill_tree(process.pid)
                stdout, stderr = process.communicate()
                reap_group(process.pid)
                reap_children(children)
            status = process.returncode
        stdout, stderr = stdout or b"", stderr or b""
        for suffix, value in (("stdout", stdout), ("stderr", stderr)):
            stem.with_suffix("." + suffix).write_bytes(value)
''' + source[end:]
source = source.replace('''                   "supervisor": supervisor, "supervisor_status": supervisor_status,
                   "supervisor_result": completed,
''', "")
source = source.replace("(environment if environment is not None else os.environ)", "(options.get(\"env\") or os.environ)")
source = source.replace('''        if supervisor_status != 0 or completed["error"] is not None or completed.get("remaining_children"):
            raise OSError(f"qualification supervisor failed: {completed}")
''', "")
source = source[:source.index('\n\nif __name__ == "__main__":')].rstrip("\n") + "\n"
data = source.encode()
expected = "b708dd0023ec89a5c2e156ee71027030116ce9e4355a76c157d6eab22769eb62"
actual = hashlib.sha256(data).hexdigest()
print("reconstructed SHA256:", actual)
assert actual == expected, "not publishing a nonidentical reconstruction"
(area / "qualification_support.pre-repair.py.txt").write_bytes(data)
