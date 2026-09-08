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
    obj(request, ("accounts", "batches"))
    known = set()
    for account in array(request["accounts"], 32):
        obj(account, ("id", "balance"))
        name = identifier(account["id"])
        integer(account["balance"], 0, 1000000)
        if name in known:
            raise ValueError("duplicate account")
        known.add(name)
    for batch in array(request["batches"], 32):
        for transfer in array(batch, 32):
            obj(transfer, ("from", "to", "amount"))
            identifier(transfer["from"])
            identifier(transfer["to"])
            integer(transfer["amount"], 0, 1000000)
