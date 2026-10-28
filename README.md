# UVM for CPU Verification — a 10-module course

Learn (or revise) UVM by verifying a small, fictional CPU called **`mini_cpu`**. Aimed at engineers with about two years of SystemVerilog and testbench experience who want the essentials plus the above-basic material a mid-level design-verification interview asks about.

Every module follows the same loop: **lesson → worked examples → exercises → solutions.**

> **Status:** all code is real UVM 1.2 (IEEE 1800.2-2017), written to be compile-consistent, but it has **not been run on a simulator**. Every log in the files is **hand-derived** and labelled as such. If something fails to compile, that is a bug in the course — please open an issue with the error message.

## Start here

1. Read [`module01-big-picture/architecture_overview.md`](module01-big-picture/architecture_overview.md). It explains the CPU from scratch and shows the UVM block diagram growing module by module.
2. Then work through the modules in order. Never skip ahead: later modules reuse names and code from earlier ones.

## The modules

| # | Topic | You will learn |
|---|---|---|
| [01](module01-big-picture/) | UVM big picture & testbench architecture | layered testbench, components vs objects, `run_test()`, first test |
| [02](module02-phases-objections-factory/) | Phases, objections, factory | phase order, ending a test, overrides |
| [03](module03-transactions-sequences/) | Transactions & sequences | instruction item, constraints, sequences, virtual sequences |
| [04](module04-driver-sequencer-monitor-agent/) | Driver, sequencer, monitor, agent | the handshake, active vs passive agents, config objects |
| [05](module05-config-connectivity/) | Configuration & connectivity | `uvm_config_db`, TLM ports, imps, FIFOs |
| [06](module06-scoreboard-reference-model/) | Scoreboard & reference model | retire-trace checking against an ISS |
| [07](module07-constrained-random-sequences/) | Constrained random & sequence strategies | `dist`, `solve before`, layered generators, seeds |
| [08](module08-functional-coverage/) | Functional coverage | covergroups, crosses, closure, assertions vs coverage |
| [09](module09-register-abstraction-layer/) | Register abstraction layer (RAL) | CSR model, adapter, mirror, frontdoor/backdoor |
| [10](module10-debug-integration-capstone/) | Debug, integration & capstone | integrated bench, reset, bug injection, regression, 25 interview Q&A |

## Layout

```
AUTHORING_SPEC.md          the rules the course was written to
PROGRESS.md                module status and the shared names used across modules
moduleNN-<topic>/
  README.md                the lesson (story first, then mechanics, code, pitfalls, interview angle)
  example01.sv, example02.sv   complete examples, each ending with a hand-derived expected log
  exercise01..03.md        fill-in, debug and design exercises (no answers here)
solutions/moduleNN/
  exerciseNN_solution.md   full solutions with reasoning and common wrong answers
  check_your_understanding.md
  MANIFEST.md              names and concepts each module defines
```

## How to study each module

1. Read the lesson's **story in plain words**, then the rest.
2. **Predict** the example's log from the code before reading the "Expected log" at the bottom of the file.
3. Do the exercises **before** opening the solutions.
4. Answer the interview questions out loud, then compare.

## Compiling the examples (optional)

- Any simulator with UVM 1.2 works; [EDA Playground](https://edaplayground.com) is free.
- Later examples reuse earlier ones with `` `include `` and a guard macro, so **compile from the example's own directory** (include-path handling differs between simulators; add `+incdir+` if needed).
- Selected tests of the integrated bench (Module 10) are chosen with `+UVM_TESTNAME=...`; `+MCPU_BUG_ADD` injects a bug in the DUT.

## What is deliberately not modelled

Traps and exceptions, interrupts actually being taken, error responses on the memory buses, an external data-memory protocol, and multi-issue or out-of-order cores. Module 10 lists them as risks in the capstone verification plan.
