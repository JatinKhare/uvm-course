# Module 08 / Exercise 03 — Coverage plan for hazards and interrupts (design)

**Type:** Design / interview write-up. No code to compile; deliverable is a written plan with short covergroup and assertion sketches.

## Scenario

The interviewer asks: *"Write the functional coverage plan for the data-hazard handling and the interrupt handling of an in-order, single-issue core like `mini_cpu`. Tell me what you sample, from where, what crosses you would build, which you would exclude, and how you would close it."* The core has a three-instruction hazard window, a load-use case, branches, a single interrupt line `irq`, and a retire trace. Interrupts are taken at instruction boundaries.

## Deliverables

1. **Plan table:** at least eight plan items, each with the coverpoint/cross that implements it and its bins.
2. **Sampling points:** for each covergroup, the component and event that samples it, and why not the driver.
3. **Crosses:** the two or three crosses you consider essential (with the bin counts, and why not a larger cross). State one cross you deliberately do **not** build.
4. **Exclusions:** two `ignore_bins`/`illegal_bins` with the written reason each, and one case where you would use `illegal_bins` rather than `ignore_bins`.
5. **Assertions paired with coverage:** two assertions and the matching `cover property` for each.
6. **Closure strategy:** the loop, the data you merge, how you bias the generator (name the Module 07 mechanisms), and the stop criteria.
7. **Failure of the plan:** two ways the coverage model could report a healthy number while the design is unverified.

## Constraints

- All crosses must be closable: say the number of bins and estimate how you would reach them.
- Use only retire/bus monitor data and the interrupt line as sampling sources (no internal RTL signals except in assertions).
- Keep each covergroup's cross under about 100 bins.

Compare against `solutions/module08/exercise03_solution.md` (one reference plan).
