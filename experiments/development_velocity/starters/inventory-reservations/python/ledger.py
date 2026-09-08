def initial(stock):
    return {item["id"]: item["quantity"] for item in stock}


def apply(available, reservations, operation):
    # Inventory loading/reporting exists; reservation transitions are the feature.
    return "unsupported-operation"
