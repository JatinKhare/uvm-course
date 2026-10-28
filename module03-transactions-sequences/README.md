# Module 03 — Transactions & Sequences

> Prerequisites: Modules 01–02 (components vs objects, phases, objections, factory `create`), SystemVerilog constrained randomisation basics.
> What this module gives you: the stimulus side of UVM — how one CPU instruction is modelled as a randomisable object, how sequences generate streams of them, and how virtual sequences coordinate several interfaces.

UVM 1.2 only. Logs are hand-derived. Labels: **PORTABLE UVM CONCEPT**, **SIMULATOR/VERSION-DEPENDENT**.


---

## Concept

### The story in plain words (start here)

Think of a **restaurant**. A customer wants a meal; a cook cooks it; in between there is a system for passing the order along.

| Restaurant | UVM name | What it is |
|---|---|---|
| One **order slip** ("1× ADD x3,x1,x2") | **sequence item** (`cpu_instr_item`) | one instruction, written down |
| The **waiter's plan** for the table ("starter, main, dessert") | **sequence** | a recipe that produces a *list* of slips |
| The **pass / ticket rail** where slips queue | **sequencer** | hands one slip at a time to the cook |
| The **cook** who actually cooks | **driver** (Module 4) | turns a slip into real activity on the wires |

The crucial idea: **the waiter doesn't know how the cook works, and the cook doesn't know what the customer wants.** So you can change the menu (new sequence) without touching the kitchen (driver), or rebuild the kitchen without rewriting menus. That separation of *what* (sequence) from *how* (driver) is the whole point of this module.

**And "random"?** Instead of typing every order by hand, you describe the *rules* ("any ALU instruction, any register from x1 to x7, never write to x0") and let the simulator roll dice **within those rules**. Those rules are called **constraints**. Rules keep every roll *legal*; the dice make it *varied*.


### Separate *what* from *how*

A transaction is one meaningful unit at a level above pins: "ADD x3,x1,x2", "write 0xDEADBEEF to 0x100". The UVM stimulus stack keeps three jobs apart:

| Layer | Class | Knows about | Lifetime |
|---|---|---|---|
| Transaction | `uvm_sequence_item` (our `cpu_instr_item`) | what one instruction is; legality constraints | per instruction |
| Scenario | `uvm_sequence` | which instructions, in what order and mix | per scenario, started on a sequencer |
| Delivery | `uvm_sequencer` + `uvm_driver` (Module 04) | arbitration, pin-level protocol | whole simulation (components) |

Changing a scenario means writing a new sequence; changing the bus protocol means changing only the driver. Both are objects/components you can swap without touching the other.


### The instruction item: `cpu_instr_item`

Defined once here (`example01.sv`) and reused by every later module. Fields: opcode `op` (enum `cpu_opcode_e`: ADD, SUB, AND, OR, ADDI, LW, SW, BEQ, CSRRW), registers `rd`, `rs1`, `rs2`, and a 12-bit `imm`. An `encode()` function produces the RV32I-style 32-bit word the fetch bus will carry. Not every field is meaningful for every opcode (a SW has no `rd`; an ADD has no `imm`); the item constrains unused ones, and `do_compare` compares the **encoding**, so unused fields never cause false mismatches.

**Where constraints belong:**

| Constraint kind | Lives in | Example |
|---|---|---|
| Legality — always true, regardless of scenario | the item | word-aligned LW/SW offset; CSR address from a valid set |
| Preference — usually true, scenario may override | the item, as `soft` | register pool x1..x7 |
| Scenario — true for this test only | the sequence or an inline `randomize() with {}` | "this instruction is a LW from x4" |


### Sequences and the sequencer

A sequence is a `uvm_object` with a `body()` task. It is **started on** a sequencer (`seq.start(seqr)`), which arbitrates between competing sequences and passes items to the driver. A sequence has no position in the component hierarchy; it can be started on any compatible sequencer, nested inside another sequence, or run in parallel with others.


### Virtual sequences

**In plain words:** a virtual sequence is a **conductor**. It plays no instrument itself; it tells the violins (the instruction sequencer) and the drums (the data-memory sequencer) when to start. Our example: first have the drums set up the data memory, *then* let the violins play the program.


A CPU testbench has more than one interface. "LW after SW to the same address" needs the data memory preloaded (load/store side) *and* an instruction stream (fetch side). A **virtual sequence** has no item type of its own; its `body()` starts real sequences on real sequencers. The **virtual sequencer** is a plain `uvm_sequencer` that only carries handles to those real sequencers. The sequence reaches them through `p_sequencer`.


---

## UVM Mechanics

### `uvm_sequence_item`

Inherits from `uvm_object` (through `uvm_transaction`): constructor takes only a name; register with `` `uvm_object_utils ``; create with `type_id::create("name")` so the factory can substitute subclasses (e.g. an item that adds error injection).

**Printing/copying/comparing.** UVM offers `` `uvm_field_* `` macros that auto-generate copy/compare/print/pack. This course **mentions and avoids** them in production examples: they hide behaviour, cost simulation speed, and are awkward for enums and conditional fields. Instead implement the hooks:

| Hook | Called by | Notes |
|---|---|---|
| `do_copy(uvm_object rhs)` | `copy()` | `$cast` rhs, call `super.do_copy(rhs)` first |
| `do_compare(uvm_object rhs, uvm_comparer comparer)` | `compare()` | return 1 on match; combine with `super.do_compare` |
| `convert2string()` | your own logs | returns one line |


### Randomisation rules you rely on (**PORTABLE**, SystemVerilog)

**Intuition first — a dice game with rules.** `rand` marks a variable as "a die". A `constraint` is a rule of the game. `randomize()` rolls all the dice at once so that **every rule is satisfied**. Tiny example with two dice `op` and `imm`:

```
rand op  : ADD, LW, SW       rule A:  op == LW  ->  imm must be a multiple of 4
rand imm : 0..7
roll 1:  (ADD, 5)  ok          roll 2:  (LW, 4)  ok          never:  (LW, 5)  -- breaks rule A
```

Two things surprise beginners, so remember them now: **(1)** a variable *without* `rand` is not a die — it is a **fixed number** that the rules must respect; **(2)** a `soft` rule is a *preference*: "try x1..x7, but if a stronger rule disagrees, drop the preference".


- Only `rand`/`randc` variables are solved. A non-`rand` variable mentioned in a constraint is treated as a **constant** — it silently prunes the random variables (a classic bug; see Pitfalls).
- `soft` constraints are dropped if they conflict with a hard constraint; hard constraints that conflict with each other make `randomize()` return 0.
- On failure `randomize()` returns 0, fields keep their previous values, and a simulator-specific message is printed. **Always check the return value.**
- `randomize() with { ... }` adds inline constraints. Inside the block, identifiers are first looked up as fields of the object being randomised; use `local::name` (or differently named arguments) to refer to the enclosing scope.


### Sequence execution model

**The conversation, in plain words** (sequence = S, sequencer = Q, driver = D):

```
S: "I'd like to send an instruction."            -> start_item(item)    (S waits until Q says go)
Q: "Go ahead, you have the slot."
S: fills in the item with random values.         -> randomize()
S: "Here it is."                                 -> finish_item(item)   (S now WAITS)
D: "Next one please."                            -> get_next_item(req)  (D receives the item)
D: ...wiggles the wires...
D: "Done with it."                               -> item_done()         (S is released, can send the next)
```

If you remember one thing: **the sequence is stuck in `finish_item` until the driver says `item_done`.** Most "my test hangs" bugs are a broken link in this little conversation.


`seq.start(sequencer)` runs, in the caller's thread: `pre_start`, `pre_body`, **`body()`**, `post_body`, `post_start` (`pre_body`/`post_body` only run when `call_pre_post` is 1, the default for a top-level `start`). It blocks until `body()` returns.

Inside `body()`, one item goes through:

1. `item = T::type_id::create("name")`
2. `start_item(item)` — blocks until the sequencer grants this sequence a slot (arbitration).
3. randomise or fill the item — **between** `start_item` and `finish_item`, so it is generated at the moment it will be sent ("late randomisation").
4. `finish_item(item)` — sends it to the driver and **blocks until the driver calls `item_done()`**.

The `` `uvm_do `` / `` `uvm_do_with `` macros wrap these four steps. The explicit form is used here because interviewers ask what the macros expand to, and because the explicit form lets you check `randomize()`.


### `m_sequencer` and `p_sequencer`

Every sequence has `m_sequencer` (type `uvm_sequencer_base`, set by `start`). `` `uvm_declare_p_sequencer(SEQUENCER) `` declares a typed `p_sequencer` handle and a setter that `$cast`s `m_sequencer` when the sequence starts. Starting such a sequence on a sequencer of a different type is a fatal at start time (message text **SIMULATOR/VERSION-DEPENDENT**). Using `p_sequencer` ties the sequence to that sequencer class — acceptable for virtual sequences (they exist to reach sibling sequencers), but avoid it in reusable, item-producing sequences.


### Virtual sequencer wiring

`mcpu_vseqr` has two plain handles, `ifetch_seqr` and `lsu_seqr`. Nothing populates them automatically: the **test** (or env) assigns them in `connect_phase`, after all sequencers exist. A missing assignment leaves a null handle that only shows up when the virtual sequence calls `start` on it.


---

## Code Walkthrough

### 1. The item (`example01.sv`)

```systemverilog
rand cpu_opcode_e op;
rand bit [4:0]    rd, rs1, rs2;
rand bit [11:0]   imm;
constraint c_small_regs { soft rd inside {[1:7]}; soft rs1 inside {[1:7]}; soft rs2 inside {[1:7]}; }
constraint c_unused_rd  { (op inside {OP_SW, OP_BEQ}) -> rd == 0; }
constraint c_align      { (op inside {OP_LW, OP_SW}) -> imm[1:0] == 2'b00; }
constraint c_csr        { (op == OP_CSRRW) -> imm inside {12'h300, 12'h305, 12'h341}; }
```

Small register pool = high hazard density (instructions often reuse the same registers) — a deliberate CPU-DV trade-off. The pool is `soft` so a directed instruction may use `x0` (`ADDI x1,x0,5`), and `c_unused_rd` is hard, which beats the soft constraint for stores and branches. `encode()` follows the RV32I layouts (R: funct7|rs2|rs1|funct3|rd|opcode; I: imm|rs1|funct3|rd|opcode; S splits `imm` into `[11:5]` and `[4:0]`; B scatters offset bits).


### 2. A directed instruction through `randomize() with`

```systemverilog
task send_instr(cpu_opcode_e o, bit [4:0] d, s1, s2, bit [11:0] i);
  it = cpu_instr_item::type_id::create("it");
  start_item(it);
  if (!it.randomize() with { op == o; rd == d; rs1 == s1; rs2 == s2; imm == i; })
    `uvm_error("RAND", "randomize failed for directed instruction")
  finish_item(it);
endtask
```

The argument names `o, d, s1, s2, i` are chosen **not** to collide with the item's field names. Had they been `op, rd, ...`, `op == op` would resolve to the item's own field on both sides (always true) and the instruction would be random (see Pitfalls; `local::op` is the alternative). All five fields are pinned, so the result is deterministic and the hand-derived log in the file is exact: `ADD x3,x1,x2` encodes to `0x002081b3`.


### 3. The handshake in time

The stub driver holds every item for 10 ns before `item_done()`. `finish_item` therefore returns 10 ns after the item was sent; the directed sequence's 4 items take 40 ns; `start` returns at 40; the random sequence (2 items) ends at 60; the test drops its objection at 60. A sequence's duration is whatever its driver makes it.


### 4. A random sequence

```systemverilog
repeat (n_instr) begin
  it = cpu_instr_item::type_id::create("it");
  start_item(it);
  if (!it.randomize()) `uvm_error("RAND", "randomize failed")
  finish_item(it);
end
```

Creating a **new item per iteration** matters: once Module 04's monitors and scoreboards hold handles to items, reusing one object would overwrite data they still reference. `n_instr` is itself `rand`, so the test can pin it (`rseq.randomize() with { n_instr == 2; }`) or leave it free.


### 5. A virtual sequence (`example02.sv`)

```systemverilog
class mcpu_lw_after_sw_vseq extends uvm_sequence;
  `uvm_declare_p_sequencer(mcpu_vseqr)
  task body();
    ...
    pre.start(p_sequencer.lsu_seqr);        // memory preload first
    prog.start(p_sequencer.ifetch_seqr);    // then the program
  endtask
endclass
```

The program does `ADDI x4,x0,0x100; ADDI x3,x0,42; SW x3,0(x4); LW x5,0(x4)`. The memory at `0x100` is preloaded with `0xDEADBEEF` and its neighbour `0x104` with `0x12345678`, so a DUT that forwards the SW data correctly returns 42 and a DUT that reads stale memory or the wrong word returns something recognisably different. The preload takes 20 ns (two items), the program 40 ns more: per the hand trace the program starts at 20 and the objection drops at 60. Run the two sequences in a `fork ... join` instead and they would overlap — the right choice only if the scenario does not depend on the preload finishing first.


---

## Common Pitfalls

- **`randomize()` return value ignored and a constraint conflict** → items arrive with default field values (`OP_ADD x0,x0,x0`, imm 0), repeated; the simulator prints a randomisation-failure message that is easy to miss → the item keeps previous values when solving fails; check the return and `uvm_error`.
- **Field not declared `rand`** → that field is a constant 0 in every item; if a constraint mentions it, it silently restricts other fields (e.g. `c_csr` with a non-rand `imm = 0` means `OP_CSRRW` is never generated) → only `rand` variables are solved; non-rand ones act as constants.
- **Name clash in `randomize() with`** (`rd == rd`) → "directed" instruction is random → the inner name resolves to the item's field; use differently named arguments or `local::`.
- **`start_item` without `finish_item`** → driver never receives the item; the sequence or the test appears stuck or ends with no stimulus → the item is only sent at `finish_item`.
- **Sequencer–driver mismatch of item types** → compile error, or a runtime cast failure when the sequencer receives a different item type (text library-specific) → `uvm_sequencer#(T)` and `uvm_driver#(T)` must agree.
- **Virtual sequencer handles never assigned** → null handle passed to `start` at the first sub-sequence (error text tool/library-specific) → assign handles in `connect_phase` and, as a habit, check them in `end_of_elaboration_phase`.
- **Randomising before `start_item`** → works with a single sequence, but constraints that read state (previous item, DUT state) can use stale values when arbitration delays the grant → randomise between `start_item` and `finish_item`.
- **Reusing one item handle across loop iterations while a consumer keeps the handle** → later items overwrite earlier ones in the scoreboard → create a new item per transaction.


---

## Interview Angle

**Q1. What is the difference between a sequence item and a sequence?**
An item is one transaction (an instruction); a sequence is a procedure that generates many of them. Both are `uvm_object`s, but only items are sent to the driver. A sequence is started on a sequencer and runs its `body()`.

**Q2. What do `start_item` and `finish_item` do, and where do you randomise?**
`start_item` requests and waits for the sequencer's grant; `finish_item` delivers the item to the driver and blocks until `item_done`. Randomise between them so the item reflects the state at send time. `uvm_do` is the macro form.

**Q3. What is a virtual sequence and why do you need one?**
A sequence that coordinates sequences on several sequencers. For a CPU: preload data memory, set up an interrupt pattern, and run the instruction stream — different interfaces, one scenario. It runs on a virtual sequencer that only holds handles to the real ones.

**Q4. `p_sequencer` vs `m_sequencer`?**
`m_sequencer` is the generic base-class handle set by `start`; `p_sequencer` is a typed handle declared by `` `uvm_declare_p_sequencer `` that `$cast`s it. Use `p_sequencer` when the sequence needs sequencer-specific members; it couples the sequence to that sequencer type.

**Q5. Why avoid `uvm_field_*` macros?**
They hide the generated code, slow simulation, and are clumsy for conditional or enum fields. Hand-written `do_copy`, `do_compare`, and `convert2string` are explicit, faster, and let `do_compare` compare what actually matters (here, the encoding).

**Q6. My randomised instructions are all the same / my constraint has no effect. What do you check?**
The `randomize()` return value (conflict), whether the fields are `rand`, name-shadowing inside `with {}`, and whether another constraint (including a `soft` one that you assumed was hard) wins. Then `constraint_mode`/`rand_mode` settings.


---

## Recap in five lines

1. **Item** = one order slip (an instruction); **sequence** = a plan producing slips; **sequencer** = the queue; **driver** = the cook.
2. **Constraints** are the rules of a dice game: legality in the item, scenario in the sequence or an inline `with { }`.
3. A variable without `rand` is a **fixed number** — it silently restricts the dice that *are* random.
4. The sequence is blocked in `finish_item` until the driver calls `item_done`.
5. A **virtual sequence** is a conductor: it starts real sequences on several sequencers.

**Questions beginners often ask**
- *"Why are all my 'random' instructions identical?"* — `randomize()` probably failed (conflicting rules) and the item kept its default values; always check its return value.
- *"Why is my 'directed' instruction random?"* — a name clash inside `with { }` (`rd == rd`); use differently named arguments or `local::`.
- *"Why do I see x0 even though I wrote x1..x7?"* — that rule is `soft`; a directed instruction may override it on purpose.


---

## Check Your Understanding

1. Why is the random item randomised between `start_item` and `finish_item`, and when would randomising earlier produce wrong stimulus?
2. In the `c_csr` constraint, `imm` is a `rand` field. Suppose it were not `rand` and held 0. What would be generated for `op`, and why?
3. Derive by hand the encoding the driver prints for the directed `SW x3,0(x4)`. Which item fields does `encode()` ignore for that opcode?

Answers: `solutions/module03/check_your_understanding.md`.


---

## Exercises

| File | Type | Summary |
|---|---|---|
| `exercise01.md` | Fill-in | Write a read-after-write hazard sequence: a producer ALU instruction followed by a consumer whose `rs1` equals the producer's `rd`. Subtle scoping trap. |
| `exercise02.md` | Debug the testbench | Two symptoms: a "directed" sequence that sends identical NOP-like items, then a random sequence that never produces CSR instructions and always has `imm = 0`. |
| `exercise03.md` | Design | Design the stimulus for verifying that a load after a store to the same address forwards correctly. |


---

## Reference

**Classes:** `uvm_sequence_item`, `uvm_sequence#(REQ,RSP)`, `uvm_sequence`, `uvm_sequencer#(REQ,RSP)`, `uvm_sequencer`, `uvm_driver#(REQ,RSP)`, `uvm_comparer`, `uvm_object`.

**Macros:** `` `uvm_object_utils ``, `` `uvm_component_utils ``, `` `uvm_declare_p_sequencer ``, `` `uvm_do `` / `` `uvm_do_with `` (mentioned), `` `uvm_field_* `` (mentioned, avoided), `` `uvm_error ``, `` `uvm_fatal ``, `` `uvm_info ``.

**Methods:** `start_item(item)`, `finish_item(item)`, `body()`, `seq.start(sequencer)`, `randomize() with {}`, `do_copy`, `do_compare`, `convert2string`, `copy()`, `compare()`, `seq_item_port.get_next_item/item_done`, `seq_item_port.connect(seqr.seq_item_export)`, `p_sequencer`, `m_sequencer`.

**Forward references made:** driver handshake in depth, monitors, agents (Module 04); constraint strategies, `solve before`, `dist`, seeding (Module 07); coverage of opcodes/hazards (Module 08); CSR instructions and the register model (Module 09).
