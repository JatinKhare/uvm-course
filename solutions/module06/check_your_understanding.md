# Module 06 — Check Your Understanding: Answers

## 1. First comparison and retirement #3

Fetches arrive at 0, 10, 20, 30, 40; retirements at 15, 25, 35, 45, 55. The first comparison happens at **15 ns**, when retirement #1 arrives. At that moment two expected entries are queued (from the fetches at 0 and 10); one is consumed, one remains. Retirement #3 arrives at **35 ns**; its expected entry (made at 20 ns from `ADD x3,x1,x2`) says `rd=x3, data = 5 + 7 = 12 = 0x0000000c`, the actual carries `0x0000000d`, so `do_compare` returns 0 and `RETIRE_MISMATCH` is printed at 35 ns with both sides.

## 2. X in `retire_data`

- **`bit` fields:** the monitor's assignment of an X to a 2-state `bit` silently converts it to 0: the DUT's X is gone before the scoreboard sees it; if the expected value happens to be 0, the compare passes.
- **`logic` fields, check written as `if (act.data != exp.data) error`:** `!=` with an X operand yields X, and `if (X)` takes the false branch: **no error — a silent pass**.
- **`logic` fields, `do_compare` returning `(data == r.data)` as a 2-state `bit`:** the X result is converted to 0 on return, so `compare()` returns 0 and a mismatch *is* reported — correct, but by accident of the conversion, and fragile (any `!=`-style check elsewhere would pass).
- **`logic` fields and `===`:** an X never equals a 0/1 value, the result is a definite 0, `RETIRE_MISMATCH` is reported and the X is visible in the printed `data=0xxxxxxxxx`. This is why the course uses `===` in `do_compare` and `!==` in direct checks.

## 3. `write_retire` before `write_fetch` in one time step

State: `exp_q = []`, `act_q = []`.
- `write_retire(a)`: `act_q = [a]`; `try_compare`: `exp_q.size()` is 0, so the loop body does not run. Nothing lost; `a` waits.
- `write_fetch(t)`: `iss.step(t.data)` creates `e`; `exp_q = [e]`; `try_compare`: both queues non-empty → pop `e` and `a`, `n_cmp++`, compare. Queues empty again.
The result is identical to the opposite arrival order. A design that popped `exp_q` inside `write_retire` would have hit the empty queue in the first call.
