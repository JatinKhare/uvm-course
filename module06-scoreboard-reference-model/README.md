# Module 06 — Scoreboard & Reference Model

> Prerequisites: Modules 01–05 (agents and monitors, analysis ports, `uvm_analysis_imp`, FIFOs).
> What this module gives you: how a UVM scoreboard decides pass or fail for a CPU — a reference model (ISS) predicts what should retire, a scoreboard compares it with what did, and end-of-test checks make sure "nothing failed" never means "nothing was checked".

UVM 1.2 only. Logs are hand-derived. Labels: **PORTABLE UVM CONCEPT**, **SIMULATOR/VERSION-DEPENDENT**.


---

## Concept

### The story in plain words (start here)

Think of **a teacher marking homework**. The student (the CPU) hands in answers: for each instruction, *what it did and what value it produced* (that is the **retire** record). The teacher has an **answer key**, but the key was made by *reading the same questions* and working them out independently — that is the **reference model** (the ISS, a tiny software CPU). The **scoreboard** is the teacher marking line by line: "question 3: student wrote 13, key says 12 — wrong."

Three habits make a good marker, and they are this module's three big ideas:
1. **Mark in order** and keep two piles (answers received, answers expected) because they may arrive in either order.
2. **Print both answers** when they differ — "wrong" alone is useless.
3. **Notice an empty pile.** If no homework arrived at all, "no mistakes found" does *not* mean "all correct".


### What a CPU scoreboard checks

A CPU has few outputs worth watching cycle by cycle; the strongest evidence of correctness is its **architectural effect per retired instruction**: which instruction retired (`pc`, `instr`), which register it wrote (`rd`) and with what value (`data`). Two checking layers:

| Layer | Compares | Catches |
|---|---|---|
| Bus-level | each fetch/load/store transaction against the bus protocol and expected address/data | wrong fetch address, wrong store data, missing access |
| **Architectural (retire-trace)** | each retirement against a **reference model** executing the same program | wrong ALU result, wrong load data/forwarding, wrong branch, wrong CSR behaviour |

The reference model is an **instruction-set simulator (ISS)**: a software model of the ISA, independent of the RTL. In industry flows it is often a C/C++ model called over DPI-C; in this course it is a small SystemVerilog class, `mcpu_iss`.


### The predictor pattern

```
fetch monitor --(instruction word)--> [ ISS: step() ] --(expected retirement)--> expected queue --+
                                                                                                  +--> compare (in order)
retire monitor ---------------------------(actual retirement)--> actual queue --------------------+
```

Two design choices to state in an interview:

1. **What feeds the ISS?** Either the *program image* you intended to run, or the *instruction words the DUT actually fetched*. Feeding from the fetch monitor (used here) also lets you check the **fetch address** against the ISS program counter, catching wrong next-PC or branch behaviour. Feeding from the image keeps the expected result independent of any fetch bug but cannot detect one by itself.
2. **Where does the prediction happen?** In the scoreboard (simple), or in a separate predictor component that publishes expected transactions on its own analysis port (more reusable; the scoreboard then only compares).


### In-order versus out-of-order comparison

- **In-order** (our case): architectural retirement is in program order even on an out-of-order core, so a FIFO of expected entries compared against a FIFO of actual entries is enough.
- **Out-of-order** streams (bus responses that return out of order, a multi-core memory system): each transaction needs an identity (ID, tag, address+sequence number). Store expected entries in an **associative array keyed by that ID**; when an actual arrives, look up, compare, delete. Anything left in the array at the end is a missing transaction; an actual with no entry is unexpected.

```systemverilog
// out-of-order pattern (sketch; the item has an id field)
mcpu_bus_txn exp_by_id[int];
function void write_exp(mcpu_bus_txn t);  exp_by_id[t.id] = t;  endfunction
function void write_act(mcpu_bus_txn t);
  if (!exp_by_id.exists(t.id)) `uvm_error("UNEXPECTED", $sformatf("no expected txn id=%0d", t.id))
  else begin
    if (!exp_by_id[t.id].compare(t)) `uvm_error("MISMATCH", $sformatf("id=%0d", t.id))
    exp_by_id.delete(t.id);
  end
endfunction
```


### "Nothing failed" is not "passed"

A scoreboard that never receives an actual transaction reports no mismatch. End-of-test checks close that hole: `check_phase` errors if **no comparison happened**, if actuals remain with no expected entry, and warns (or errors, depending on pipeline depth) if expected entries never retired.


---

## UVM Mechanics

### Multiple analysis inputs: `uvm_analysis_imp_decl`

A component has exactly one `write` method, so two `uvm_analysis_imp` fields would collide. `` `uvm_analysis_imp_decl(_fetch) `` (at file/package scope, outside classes) declares `uvm_analysis_imp_fetch#(T, IMP)`, whose host method is **`write_fetch(T t)`**; `_retire` gives `uvm_analysis_imp_retire` and `write_retire`. The imps are constructed with `new("name", this)` in `build_phase`, connected by the env in `connect_phase` (Module 05).


### Execution context of `write_*`

**In plain words:** `write_*` is a **phone call that rings right now**, in the caller's moment. The fetch call and the retire call can ring in either order within the same instant — so each call just puts its item in its own **inbox** (a queue), then checks whether *both* inboxes have something to compare.

Each `write_*` runs inside the producer's `ap.write(t)` call: same time step, caller's thread, and **no guaranteed order between different producers**. Therefore:
- keep the body non-blocking (a function);
- never assume the expected entry arrived before the actual; **buffer both** and compare when both exist (the two-queue pattern in `try_compare`);
- never keep a transaction handle that the producer will modify later (see aliasing in Pitfalls).


### `compare()` and `do_compare()`

`uvm_object::compare(rhs, comparer)` calls the virtual hook `do_compare(rhs, comparer)` and returns 1 if equal. You write `do_compare`: `$cast` the argument, call `super.do_compare`, and combine field comparisons. `uvm_comparer` offers `compare_field`-style helpers that also generate miscompare messages; the course's examples return a plain bit and let the scoreboard print a message that includes **both** transactions (`convert2string`), which is what a debugger needs. (Message text produced by the comparer itself is **SIMULATOR/VERSION-DEPENDENT**.)

**4-state data.** `logic` fields can hold X/Z sampled from the DUT (a `bit` field would silently turn an X into 0 at the monitor's assignment, hiding it). With `==`, `x == 5` is X, and what happens next depends on how the X is consumed: `if (act != exp) error(...)` takes the false branch — an X **passes silently** — while a `do_compare` that returns the expression as a 2-state `bit` converts the X to 0 and happens to report a mismatch, by accident rather than by design. Use `===`/`!==` in `do_compare` and in every other DUT-versus-model check so the behaviour is explicit (an X never equals a 0/1 value).


### The reference model as plain SV

`mcpu_iss` is not a UVM class; it needs no phases or factory. It holds `regs[32]`, sparse `mem` and `csr` arrays and the `pc`, and `step(instr)` returns an expected `mcpu_retire_txn`. Two rules: `step` must return a **new** object per call, and `x0` must never be written (`rd != 0` guard).


### End-of-test checks

`check_phase` (function, bottom-up) is the place for end-of-test verdicts: it runs after the run phase has ended and all monitors have stopped. `report_phase` prints the summary. Both are **PORTABLE UVM CONCEPT**. Note the pipeline: instructions fetched in the last cycles are still in flight when the test ends, so "expected entries left over" is a **warning** that the test should size against the pipeline depth (use drain time, Module 02, so retirements finish first).


---

## Code Walkthrough

**The tiny program used all module** (so you can follow the numbers):

| # | Instruction | What the key (ISS) says should retire |
|---|---|---|
| 1 | `ADDI x1,x0,5` | pc 0, x1 = 5 |
| 2 | `ADDI x2,x0,7` | pc 4, x2 = 7 |
| 3 | `ADD x3,x1,x2` | pc 8, x3 = 5 + 7 = **12** |
| 4 | `SW x3,0(x4)` | pc 12, no register written |
| 5 | `LW x5,0(x4)` | pc 16, x5 = **12** (reads what the SW stored) |

In `example02.sv` the "chip" gets #3 wrong (13) on purpose, so you can see the scoreboard catch it at 35 ns. **Reading order:** `example01.sv` = the parts (transaction, ISS, scoreboard); `example02.sv` = a stand-in chip feeding it.


### 1. The retire transaction (`example01.sv`)

`mcpu_retire_txn` carries `pc`, `instr`, `rd` (0 means "no register written") and `data`, as 4-state `logic`. `do_compare` returns `super.do_compare(rhs, comparer) && (pc === r.pc) && ...`.


### 2. The ISS

```systemverilog
function mcpu_retire_txn step(bit [31:0] instr);
  r = mcpu_retire_txn::type_id::create("exp");     // new object each call
  ...
  case (opc)  7'b0110011: ... ADDI ... LW ... SW ... BEQ ... CSRRW ...
  r.pc = pc;  r.instr = instr;
  r.rd   = (we && rd != 0) ? rd    : 5'd0;
  r.data = (we && rd != 0) ? wdata : 32'd0;
  if (we && rd != 0) regs[rd] = wdata;
  pc = next_pc;
  return r;
```

Decoding follows the RV32I layouts used by `cpu_instr_item.encode()` in Module 03: an instruction encoded there decodes to the same operation here. Stores write `mem` and retire with `rd=0, data=0`; loads read `mem` (default 0); `BEQ` changes the next pc by the B-type offset; `CSRRW` returns the old CSR value and writes the new one.


### 3. The scoreboard

```systemverilog
function void write_fetch(mcpu_bus_txn t);
  if (t.addr !== iss.pc) `uvm_error("PC_MISMATCH", ...)
  e = iss.step(t.data);   exp_q.push_back(e);   try_compare();
endfunction
function void write_retire(mcpu_retire_txn t);  act_q.push_back(t);  try_compare();  endfunction
```

`try_compare` loops `while (exp_q.size() > 0 && act_q.size() > 0)`, pops **both** entries every time (also on mismatch, so the streams cannot slip by one) and counts. `while` (not `if`) drains a backlog when several entries arrived before the first compare.


### 4. End-of-test checks

`check_phase`: `SB_EMPTY` if nothing was compared, `SB_LEFTOVER` if actual entries have no expected partner, `SB_INFLIGHT` warning for fetches that never retired. `report_phase` prints `fetched/compared/mismatched`.


### 5. The run (`example02.sv`) — hand-derived

The synthetic feeder plays both monitors for the program `ADDI x1,x0,5; ADDI x2,x0,7; ADD x3,x1,x2; SW x3,0(x4); LW x5,0(x4)`: fetches at 0, 10, 20, 30, 40 ns, retirements 15 ns later. The ISS expects `x3 = 5 + 7 = 12` but the "DUT" retires 13 for the third instruction. Hand trace: at 35 ns the scoreboard prints `RETIRE_MISMATCH retire #3 exp: ... data=0x0000000c | act: ... data=0x0000000d`; the other four match; `fetched=5 compared=5 mismatched=1` at 100 ns. The synthetic design is deliberate: the Module 01 stub DUT never executes anything, so a full compare against it would only report the stub's own limitation.


---

## Common Pitfalls

- **Predictor returns the same object every call** (a reused `last` member) → expected entries alias; messages show the *latest* instruction on the expected side for every mismatch, usually all compares fail → queues store handles, not copies; `create` a new object per prediction.
- **`do_compare` forgets a field** (e.g. `data`) → a real DUT bug passes silently, summary says `mismatched=0` → review `do_compare` against the transaction's field list; add a negative test (inject a corrupt field, expect an error).
- **`==`/`!=` instead of `===`/`!==` on 4-state data** → an X from the DUT makes `if (act != exp)` false, so the check passes silently (in a bit-returning `do_compare` the X-to-0 conversion hides the problem differently) → `===`/`!==`, and declare monitored fields `logic`.
- **Pop only on match** → after the first mismatch the two streams are offset by one and every later compare fails (error flood hiding the real first failure) → pop both entries every time.
- **`if` instead of `while` in the compare loop** → backlog builds when several entries arrive together; leftovers reported at the end → `while` both queues non-empty.
- **Assuming expected arrives before actual** → works until the two `write_*` calls land in the same time step in the other order; a pop from an empty queue (runtime error) or lost compare → buffer both streams.
- **No end-of-test check** → a broken monitor connection (nothing arrives) yields a green run → `SB_EMPTY` and leftover checks in `check_phase`.
- **Feeding the ISS only from the program image** (not the fetch stream) → fetch-address and wrong-instruction-delivered bugs are invisible → compare the fetch address with the ISS pc, as `write_fetch` does.


---

## Interview Angle

**Q1. Describe the scoreboard for a CPU testbench.**
A retire monitor publishes each retired instruction (`pc`, `instr`, destination, data). A reference model/ISS, fed with the instructions the DUT fetched, predicts the same stream. The scoreboard buffers expected and actual entries and compares in order, reporting the first mismatch with both sides; `check_phase` verifies that something was compared and nothing is left over.

**Q2. How do you handle out-of-order results?**
Give every transaction an ID and store expected ones in an associative array keyed by ID; match on arrival and delete; leftovers and unmatched arrivals are errors. For an out-of-order core's *architectural* retire stream, order is still program order, so a FIFO suffices.

**Q3. Why buffer both streams instead of popping the expected queue in `write_retire`?**
Subscriber/producer ordering within a time step is unspecified. A scoreboard that assumes expected-first will occasionally find an empty queue. Buffering both and comparing when both are non-empty is order-independent.

**Q4. A scoreboard reports zero errors. How do you know it checked anything?**
End-of-test checks: count of comparisons > 0 (matching the expected instruction count), empty queues at the end, a deliberate negative test showing it can fail. Also print counts in `report_phase`.

**Q5. `==` or `===` in a compare, and why?**
`===` for DUT-sampled 4-state values: `==` with an X yields X, and a check written as `if (act != exp)` treats that as false, so an X in the DUT output would pass; `===` gives a definite answer (X never equals 0/1).

**Q6. Where does the reference model's expected state come from for loads and stores?**
The ISS keeps its own memory; stores update it, loads read it. Preloaded memory contents must also be given to the ISS (same image), or both sides can disagree on initial data.

**Q7. How do you make the scoreboard robust to the end of simulation?**
Use drain time so in-flight retirements are collected; size the allowed number of in-flight fetches to the pipeline depth; separate "in flight" (warning) from "never retired" (error) with a bound.


---

## Recap in five lines

1. The **retire record** (`pc, instr, rd, data`) is what we check; the **ISS** predicts it.
2. Keep **two queues**, compare when both have something, and **pop both every time**.
3. `write_*` calls arrive in **any order** within a time step — never assume expected-first.
4. Compare with **`===`** and print **both sides** on a mismatch.
5. In `check_phase`: **nothing compared**, **leftovers**, **in flight** — "no errors" is not "passed".

**Questions beginners often ask**
- *"Why predict from the fetched words, not the original program?"* — it also lets us check the fetch address; the price is that a corrupted fetched word is predicted consistently (Exercise 03 discusses the alternative).
- *"Why did one wrong result cause many errors?"* — a lost or skipped entry shifts the queues; read only the **first** error.
- *"Why a synthetic feeder in the example?"* — the early stub chip doesn't compute results; Module 10 brings a chip that does.


---

## Check Your Understanding

1. In `example02.sv`, at what time is the first comparison made, and how many expected entries are queued at that moment? Why does retirement #3 produce the error at 35 ns?
2. A DUT bug makes a load return X in `retire_data`. With `bit` fields in the transaction, what does the scoreboard see? With `logic` fields, what does `if (act.data != exp.data) error` do, what does a `do_compare` that returns `(data == r.data)` as a `bit` do, and what is the behaviour with `===`?
3. Two `write_*` calls reach the scoreboard in the same time step: `write_retire` first, then `write_fetch` for the matching instruction. Trace `try_compare` and show that nothing is lost.

Answers: `solutions/module06/check_your_understanding.md`.


---

## Exercises

| File | Type | Summary |
|---|---|---|
| `exercise01.md` | Fill-in | Write an order-independent two-queue comparator with end-of-test checks. Subtle traps: `if` vs `while`, popping on mismatch. |
| `exercise02.md` | Debug the testbench | A predictor that aliases its output object, then a `do_compare` that misses a field. |
| `exercise03.md` | Interview write-up | Describe the scoreboard for an out-of-order, dual-retire CPU with exceptions. |


---

## Reference

**Classes:** `uvm_scoreboard`, `uvm_sequence_item`, `uvm_object` (`compare`, `do_compare`, `convert2string`), `uvm_comparer`, `uvm_analysis_imp_<suffix>` (via macro), `uvm_analysis_port#(T)`, `uvm_tlm_analysis_fifo#(T)` (alternative design), `uvm_monitor`.

**Macros:** `` `uvm_analysis_imp_decl(_suffix) ``, `` `uvm_component_utils ``, `` `uvm_object_utils ``, `` `uvm_error ``, `` `uvm_warning ``, `` `uvm_info ``, `` `uvm_fatal ``.

**Methods:** `write_<suffix>(T t)`, `compare(rhs, comparer)`, `do_compare(rhs, comparer)`, `check_phase`, `report_phase`, `queue.push_back/pop_front/size`, associative-array `exists/delete`.

**Forward references made:** coverage subscribers on the same streams (Module 08); CSR comparison with a register model (Module 09); integrated bench with the real retire monitor, drain time and a DUT that executes instructions (Module 10); constrained-random programs whose results the ISS predicts (Module 07).
