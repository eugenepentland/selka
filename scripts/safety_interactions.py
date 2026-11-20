"""Generated managed-memory boundary cases with independent scalar oracles."""


def templates(rng):
    value = rng.randrange(1, 1000)
    count = rng.randrange(1, 8)
    odd = rng.randrange(2)
    propagation = '''func halve(value: int) -> int fails int:
    if value % 2 != 0:
        fail 1
    return value // 2


func total(values: int[]) -> int fails int:
    mut sum = 0
    for value in values:
        const half = try halve(value)
        sum = sum + half
    return sum


func main() -> int:
    match total([FIRST, SECOND]):
        case Ok(found):
            return found
        case Err(code):
            return -code
'''.replace('FIRST', str(value * 2)).replace('SECOND', str(value * 2 + odd))
    yield propagation, -1 if odd else value * 2, 'managed-arena-propagation'
    midpoint = rng.randrange(5)
    mutation = '''func change(mut values: int[], index: int, x: int) -> int:
    if index < len(values):
        values[index] = x
    return 0


func main() -> int:
    mut values = [1, 2, 3, 4]
    _ = change(mut values, MID, VALUE)
    return values[0] + values[1] + values[2] + values[3]
'''.replace('MID', str(midpoint)).replace('VALUE', str(value))
    numbers = [1, 2, 3, 4]
    if midpoint < 4:
        numbers[midpoint] = value
    yield mutation, sum(numbers), 'managed-list-mutation'
    escaping = '''func measure(values: int[]) -> int:
    return len(values)


func main() -> int:
    mut total = 0
    mut values: int[] = []
    for index in range(COUNT):
        values.append(index)
    total = measure(values)
    return total
'''.replace('COUNT', str(count))
    yield escaping, count, 'managed-arena-region-escape'
