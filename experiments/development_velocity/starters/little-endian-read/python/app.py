import struct

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


def run(request):
    obj(request, ("hex", "offsets"))
    text = request["hex"]
    if type(text) is not str or len(text) > 1024 or len(text) % 2 or any(c not in "0123456789abcdef" for c in text):
        raise ValueError("hex")
    offsets = [integer(n, 0, 512) for n in array(request["offsets"])]
    data = bytes.fromhex(text)
    if any(offset + 2 > len(data) for offset in offsets):
        return {"error": "out-of-bounds"}
    return {"values": [struct.unpack_from(">H", data, offset)[0] for offset in offsets]}
