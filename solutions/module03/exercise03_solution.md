# Module 03 / Exercise 03 — Solution (one reference design)

## 1. Scenario list

| # | Scenario | Expected at the LW |
|---|---|---|
| 1 | SW then LW, same address, **distance 0** (adjacent) | stored value |
| 2 | Distance 1, 2, 3 (independent filler instructions between SW and LW) | stored value |
| 3 | Two SWs to the same address, then LW | the **later** store |
| 4 | **Negative:** SW to A, LW from A+4 (neighbour word) | preload value of A+4, not the store |
| 5 | Same address reached through **different base registers** (SW uses x4, LW uses x5, both hold the same value, or different base+offset sums that reach the same address) | stored value (match is by address, not register name) |
| 6 | LW destination equals the SW data register, and equals the base register | stored value; base register overwritten correctly |
| 7 | Store data patterns: all zeros, all ones, alternating bits, equal to the stale preload | stored value (zero and "equals preload" distinguish a no-op) |

## 2. Sequence structure

- `mcpu_sw_lw_seq` (instruction sequence on the fetch-side sequencer): `rand` knobs `dist` (0..3), `same_addr` (bit), `off` (12-bit word-aligned), `data_sel` (enum of patterns), `dup_store` (bit). Builds: base setup → data setup → SW → `dist` fillers → LW.
- `mcpu_filler_seq` / helper in the base: independent ALU instructions that touch neither the base nor the data register.
- `mcpu_mem_preload_seq` (load/store-side): preloads A and A+4 with known stale words.
- `mcpu_sw_lw_vseq` (**virtual**): preloads memory first, then runs `mcpu_sw_lw_seq` several times, one per scenario. Virtual because it must drive two sequencers, in order.

## 3. Constraints (key sequence)

```systemverilog
// base address: set once with ADDI so it is aligned and in the preloaded region
send_instr(OP_ADDI, base_reg, 5'd0, 5'd0, 12'h100);    // 0x100: multiple of 4
// store/load offsets: word-aligned (also enforced by the item's c_align)
// same address  <=>  same base register value  and  same offset
constraint c_off   { off[1:0] == 2'b00; off inside {[12'h000:12'h03C]}; }
constraint c_same  { ld_off == (same_addr ? st_off : st_off + 12'd4); }
constraint c_dist  { dist inside {[0:3]}; }
```

Because `OP_SW`/`OP_LW` offsets are already word-aligned by the item and the base is loaded with a multiple of 4, the effective address is aligned by construction. Scenario 5 sets a second register to the same value with `ADDI x5,x0,0x100`.

## 4. Data choices

Preload A with a recognisable stale word (e.g. `0xDEADBEEF`) and A+4 with another (`0x12345678`); store a different, non-trivial value (e.g. 42 or a pattern built with `ADDI`, such as `-1` for all ones). Rule: **the correct answer, the stale answer, and the neighbour answer must all be distinct**, except in the one scenario (7) that deliberately makes them coincide. Limitation: with only `ADDI` (12-bit sign-extended) the reachable 32-bit patterns are limited; richer patterns need `ADD/SUB/AND/OR` combinations or a `LUI` instruction that this course's item does not model.

## 5. Expected result and where it is checked

When the LW retires, the retire-trace entry for that PC must show destination `rd` and `retire_data` equal to the stored value (scenarios 1–3, 5–7) or the preload value of the neighbour (scenario 4). The check lives in the **scoreboard**: the retire monitor feeds it and the reference model predicts the expected value (Module 06). A directed assertion on the pipeline could add a cycle-accurate forwarding check, but the architectural result is the scoreboard's job.

## 6. Reproducibility

Log the seed and the scenario knobs (`dist`, `same_addr`, data pattern) via `convert2string` at the start of each run of the sequence, and rerun with the simulator's seed option (name is **SIMULATOR-DEPENDENT**; Module 07).

## Coverage (mentioned, not built)

A cross of `dist` (0–3) × `same_addr` (same/neighbour) × data class (zero/ones/other/equals-stale) would prove every combination was exercised (Module 08).

## Self-review checklist

- [x] At least five scenarios, including a negative.
- [x] A virtual sequence, with the reason (two sequencers, ordering).
- [x] Alignment guaranteed by construction (base + offset).
- [x] Wrong, stale and neighbour results distinguishable.
- [x] Checker named (scoreboard + reference model), body deferred.

## Expected log

Not applicable (design exercise).

## The result that matters

A good directed-random design pins what makes the scenario *meaningful* (same address, known distance, distinguishable data) and randomises only what does not matter (registers, filler). If a scenario can be reached just by lucky randomisation, the test is not directed; if it needs a log reader to tell right from wrong, the data was badly chosen. Variation to try: add an interrupt between the SW and the LW (Module 10) and say which expectation changes.
