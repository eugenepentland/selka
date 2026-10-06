#!/usr/bin/env python3
"""Use the strict text harness for S3-A's split-key lifetime generator.

Run through fuzz_qualification.py --kind text --harness THIS_FILE, with explicit
qualified old/new oracles and fresh evidence/cache roots. This supplementary
200-case sweep exercises split-key fusion in addition to the nine-kind matrix.
"""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
_split_generator = None


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def program(rng, index):
    global _split_generator
    if _split_generator is None:
        _split_generator = module(
            "s3_split_generator",
            ROOT / "experiments/new-core-s3-20261006/wave-c/s3-a/fuzz_split.py",
        )
    source = _split_generator.program(rng, index)
    prefix = f"module split_{index:04d}\n"
    if not source.startswith(prefix):
        raise RuntimeError("split generator module prefix changed")
    return f"module text_{index:04d}\n" + source[len(prefix):]


def main():
    harness = module(
        "s3_text_transport",
        ROOT / "experiments/new-core-s3-20261006/wave-b/s3-t1/fuzz_text.py",
    )
    harness.program = program
    return harness.main()


if __name__ == "__main__":
    raise SystemExit(main())
