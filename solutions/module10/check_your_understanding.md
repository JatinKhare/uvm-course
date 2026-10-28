# Module 10 — Check Your Understanding: Answers

## 1. Why `[SB]` prints at 235 ns

The fifth instruction executes at the **185 ns** edge; the driver completes its item (`item_done`) at that edge, so `s1.start` returns and the test drops its objection at 185. The run phase does not end then: the **drain time (50 ns)** keeps it open until **235 ns**. That is deliberate: the retire monitor only observes the fifth retirement at 195 ns and the scoreboard compares it then; without drain the phase could end before that. `report_phase` (which prints `[SB]`) runs after the run phase ends: at 235 ns.

## 2. Mutation: two errors

`x3 = a + b + 1 = 13`. Retirement #3 (ADD) is observed at 135 ns: act `data=0x0d` vs exp `0x0c` → `RETIRE_MISMATCH` at **135 ns**. Retirement #4 (SW x3,0(x4)) retires with `rd=0, data=0` on both sides, so it matches even though it stores the wrong value (13) — stores are only visible through later loads. The LW (#5) then reads that 13 back: observed at 195 ns, act `0x0d` vs exp `0x0c` → second `RETIRE_MISMATCH` at **195 ns**. Total **2 errors** at 135 and 195, final line `mismatched=2`.

## 3. `flush()` deleted in the reset test

After program 1 the ISS has executed 5 instructions: `iss.pc = 20`. The DUT restarts at pc 0. Program 2's first fetch is observed at **285 ns** with address 0:

`UVM_ERROR ... @ 285 [PC_MISMATCH] fetch #6: DUT fetched 0x00000000, ISS expects pc 0x00000014`

— the **first error at 285 ns**. All five program-2 fetches mismatch (285, 315, 345, 375, 405 ns: DUT addresses 0, 4, 8, 12, 16 versus ISS 20, 24, 28, 32, 36). The ISS then predicts retirements with those pcs, so each of the five retirements (observed at 295, 325, 355, 385, 415 ns, with pcs 0…16) also mismatches on `pc`: five `RETIRE_MISMATCH` errors. **Total: 10 errors** (5 + 5), and the summary line reads `fetched=10 compared=10 mismatched=5`. One missing line of code produced a flood whose *first* message already names the cause (the ISS pc is not 0): read the first error.
