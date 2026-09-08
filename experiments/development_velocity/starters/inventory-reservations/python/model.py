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


def validate(request):
    obj(request, ("stock", "operations"))
    known = set()
    for item in array(request["stock"], 32):
        obj(item, ("id", "quantity"))
        name = identifier(item["id"])
        integer(item["quantity"], 0, 1000000)
        if name in known:
            raise ValueError("duplicate stock")
        known.add(name)
    for operation in array(request["operations"]):
        if type(operation) is not dict or operation.get("op") not in ("reserve", "release"):
            raise ValueError("operation")
        if operation["op"] == "reserve":
            obj(operation, ("op", "token", "id", "quantity"))
            identifier(operation["id"])
            integer(operation["quantity"], 1, 1000000)
        else:
            obj(operation, ("op", "token"))
        identifier(operation["token"])
