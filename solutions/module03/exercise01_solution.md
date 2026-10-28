# Module 03 / Exercise 01 — Solution

## Full solution code

```systemverilog
class mcpu_raw_hazard_seq extends uvm_sequence#(cpu_instr_item);
  `uvm_object_utils(mcpu_raw_hazard_seq)                       // TODO 3
  function new(string name = "mcpu_raw_hazard_seq");
    super.new(name);
  endfunction

  rand int unsigned n_pairs;
  constraint c_n { n_pairs inside {[1:8]}; }

  task body();
    cpu_instr_item producer, consumer;
    repeat (n_pairs) begin
      producer = cpu_instr_item::type_id::create("producer");
      // TODO 1
      start_item(producer);
      if (!producer.randomize() with { op inside {OP_ADD, OP_SUB, OP_AND, OP_OR}; rd != 0; })
        `uvm_error("RAND", "producer randomize failed")
      finish_item(producer);

      consumer = cpu_instr_item::type_id::create("consumer");
      // TODO 2
      start_item(consumer);
      if (!consumer.randomize() with { op inside {OP_ADD, OP_SUB, OP_AND, OP_OR}; rs1 == producer.rd; })
        `uvm_error("RAND", "consumer randomize failed")
      finish_item(consumer);
    end
  endtask
endclass
```

## TODO 1 — Producer: handshake, ALU op, `rd != 0`

`start_item` → randomise → `finish_item`, with the `randomize()` result checked. `rd != 0` is a hard constraint; the item's soft pool (`rd inside {[1:7]}`) remains satisfied, so `rd` is x1..x7.
**Wrong answers:** omit `rd != 0` (x0 producers occur only if the soft pool is dropped, which it is not here, but the requirement should be stated explicitly rather than depending on a soft default — a later constraint change would silently break the hazard); omit the `if (!...)` (a failed solve produces a stale item and no hazard, silently).

## TODO 2 — Consumer: `rs1 == producer.rd` (the subtle one)

Inside the `with` block, an unqualified identifier is looked up first among the fields of the object being randomised (`consumer`). `producer` is **not** a field of `cpu_instr_item`, so `producer.rd` resolves to the local variable, which is what we want; its `rd` was fixed when the producer was randomised and sent. The left side `rs1` resolves to `consumer.rs1`.
**Wrong answers and symptoms:**
- `rs1 == rd`: both names resolve to the consumer's own fields → always true, no constraint; consumer `rs1` is random; hazards occur only 1 time in 7 by luck. Nothing fails.
- Randomising the consumer **before** the producer is randomised (e.g. both created and randomised at the top of the loop, using `producer.rd` before it is solved): the producer's `rd` is still the default 0, so the consumer gets `rs1 == 0` every time. Symptom: every pair shows `rs1=x0` on the consumer.
- `start_item(producer); start_item(consumer);` interleaved: the second `start_item` blocks until the first item is finished → the sequence hangs.

## TODO 3 — Registration and constructor

`` `uvm_object_utils(mcpu_raw_hazard_seq) `` plus `new(string name = ...)` calling `super.new(name)`. A sequence is an object: **no parent argument**.
**Wrong answer:** `new(string name, uvm_component parent)` (component style) → compile error when the factory instantiates it; or omitting the macro → `type_id::create` does not compile.

## Self-review checklist

- [x] No `config_db`; no ports.
- [x] `super.new` called; sequences have no phases, so no `super.build_phase`.
- [x] Every `start_item` has a matching `finish_item`, sequentially.
- [x] `randomize()` return checked everywhere.
- [x] No `with`-block name clashes: `producer`/`consumer` are not item fields.
- [x] Types match (`cpu_instr_item`, `cpu_opcode_e`).

## Expected log (hand-derived, not simulated)

Values depend on the seed, so only properties can be derived. For a test that runs `rseq.randomize() with { n_pairs == 1; }` the stub driver prints two lines 10 ns apart:

```
@ t    [DRV] got OP_<ALU> rd=x<a> rs1=x<..> rs2=x<..> imm=0x...
@ t+10 [DRV] got OP_<ALU> rd=x<..> rs1=x<a> rs2=x<..> imm=0x...
```

with `<a>` in 1..7 (same register: producer `rd`, consumer `rs1`), both opcodes in {ADD, SUB, AND, OR}.

## The result that matters

Inside a `with` block the object being randomised shadows the enclosing scope: a constraint that refers to *another* object must name it explicitly, and a constraint that merely repeats a field name constrains nothing. Variation to try: add a third instruction whose `rs2` equals the producer's `rd` as well and use `local::` in one of the constraints to see the difference in readability.
