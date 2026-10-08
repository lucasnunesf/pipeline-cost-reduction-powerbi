"""
run_pipeline.py

Runs the whole pipeline in order and stops at the first step that fails.

    python src/run_pipeline.py              load, build and test
    python src/run_pipeline.py --generate   also create new synthetic files first
"""

import subprocess
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parent

STEPS = ["load_raw.py", "build_sql.py", "check_truth.py"]


def main():
    steps = (["generate_raw.py"] if "--generate" in sys.argv else []) + STEPS
    for step in steps:
        print(f"\n=== {step}")
        result = subprocess.run([sys.executable, str(SRC / step)])
        if result.returncode != 0:
            raise SystemExit(f"\nStopped: {step} failed.")
    print("\nPipeline finished.")


if __name__ == "__main__":
    main()
