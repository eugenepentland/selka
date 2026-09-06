"""Run with zig-out/bindings on PYTHONPATH after generating message_bindings.py."""
from message_bindings import CASES, TYPES, dumps, loads

Header = TYPES['message::Header']
Status = TYPES['message::Status']
Reading = CASES['message::Message']['reading']

message = Reading(Header(f_sequence=18446744073709551615, f_status=Status.v_ready))
encoded = dumps(message)
assert loads(encoded, expected_type='message::Message') == message
print(encoded)
