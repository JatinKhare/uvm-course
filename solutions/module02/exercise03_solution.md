# Module 02 / Exercise 03 — Solution

## Full solution code

Not applicable (prediction exercise). The ordered log is below.

## Prediction walk-through

**Build (top-down, time 0):** test, then env (creates agent), then agent.
**Connect (bottom-up, time 0):** agent, then env, then test.
**Run:** test raises at 0, agent raises at 0, env raises nothing.
- Test finishes at **10** (logs, drops). Agent still holds its objection → phase continues.
- Env tick 1 at **15** (env has no objection, but the phase is still open because of the agent).
- Agent finishes at **20** (logs, drops). Total is now 0, drain time is 0 → the phase ends at 20 and kills all remaining `run_phase` tasks, including env's, which was waiting for its 35 ns tick.
**Report (bottom-up, time 20):** agent, env, test.

## Expected log (hand-derived, not simulated)

```
@ 0   [P] test build
@ 0   [P] env build
@ 0   [P] agent build
@ 0   [P] agent connect
@ 0   [P] env connect
@ 0   [P] test connect
@ 10  [P] test run done
@ 15  [P] env tick 1
@ 20  [P] agent run done
@ 20  [P] agent report
@ 20  [P] env report
@ 20  [P] test report
```

(a) **Never prints:** `env tick 2` (35 ns). It is in a task that gets killed at 20 ns.
(b) **Report time:** 20 ns. The phase ended when the last objection dropped (agent, 20 ns) with zero drain; report phase starts immediately after at the same time.

## Self-review checklist

- [x] build is top-down; connect and report are bottom-up.
- [x] The run phase length equals the latest objection drop (agent, 20), not the test's (10).
- [x] A component with no objection does not extend the phase.
- [x] Killed tasks print nothing after phase end.
- [x] No undeclared identifiers in the given code.

## The result that matters

The run phase lasts exactly as long as the **last** objection holder, and everything else is just along for the ride: env's first tick survives because the agent happens to be busy, its second does not. Variation to try: add `phase.phase_done.set_drain_time(this, 20ns)` in the test's `run_phase` and redo the prediction (tick 2 now prints at 35; report at 40).
