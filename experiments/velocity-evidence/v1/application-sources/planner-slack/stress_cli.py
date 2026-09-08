"""Full-contract resource cases; nonzero host status and timeouts fail the suite."""
import json
import subprocess
import time
from test_cli import HOST, ROOT, job, manifest

names = ["j" + str(i).zfill(3) for i in range(128)]
cases = [
    ("dense-cycle", [job(n, 1, names) for n in names],
     {"error": "cycle", "blocked": names}),
    ("maximum-distinct-unknown", [
        job(n, 1, ["x" + str(i * 128 + j).zfill(5) for j in range(128)])
        for i, n in enumerate(names)
    ], {"error": "unknown-dependency", "ids": [
        "x" + str(i).zfill(5) for i in range(16384)
    ]}),
]
# Exercise the same supported reference counts with object dependencies.
cases += [
    (name + "-lagged",
     [job(j["id"], j["duration"],
          [{"id": dependency, "lag": 1000000} for dependency in j["needs"]])
      for j in jobs], expected)
    for name, jobs, expected in list(cases)
]
for name, jobs, expected in cases:
    start = time.monotonic()
    result = subprocess.run(
        [str(HOST), "--project", str(ROOT)],
        input=json.dumps({"cases": [manifest(jobs)]}).encode(),
        capture_output=True, timeout=180,
    )
    print(name, "exit", result.returncode, "seconds", round(time.monotonic() - start, 3),
          "output bytes", len(result.stdout), "stderr", result.stderr.decode(), flush=True)
    assert result.returncode == 0, result.stderr.decode()
    assert json.loads(result.stdout) == {"results": [expected]}
