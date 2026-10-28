# Module 03 — Check Your Understanding: Answers

## 1. Randomise between `start_item` and `finish_item`

`start_item` returns only when the sequencer grants this sequence a slot; with several sequences running (or a lock/priority in play) that can be later than the call. Randomising after the grant means the item's content is chosen at the moment it will actually be sent, so constraints that depend on current state — the previous item, a counter, something read from the DUT or a model — use fresh values. Randomising earlier gives stale-state stimulus: for example a "branch to the address of the last store" item whose reference value changed while the sequence waited for arbitration. With a single sequence and stateless constraints both orders behave identically, which is why the bug stays hidden.

## 2. Non-`rand` `imm` in `c_csr`

A non-`rand` variable is a constant during solving. With `imm == 0` the implication `(op == OP_CSRRW) -> imm inside {0x300, 0x305, 0x341}` becomes `(op == OP_CSRRW) -> false`, which can only be satisfied by `op != OP_CSRRW`. So `OP_CSRRW` is never generated, `imm` stays 0 everywhere, and `randomize()` still returns 1: the constraint is legal, just constant.

## 3. SW encoding and ignored fields

S-type layout: `imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode`. For `SW x3,0(x4)`: `imm=0`, `rs2=3`, `rs1=4`, `funct3=010`, opcode `0100011`.

```
0000000 | 00011 | 00100 | 010 | 00000 | 0100011
= 0000 0000 0011 0010 0010 0000 0010 0011 = 0x00322023
```

`encode()` ignores `rd` for SW (stores write no register; the item forces `rd == 0` anyway). Other opcodes ignore other fields: ADD/SUB/AND/OR ignore `imm`; ADDI, LW and CSRRW ignore `rs2`; BEQ ignores `rd`. This is why `do_compare` compares encodings.
