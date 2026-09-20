# Order tiers: the volume rule changed

The `order-tiers` project in this directory prices orders and reports them. The
volume rule it implements is out of date. Your job is to make the project
implement the rule below, everywhere it is observable.

## The rule as it must now behave

* An order quantity of **20 or more** earns the top volume discount: **5%**
  (500 basis points).
* A quantity of **5 or more** (and less than 20) earns the smaller discount:
  **2%** (200 basis points).
* A smaller quantity earns no discount.
* `orders.total_cents(unit_price, quantity)` is `unit_price * quantity` less the
  discount for that quantity, in whole cents, truncating toward zero after the
  discount is applied.
* `audit.small_order(quantity)` is `1` exactly when the quantity earns no
  discount, and `0` otherwise.
* `bands.name(quantity)` is `"top"` for a quantity that earns the top discount,
  `"mid"` for one that earns the smaller discount, and `"none"` otherwise.

## What must not change

* The public API: module names, function names, parameter order and return types
  are used by other projects.
* `report.line(sku, unit_price, quantity)` keeps returning one string,
  `"<sku> <total_cents> <small_order_flag> <band>"`.
* `main.my` keeps printing one report line per sample order and exits `0`.
* `mylang check main.my` must succeed.

## Notes

* The compiler is `mylang`, on `PATH`.
* The repository documentation is readable at the `docs` path named in your
  prompt.
* The rule must hold for every quantity, not only for the quantities `main.my`
  prints today: an unseen grading probe exercises quantities on and around each
  boundary.
