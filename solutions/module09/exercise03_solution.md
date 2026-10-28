# Module 09 / Exercise 03 — Solution (one reference design)

## 1. Model review checklist (before any DUT)

- Every register present with the right **address**, width, and access policy (RW/RO) from the spec table; checked by a script diffing a model dump against the spec.
- Every implemented bit is described (fields tile the 32 bits; reserved bits as RO zero fields).
- Reset values correct (mtvec `BASE = 0x40` → `0x100`); volatility right (`mcause`, and `mepc` if hardware writes it, are volatile or are updated by explicit prediction).
Three things that could be wrong in the model: a field at the wrong bit position; a missing reserved bit; a wrong access policy (RW where the spec says RO).

## 2. Tests

| Test | Proves | Mechanism |
|---|---|---|
| `csr_hw_reset` | reset values | `uvm_reg_hw_reset_seq` |
| `csr_bit_bash` | RW bits store and read back, no aliasing | `uvm_reg_bit_bash_seq` (excluding RO registers via `NO_REG_BIT_BASH_TEST`) |
| `csr_access` | frontdoor and backdoor paths agree | `uvm_reg_access_seq` (**backdoor DPI-dependent**) |
| `csr_ro_write` | RO fields ignore writes (`mcause`, `mepc.zero`) | own: write all-ones, read, mirror check |
| `csr_mask` | `mstatus` keeps only MIE/MPIE | own: write `0xFFFFFFFF`, expect `0x88` |
| `csr_instr_path` | a CSR written by instruction is visible through the register port | own, virtual sequence (instruction program + register-port read) |
| `csr_trap_update` | hardware updates of `mepc`/`mcause` are observed | program takes a trap (Module 10 scope) + mirror check with prediction |
| `csr_reset_mid` | reset behaviour of CSRs and mirror | reset during traffic, then `hw_reset` check |

## 3. Prediction architecture

Use an **explicit predictor** (`set_auto_predict(0)`) fed by a **CSR-port monitor** (`uvm_reg_predictor#(mcpu_csr_item)`, `bus_in`) so every register-port access updates the mirror. Writes by CSR **instructions** do not appear on the register port, so the retire-stream path updates the mirror too: a small component converts each retired `CSRRW`/`CSRRS` (from the ISS's expected stream) into `predict(value, UVM_PREDICT_WRITE)` on the right register. Hardware updates at a trap (`mepc`, `mcause`) are applied with `predict(value, UVM_PREDICT_DIRECT)` when the scoreboard/ISS signals a trap entry, or the fields are volatile and are not mirror-checked.

```
CSR port --> csr_mon.ap --> uvm_reg_predictor --> mirror
retire stream --> ISS (CSR array) --> csr_pred_from_iss --> mirror (WRITE / DIRECT)
```

## 4. Two access paths

Write via instruction, read via the register port, and the reverse; compare the read value with (a) the register model's mirror and (b) the ISS's CSR array. The ISS is the reference for architectural behaviour; the register model is the reference for the port's field semantics. A scripted consistency check between the two models' CSR definitions (addresses, masks, reset values) prevents them drifting apart.

## 5. Backdoor

Good: fast initialisation of CSRs before a test; independent peek at a register to separate "bus path wrong" from "storage wrong" when a frontdoor check fails. Wrong: when the register has side effects (clear-on-read, W1C) that the test must exercise; and during a reset or clock-gated period where the DUT's behaviour is the point. The backdoor requires the HDL DPI and signal visibility (simulator-dependent), so the plan has a frontdoor-only fallback.

## 6. Reset

On DUT reset the model must `reset()` (mirror and desired) at the right moment: a reset watcher calls `blk.reset("HARD")` after reset is observed, and in-flight register operations are drained or abandoned first; then `csr_hw_reset` verifies the DUT matches the model's reset values. Resetting the DUT without resetting the mirror produces a flood of spurious mismatches.

## 7. Coverage

Field-level: every RW field written to 0 and to 1; every RO register read; per-register access counts (read, write, backdoor/frontdoor). One cross: register × access kind × path (frontdoor/instruction) = 4 × 2 × 2 = 16 bins, closing "every CSR was touched both ways".

## 8. Failure triage (mirror check fails on `mstatus` bit 3)

1. **Model:** is the field at bit 3, RW, with the right reset and no volatility? (Spec table diff.)
2. **Adapter/bus:** does a backdoor read of the same register agree with the frontdoor read? If backdoor ≠ frontdoor, the bus decode or adapter is wrong; if they agree, the storage is what it is.
3. **DUT:** read the RTL's mask for the register; compare with the spec.
4. **Test:** was a write to the register made by something that bypassed the mirror (instruction path, hardware) with no prediction?
5. Re-run with the register port monitor's log of the last accesses.

## Self-review checklist

- [x] Seven or more tests, with built-in sequences and own sequences distinguished.
- [x] Explicit predictor and a second prediction source for instructions and traps.
- [x] Both access paths compared against the right references.
- [x] Backdoor limits and the simulator dependence stated.
- [x] Reset handling for the mirror.
- [x] Triage order from model to test.

## Expected log

Not applicable (design exercise).

## The result that matters

For a CPU the hard part of RAL is **keeping the mirror truthful when something other than the register port changes a CSR** (instructions, hardware, reset). The model is easy; the prediction architecture is the design. Variation to try: add a write-1-to-clear CSR and decide which of backdoor, auto-predict and the explicit predictor handles clear-on-read/W1C correctly.
