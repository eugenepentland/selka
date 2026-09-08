import model
import ledger


def run(request):
    model.validate(request)
    state = {a["id"]: a["balance"] for a in request["accounts"]}
    results = []
    for operations in request["batches"]:
        state, status = ledger.batch(state, operations)
        results.append(status)
    return {"results": results, "balances": [{"id": key, "balance": state[key]} for key in sorted(state)]}
