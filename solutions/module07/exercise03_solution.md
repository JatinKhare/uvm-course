# Module 07 / Exercise 03 — Solution (one reference design)

## 1. Layers and knobs

| Layer | Class (names reuse the course's) | Knobs (`rand`) | Decides |
|---|---|---|---|
| Item | `cpu_instr_item` (+ `mcpu_mix_item` / `mcpu_hazard_item` via factory) | opcode mix weights, `reuse_prev` | one legal instruction |
| Burst | `mcpu_alu_burst_seq` (`n`, `hazard`), `mcpu_sw_lw_burst_seq` (`base_reg`, `off`), `mcpu_branch_seq` (forward offset), `mcpu_load_use_seq` (LW then consumer, distance 0..3) | pattern parameters | a meaningful instruction pattern |
| Scenario | `mcpu_stream_seq` (`n_alu`, `hazard`, number of bursts, mix of burst types) | counts, burst weights | the order and mix of bursts |
| Test / virtual sequence | `mcpu_vseq` over `mcpu_vseqr` (memory preload + program) | pinned knobs, seed | which scenario, with what data memory |

## 2. Constraints

```systemverilog
// (a) mix with a rare-opcode guarantee: distribution + choose the case first
constraint c_mix   { op dist { [OP_ADD:OP_OR] :/ 40, OP_ADDI := 20, OP_LW := 15, OP_SW := 15, OP_BEQ := 5, OP_CSRRW := 5 }; }
constraint c_order { solve op before imm; }       // CSR has 3 legal imm values; without this it is starved
// (b) hazard density: small soft register pool (base item) + reuse knob (Exercise 01) with weights, e.g. 70/30
// (c) legal addresses: base register set once by ADDI to a value inside the preloaded region, offsets aligned and bounded
constraint c_off   { off[1:0] == 2'b00; off inside {[12'h000:12'h03C]}; }
// (d) forward-only branches: positive offset within the program length
constraint c_br    { imm inside {[12'd2:12'd16]}; }
```

`solve before` is needed wherever a case has far fewer legal completions than its neighbours (CSR, aligned LW/SW) and must nevertheless get its intended share.

## 3. Program structure

1. **Setup** (directed, fixed): `ADDI` the base register(s) to the data region base; initialise a few source registers; optional CSR setup.
2. **Body** (random): `mcpu_stream_seq` bursts, each hazard-rich pattern independent of the others; every address derives from the base registers.
3. **End marker**: a final store to a designated end-of-test address (or a fixed `NOP` tail) the scoreboard and test recognise.
The data region is preloaded through the load/store-side sequencer (virtual sequence ordering: preload first, program second).

## 4. Termination

Every branch offset is positive and the program length is fixed, so the pc strictly increases (a taken branch only skips forward) until it reaches the end marker: at most `length` instructions retire. There are no jumps, no calls and no backward edges.

## 5. Reproducibility

At time 0 log `$get_initial_random_seed()`, the simulator/tool version and the test name. During generation log each burst and its pinned knob values, and write the instruction stream (encoded words and the memory preload) to a file. To replay after code changes, load that file into a **directed** sequence that sends the recorded words (no randomisation). With unchanged code, the logged seed reproduces the run (random stability keeps unrelated streams unaffected).

## 6. Per-test customisation

| Need | Mechanism | Feature |
|---|---|---|
| Pin a knob | `seq.randomize() with { n_alu == 6; hazard == 1; }` | SystemVerilog |
| Different opcode mix | factory type override of `cpu_instr_item` with a subclass carrying another `dist` (`set_type_override`) | UVM factory (Module 02) |
| Negative test | `item.c_align.constraint_mode(0)` plus an inline constraint requesting the illegal case | SystemVerilog |
| Config-driven weights | a config object read in the scenario sequence and applied through inline weights | UVM `config_db` |

## 7. Self-check for distribution drift

A coverage-style counter (or a small test-only subscriber) tallies opcode classes and hazard distances; at `check_phase` it compares each share against its target ± a tolerance (binomial standard deviation) and errors if a class never occurs. Functional coverage (Module 08) provides the same information with reports.

## Self-review checklist

- [x] Four layers, each with its knobs.
- [x] Constraints for mix, hazard density, addresses and branches, with the `solve before` need explained.
- [x] Program shape with setup, body, end marker; termination argument.
- [x] Seed, stream and replay strategy.
- [x] Customisation mechanisms separated into SystemVerilog and UVM.
- [x] Legality never weakened for a scenario (only switched off explicitly for a negative test).

## Expected log

Not applicable (design exercise).

## The result that matters

A random generator is a *system of constraints plus controls*: legality in the item, scenario in the sequences, intent pinned by the test, and **observability** (logging, replay, distribution checks) so that randomness is something you can audit. Variation to try: add interrupts as a second, concurrent sequence and say what must be logged to replay the interleaving.
