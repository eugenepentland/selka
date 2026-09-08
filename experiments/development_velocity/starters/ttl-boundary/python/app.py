import re

def obj(value, fields):
    if type(value) is not dict or set(value) != set(fields):
        raise ValueError("object fields")


def integer(value, low, high):
    if type(value) is not int or not low <= value <= high:
        raise ValueError("integer range")
    return value


def array(value, maximum=128):
    if type(value) is not list or len(value) > maximum:
        raise ValueError("array bound")
    return value


def identifier(value):
    if type(value) is not str or re.fullmatch(r"[a-z][a-z0-9_-]{0,31}", value) is None:
        raise ValueError("identifier")
    return value


def sweep(state, now):
    for key in list(state):
        if state[key][1] < now:
            del state[key]


def run(request):
    obj(request, ("operations",))
    operations = array(request["operations"])
    last = 0
    for op in operations:
        if type(op) is not dict or op.get("op") not in ("put", "get"):
            raise ValueError("operation")
        obj(op, ("op", "at", "key", "value", "ttl") if op["op"] == "put" else ("op", "at", "key"))
        last = integer(op["at"], last, 1000000)
        identifier(op["key"])
        if op["op"] == "put":
            integer(op["value"], -1000000, 1000000)
            integer(op["ttl"], 0, 1000000)
    state, results = {}, []
    for op in operations:
        sweep(state, op["at"])
        if op["op"] == "put":
            state[op["key"]] = (op["value"], op["at"] + op["ttl"])
            results.append(None)
            sweep(state, op["at"])
        else:
            results.append(state[op["key"]][0] if op["key"] in state else None)
    return {"results": results, "live": sorted(state)}
