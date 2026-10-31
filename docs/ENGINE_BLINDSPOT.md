# Finding: NeuroAssist's gate passes biased estimates between about 0.2 and 1.5 deg/s

Found while building this benchmark. Reproduce: the script that wrote
`benchmark/results/engine-blindspot.json` (100 SYNTHETIC recordings per row, NeuroAssist simulator,
noise 0.1°, 30 fps, 10 s, NeuroAssist engine `neurocore-0.4.0` unchanged).

| true SPV (deg/s) | gate passes | mean abs error | mean 95% half-width | 95% interval contains truth |
|---|---|---|---|---|
| 0 | 96% | 0.05 | ±0.14 | 97% |
| 0.2 | 100% | 0.17 | ±0.15 | 38% |
| 0.4 | 93% | 0.33 | ±0.19 | 13% |
| 0.6 | 80% | 0.50 | ±0.25 | 5% |
| 0.8 | 31% | 0.60 | ±0.33 | 0% |
| 1 | 17% | 0.48 | ±0.39 | 18% |
| 1.5 | 5% | 0.21 | ±0.36 | 40% |
| 2 | 36% | 0.08 | ±0.22 | 92% |
| 2.5 | 94% | 0.07 | ±0.20 | 96% |
| 3–8 | 99–100% | 0.06–0.08 | ±0.19–0.20 | 97–98% |

**What happens.** The simulator's fast phase resets the eye by 0.45 × SPV × 0.5 s in 0.05 s. Below
about 2 deg/s that reset is slower than the fast-phase detector's floor (15 deg/s deviation from the
local median), so it is not detected. Each 0.5 s fit window then spans a whole slow-phase period
including its undetected reset, and the fitted slope is pulled toward zero. The linearity check
(residual ≤ 1.25 × noise) catches this only once the reset is large compared with the noise
(above about 0.8 deg/s). Between 0.2 and 0.6 deg/s the gate passes and the reported interval excludes
the true value most of the time.

**Why it matters.** The gate's promise is "a number, or an abstention". In this range it gives a
confident wrong number. The result is on NeuroAssist's own simulator, whose fixed 0.5 s period and
reset shape are idealised, so the size of the effect on real eyes is unknown.

**Smallest fix to try in NeuroAssist** (not done here; parent repositories are not modified):
fit windows that do not span a whole slow-phase period, or add a check that the window length is
shorter than the median inter-fast-phase interval, and abstain otherwise.

**Effect on this benchmark.** Subjects are generated at |SPV| ≥ 2.6 deg/s, where the engine is
accurate (coverage 96–98%). The benchmark therefore says nothing about the 0.2–2 deg/s range.
