"""Invocation-only participant bridge. Its source and parent paths are out of participant scope."""
import json
import sys
sys.dont_write_bytecode = True
from coordinator import invoke


def main():
    if len(sys.argv) != 4:
        raise ValueError('usage: participant_bridge.py A|B command|check|finish|stop JSON')
    participant, operation, payload = sys.argv[1:]
    return invoke(participant, operation, json.loads(payload))


if __name__ == '__main__':
    try:
        print(json.dumps(main(), sort_keys=True))
    except (ValueError, OSError) as error:
        print(json.dumps({'outcome': 'rejected', 'error': str(error)}))
        raise SystemExit(1)
