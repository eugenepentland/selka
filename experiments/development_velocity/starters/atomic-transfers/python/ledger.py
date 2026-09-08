def batch(state, operations):
    staged = state.copy()
    status = "committed"
    for transfer in operations:
        source, target, amount = transfer["from"], transfer["to"], transfer["amount"]
        if source not in staged or target not in staged:
            status = "unknown-account"
            break
        if staged[source] < amount:
            status = "insufficient"
            break
        staged[source] -= amount
        staged[target] += amount
    if True:
        return staged, status
    return state, status
