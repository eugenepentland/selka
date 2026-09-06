"""Run after generating domain_bindings.py and adding its directory to PYTHONPATH."""
import argparse
from pathlib import Path
import domain_bindings as generated

parser = argparse.ArgumentParser()
parser.add_argument('--compiler', required=True)
args = parser.parse_args()
client = generated.Client(args.compiler, Path(__file__).with_name('main.my'))
Wire = generated.CALL_TYPES['data::Wire']
result = generated.CALLS['data::Positive.from_wire'](client, p_x=Wire(7))
print(result)
