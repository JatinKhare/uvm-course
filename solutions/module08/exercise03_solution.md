# Module 08 / Exercise 03 — Solution (one reference plan)

## 1. Plan table

| # | Plan item | Implementation | Bins |
|---|---|---|---|
| 1 | Every instruction class retires | `cp_class` | R, ADDI, LW, SW, BEQ, CSRRW (6) |
| 2 | RAW hazard at every distance | `cp_dist` (nearest producer) | none, 1, 2, 3 (4) |
| 3 | Which operand carries the hazard | `cp_opnd` | rs1 only, rs2 only, both (3) |
| 4 | Load-use is seen by every consumer class | `cp_prod_class` (class of the nearest producer) | alu, load (2) |
| 5 | Branch outcome | `cp_br` | taken, not taken (2); transition `(taken => not taken)` etc. |
| 6 | Memory region and direction | `cp_dir`, `cp_region` | rd/wr × low/mid/high |
| 7 | Interrupt is observed at every instruction class | `cp_irq_class` (class of the instruction retiring when `irq` is sampled high) | 6 |
| 8 | Interrupt inside/outside a hazard window | `cp_irq_hz` | no hazard in flight, hazard at d1, d2/d3 (3) |
| 9 | Reset after each class of last-retired instruction | `cp_rst_last` | 6 |

## 2. Sampling points

- Retire-stream groups (1–5): `uvm_subscriber#(mcpu_retire_txn)`, `sample()` in `write()` after decoding (Module 08 example).
- Memory (6): the load/store monitor's subscriber, once per **completed** access.
- Interrupt groups (7–8): a small component that samples on the clock edge where `irq` is high, using the retire stream's *latest* class/distance (the pipeline view must be taken from the monitor, not from the interrupt sequence).
- Reset (9): the reset watcher, using the last retirement seen before reset asserted.
Not the driver: a driver reports what it *attempted*; an interrupt asserted during a stall, or an instruction killed by reset, would be counted though the DUT never experienced it.

## 3. Crosses

- `x_class_dist` = class × distance = 6 × 4 = **24** bins (the core hazard cross).
- `x_loaduse` = nearest producer class × consumer class × distance {1,2} = 2 × 6 × 2 = **24** bins.
- `x_irq` = `cp_irq_class` × `cp_irq_hz` = 6 × 3 = **18** bins.
Deliberately not built: class × distance × operand × region (24 × 3 × 3 = **216** bins): too many to close, and the factors do not interact (the memory region is irrelevant to forwarding).

## 4. Exclusions

- `ignore_bins`: in `x_loaduse`, producer class "load" with consumer distance 3 when the pipeline's load-use window is spec'd as two cycles: `// ignore: spec 4.2: load data is forwarded from distance 3 on; no hazard exists`. Verified by an assertion that no stall is inserted at distance 3.
- `ignore_bins`: producers that write no register (SW, BEQ) cannot be "nearest producer" bins; they never appear because the history stores `rd = 0`.
- `illegal_bins`: a retirement whose `pc[1:0] != 0` (the ISA subset requires word alignment): if it ever occurs it is a design or testbench bug, not a hole; `illegal_bins` raises an error at the point of occurrence.

## 5. Assertions paired with coverage

```systemverilog
// no X/Z on retirement
a_retire_known : assert property (@(posedge clk) disable iff (!rst_n)
                                  retire_valid |-> !$isunknown({retire_pc, retire_instr}));
c_back_to_back : cover  property (@(posedge clk) disable iff (!rst_n) retire_valid ##1 retire_valid);
// interrupt taken -> next fetch at the vector (uses internal signals through a bind, allowed in assertions)
a_irq_vector   : assert property (@(posedge clk) disable iff (!rst_n)
                                  irq_taken |-> ##[1:3] (if_req && if_addr == mtvec_base));
c_irq_taken    : cover  property (@(posedge clk) disable iff (!rst_n) irq_taken);
```
Each `cover` proves its assertion's antecedent happened (no vacuous pass).

## 6. Closure strategy

Random regression over many seeds with the Module 07 generator (hazard knob, `mcpu_mix_item` weights, burst sequences); interrupts injected by a concurrent sequence whose `irq` offset is swept over `0..N` cycles from the start of each burst. Merge coverage from **passing** runs only. Review holes weekly: reachable holes get a directed burst (e.g. "LW then consumer at distance 1, interrupt at +0/+1/+2"), unreachable holes get a documented `ignore_bins`. Stop criteria: all counted bins at goal (100% of non-waived bins), zero open waivers without reasons, assertions and scoreboard clean in every contributing run.

## 7. Two ways the plan can lie

1. Coverage sampled from the **sequence** (or driver): the interrupt "arrives at every class", but half were suppressed by reset or hidden behind a stall; numbers are healthy, the DUT never saw them.
2. The **distance** model has a bug (for example `x0` counted as a producer, or the history not cleared at reset): bins fill with phantom hazards. Mitigation: unit-test the coverage model on a known directed program with hand-derived bins (as in Module 08's examples).
Also: a perfect coverage report with a scoreboard that cannot fail.

## Self-review checklist

- [x] At least eight plan items with explicit bins.
- [x] Sampling from monitors/subscribers, with the reason.
- [x] Crosses sized and justified; one cross deliberately excluded.
- [x] Waivers have written reasons; `illegal_bins` used for a bug-if-hit case.
- [x] Assertions paired with `cover property`.
- [x] Closure loop and stop criteria; two failure modes of the plan.

## Expected log

Not applicable (design exercise).

## The result that matters

A coverage plan is a *list of claims about the design that you intend to demonstrate*; each bin must be traceable to one. The skill is cutting the cross space down to the combinations that interact, sampling them from what the DUT did, and being able to defend every waiver. Variation to try: add a second interrupt line with priority and compute how the `x_irq` cross grows.
