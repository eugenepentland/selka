import model
import ledger


def run(request):
    model.validate(request)
    available, active = ledger.initial(request["stock"]), {}
    results = [ledger.apply(available, active, operation) for operation in request["operations"]]
    return {"results": results,
            "available": [{"id": key, "quantity": available[key]} for key in sorted(available)],
            "active": sorted(active)}
