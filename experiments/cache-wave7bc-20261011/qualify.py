#!/usr/bin/env python3
"""Run the permanent native application cache qualification's complete matrix."""
from pathlib import Path
import runpy

if __name__ == "__main__":
    runpy.run_path(str(Path(__file__).resolve().parents[2] / "tests/application_cache.py"), run_name="__main__")
