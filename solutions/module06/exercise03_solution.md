# Module 06 / Exercise 03 — Solution (one reference design)

## 1. Block diagram

```
 retire monitor (2 slots) --> retire_ap  (in-order; entry: seq, pc, instr, rd, data, trap, cause)
                                  |
                                  v
        +---------------- scoreboard: arch_cmp ----------------+
        |   predictor: ISS runs the PROGRAM IMAGE on its own   |      program image  --> ISS (also loaded into memory model)
        |   pc; one ISS step per actual retirement             |
        |   expected entry --> compare (in order, === fields)  |
        +------------------------------------------------------+

 lsu monitor --> lsu_req_ap (tag, addr, we, wdata)   (in order of issue)
             --> lsu_rsp_ap (tag, rdata)             (may be out of order)
                                  |
                                  v
        +---------------- scoreboard: mem_cmp ----------------+
        |   assoc array keyed by tag: request -> waiting       |
        |   response: look up tag, check, delete               |
        +------------------------------------------------------+
```

In-order streams: retire. Out-of-order: load responses. Fetch is **not** an input to the architectural check (speculation, section 4).

## 2. Retire-trace compare

- **Two retirements per cycle:** the monitor samples both retire slots at each edge and publishes slot 0 then slot 1 with two `write` calls in the same time step; the architectural rule is that slot 0 is older. A running `seq` number on each entry lets the scoreboard detect a missing or duplicated entry (gap in `seq`).
- **Entry fields:** `seq`, `pc`, `instr`, `rd`, `data`, plus `trap` and `cause` (and, if the DUT exposes them, `mepc`/`mcause` values via the CSR register model, Module 09).
- **Trap representation:** the ISS, when the instruction at `pc` raises an exception, produces an expected entry with `trap = 1`, the cause, `rd = 0`; the next expected entry is the first handler instruction at the trap vector. An interrupt (asynchronous) is injected into the ISS at the same *instruction boundary* the DUT took it (the DUT's retire entry says which instruction was interrupted); the test cannot predict the boundary from time alone.

## 3. Memory-side compare

Key = **tag**. On a request: `pending[tag] = req` (error if the tag is already pending). On a response: `if (!pending.exists(tag))` → error "unexpected response", else check the response (data for loads comes from the architectural comparison, so here check address/direction/protocol rules: one response per request, ordering rules the memory system promises), then `pending.delete(tag)`. At end of test: any entry left in `pending` → error "request never answered". Out-of-order arrival is therefore harmless.

## 4. Speculation

A scoreboard that predicts from the **fetch** stream sees wrong-path instructions that never retire: expected entries with no actual partner, and the ISS (which must follow only architecturally executed instructions) gets out of sync. Remedy: drive the ISS from the **program image** and from its own pc, advancing exactly one architectural instruction per actual retirement (a *pull* model); fetch monitoring remains a separate bus-level check (fetch address legality, no fetch outside the image). The retire entry's `pc` and `instr` are compared with the ISS's (`pc`, image word at `pc`), which also catches the DUT executing the wrong instruction.

## 5. End-of-test conditions (all must hold)

1. Comparisons performed > 0 and equal to the number of retirements the DUT reported (via the sequence numbers).
2. No expected/actual left over beyond the allowed pipeline bound (in flight at the end only if the test intentionally ends mid-run; normally zero after drain time).
3. The program's end marker retired (for example a store to a designated "end of test" address) and the ISS reached the same point.
4. No pending memory requests; no unexpected responses.
5. Exception/interrupt counts in the DUT trace equal those the ISS expected.
6. Zero `UVM_ERROR`/`UVM_FATAL`, and the bench-level sanity check that simulation time is non-trivial (the Module 01 time-0 lesson).
In-flight work is handled with drain time (Module 02) so the monitors collect the last retirements before `check_phase`.

## 6. Failure visibility

On the **first** mismatch print: the retirement index and `seq`, both entries (`convert2string`), the last N (say 16) retirements from a history ring buffer, and the ISS register file. Then set a `failed` flag and either stop comparing or limit further reports to a small count: after a real divergence (a wrong branch, a lost instruction) every later entry is off, and the flood buries the first error. A compare that pops both entries every time keeps queues aligned, but alignment cannot survive a lost or extra instruction; do not rely on it.

## Self-review checklist

- [x] In-order and out-of-order streams identified, and the right structure chosen for each.
- [x] Dual retire handled by publishing in age order with a sequence number.
- [x] Exceptions represented in the expected stream.
- [x] Speculation addressed (ISS pulled by retirements, not pushed by fetches).
- [x] At least four end-of-test conditions.
- [x] First-failure reporting policy given.

## Expected log

Not applicable (design exercise).

## The result that matters

The checking model must match the **architecture** (what retires, in program order), not the micro-architecture (what was fetched or reordered). Everything dynamic — speculation, reordering — is absorbed by choosing the right *source of truth* for the ISS and the right key for the comparison. Variation to try: describe how the design changes if the DUT retires out of program order (hint: it must not, architecturally; say what you would check to prove it).
