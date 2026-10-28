# Module 03 / Exercise 01 — Read-after-write hazard sequence (fill-in)

**Type:** Fill-in. SV/UVM-compile-checkable by inspection.

## Goal

Write `mcpu_raw_hazard_seq`: a sequence that sends `n_pairs` back-to-back pairs of instructions. In each pair the second instruction (the **consumer**) reads, in its `rs1`, the register the first instruction (the **producer**) just wrote. This is the stimulus for exercising the CPU's operand-forwarding/hazard logic.

## Setup / DUT assumptions

- Use `cpu_instr_item`, `cpu_opcode_e`, the constraints and `mcpu_ifetch_seqr` from `module03/example01.sv`. Items go through a sequencer to a driver (stub driver there); you only write the sequence.
- Register `x0` is hard-wired to zero in the DUT, so a producer that writes `x0` creates no real hazard.
- ALU ops here means `OP_ADD`, `OP_SUB`, `OP_AND`, `OP_OR`.

## Skeleton

```systemverilog
class mcpu_raw_hazard_seq extends uvm_sequence#(cpu_instr_item);
  // TODO 3: make the class creatable by the factory, with the standard sequence constructor
  // YOUR CODE HERE

  rand int unsigned n_pairs;
  constraint c_n { n_pairs inside {[1:8]}; }

  task body();
    cpu_instr_item producer, consumer;
    repeat (n_pairs) begin
      producer = cpu_instr_item::type_id::create("producer");
      // TODO 1: send the producer through the sequencer: an ALU op that writes a real register
      // YOUR CODE HERE

      consumer = cpu_instr_item::type_id::create("consumer");
      // TODO 2: send the consumer: an ALU op whose rs1 is the register the producer wrote
      // YOUR CODE HERE
    end
  endtask
endclass
```

## A correct answer must achieve

1. Every item is sent with the full sequencer handshake, producer completely before consumer.
2. Producer: ALU opcode, `rd != x0`.
3. Consumer: ALU opcode, `rs1` equals the producer's `rd` **by constraint**, not by luck.
4. A failed randomisation is reported through UVM, never ignored.
5. For any seed, across all pairs, `consumer.rs1 == producer.rd` and `producer.rd != 0`.

Compare against `solutions/module03/exercise01_solution.md`.
