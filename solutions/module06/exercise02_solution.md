# Module 06 / Exercise 02 — Solution

## Full solution code (changed parts)

```systemverilog
// mcpu_iss: no shared object; build a new transaction in step()
function mcpu_retire_txn step(bit [31:0] instr);
  mcpu_retire_txn r;
  // ... decode/execute as before ...
  r = mcpu_retire_txn::type_id::create("exp");        // Bug A fix: new object per call
  r.pc    = pc;
  r.instr = instr;
  r.rd    = (we && rd != 0) ? rd    : 5'd0;
  r.data  = (we && rd != 0) ? wdata : 32'd0;
  if (we && rd != 0) regs[rd] = wdata;
  pc = next_pc;
  return r;
endfunction
// (remove the `last` member and its creation in new())

// mcpu_retire_txn.do_compare
return super.do_compare(rhs, comparer) &&
       (pc === r.pc) && (instr === r.instr) && (rd === r.rd) && (data === r.data);   // Bug B fix
```

## Bug A — the predictor returns one shared object

**Mechanism:** `step` overwrites the fields of the single `last` object and returns its handle. The scoreboard stores **handles** in `exp_q`, so every queue entry points to the same object, whose contents are whatever the *most recent* `step` wrote. Trace with the example's timing:
- Fetch @0: `last` = instr 0; `exp_q = [last]`; no actual yet.
- Fetch @10: `last` = instr 1; `exp_q = [last, last]`.
- Retire #1 @15 (`pc=0`): pops `last`, whose contents are **instr 1** (`pc=4`): `exp pc=0x00000004 | act pc=0x00000000` → mismatch.
- Fetch @20 → `last` = instr 2; retire #2 @25 (`pc=4`): `exp pc=0x00000008` vs `act pc=0x00000004` → mismatch.
- Likewise #3 @35: `exp pc=12` vs `act pc=8`; #4 @45: `exp pc=16` vs `act pc=12`.
- Retire #5 @55 (`pc=16`): `last` still holds instr 4 (the last fetch), which happens to equal the actual → match.
So four mismatches, the expected side always **one instruction ahead**, and the last pair matching by coincidence.
**Fix:** `create` a new transaction in every `step`. **Rule:** any component that queues handles needs producers that never reuse the object.

## Bug B — `do_compare` omits `data`

**Mechanism:** `pc`, `instr`, `rd` are compared but not `data`, so a retirement with the right instruction, register and wrong value is judged equal. With the DUT's third retirement carrying 13 instead of 12, all five pairs compare equal: `compared=5 mismatched=0`, no error. Nothing is wrong with the ISS or the connections: the checker is blind to the one field that holds the result.
**Fix:** add `(data === r.data)`. **Negative test:** run a stream that is known-wrong in each compared field in turn (as `example02.sv` does for `data`) and require exactly one `RETIRE_MISMATCH` per injected corruption. A checker that cannot fail is not a checker.
**Common wrong fix:** adding the field only to `convert2string` (the failure would be printed but never detected).

## Self-review checklist

- [x] Every `exp_q` entry is an independent object.
- [x] `do_compare` covers all four fields of the transaction (`pc`, `instr`, `rd`, `data`) using `===`.
- [x] Scoreboard connections unchanged: `feed.fetch_ap → sb.fetch_imp`, `feed.retire_ap → sb.retire_imp`.
- [x] `super.*` calls retained; objections balanced in the test.
- [x] No undeclared identifiers (`last` removed).

## Expected log (hand-derived, not simulated)

Run 1 after fixing A (correct DUT stream, B still unfixed): no errors; `[SB] fetched=5 compared=5 mismatched=0` at 100 ns.
Run 2 after fixing both A and B (DUT stream with `data=13` on #3):

```
UVM_ERROR ... @ 35: uvm_test_top.env.sb [RETIRE_MISMATCH] retire #3 exp: pc=0x00000008 instr=0x002081b3 rd=x3 data=0x0000000c | act: pc=0x00000008 instr=0x002081b3 rd=x3 data=0x0000000d
UVM_INFO  ... @ 100: uvm_test_top.env.sb [SB] fetched=5 compared=5 mismatched=1
```

## The result that matters

Two different failures with one theme: a scoreboard can be wrong in two ways — **noisy** (false mismatches from aliasing) or **silent** (missing a field). The first is annoying; the second is dangerous. Variation to try: make the ISS return a new object but have the *feeder* reuse one `mcpu_retire_txn` for the actual stream and predict what the log looks like.
