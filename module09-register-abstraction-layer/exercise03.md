# Module 09 / Exercise 03 — CSR verification plan with the register layer (design)

**Type:** Design / interview write-up. No code to compile; deliverable is a written plan with short SV sketches where noted.

## Scenario

*"You are verifying the CSRs of `mini_cpu`: `mstatus`, `mtvec`, `mepc`, `mcause`. They are readable and writable through a debug register port (frontdoor, modelled with RAL) and also by CSR instructions executed by the CPU. `mepc` and `mcause` are updated by hardware when a trap is taken. Describe your CSR verification environment and tests."*

## Deliverables

1. **Model review checklist:** what you check in the register model itself (before running any DUT), with three items that could be wrong in the model.
2. **Test list:** at least seven tests (name + what it proves), including which built-in sequences you use and where you must write your own.
3. **Prediction architecture:** auto-predict versus predictor, where the monitor sits, and how the mirror learns about (a) writes through the debug port, (b) CSR instructions executed by the CPU, (c) hardware updates of `mepc` and `mcause` at a trap. Draw the connections.
4. **Two access paths:** how you verify that a CSR written by instruction is seen identically through the register port, and vice versa. What do you compare, and with what reference?
5. **Backdoor use:** two good uses and two cases where backdoor access would be wrong.
6. **Reset:** how the model and mirror behave when the DUT is reset mid-test.
7. **Coverage:** field-level and access-level coverage you would collect; one cross.
8. **Failure triage:** a mirror check fails on `mstatus` bit 3. List, in order, what you check (model, adapter, DUT, test) and how.

## Constraints

- `mini_cpu_if` stays unchanged; the register port is the separate `mini_cpu_csr_if` of this module.
- State which parts rely on the simulator-dependent backdoor DPI.
- The reference for architectural CSR behaviour is the ISS of Module 06; say how the two models (ISS CSR array and the register model) are kept consistent.

Compare against `solutions/module09/exercise03_solution.md` (one reference design).
