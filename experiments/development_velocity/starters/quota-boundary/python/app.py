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
    obj(request, ("limit", "used", "requests"))
    limit = integer(request["limit"], 0, 1000000)
    used = integer(request["used"], 0, limit)
    amounts = [integer(n, 0, 1000000) for n in array(request["requests"])]
    accepted = []
    for amount in amounts:
        allow = used + amount < limit
        accepted.append(allow)
        if allow:
            used += amount
    return {"accepted": accepted, "used": used, "remaining": limit-used}
