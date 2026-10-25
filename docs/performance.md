# Motion performance

## Settled vehicles below 5 km/h

Below 5 km/h in either direction, a carriage continues its normal suspension response until procedural amplitude, curve lean, and both response velocities have settled. Subsequent callbacks emit the neutral animation times directly, skipping track response, maintenance response, speed-envelope evaluation, and waveform preparation/evaluation. The original transformator still runs.

The damping clock remains current during idle callbacks, so reaching 5 km/h after a long stop or crawl still eases into motion. Pauses and clock rewinds retain the existing response semantics. On and Speedless Sway both use this idle shortcut. Speedless Sway targets full procedural amplitude from 5 km/h, with the same time-based damping and distance-based waves; curve lean still uses actual speed. Developer isolation with the speed envelope disabled also retains the 5 km/h cutoff.

## Shared waveform calculations

Long consists can reuse distance-dependent sine/cosine pairs within each Lua context and motion profile. Each carriage retains its individual phase, facing, lag, section geometry, track spectrum, and suspension response. The distance cache is keyed by consist independently of phase selection: the default per-carriage long waves and experimental common consist phase use the same sharing mechanism. Phase rotations are prepared once and reused in place; changing distance does not allocate carriage or section objects. Cached coefficients contain only fixed phase, support geometry, facing, and wave weights. Live short/long spectrum weights are applied during evaluation, so track-response smoothing does not rebuild the coefficients every frame.

Sharing requires enabled secondary motion, at least 20 carriages, and observed reuse of exact raw/signed distance coordinates in that context. Roll-only motion and smaller consists use the direct evaluator because preparation overhead was not amortised in those benchmark cases. Contexts seeing changing inputs without reuse also use direct evaluation. Both paths represent the same waves, with ordinary floating-point rounding differences; neither relies on a leading-carriage update, worker affinity, interpolation, or waveform history.

With irregularity enabled, matching carriages share four distance-dependent trigonometric evaluations for the long and third waves per profile and coordinate pair in a context. With all axes enabled, each section additionally evaluates three sines at the variable short wave's centre and front/rear supports. Direct evaluation needs seven trigonometric evaluations per section. With irregularity disabled, the original six-evaluation shared and direct paths remain available. Static phase construction has a separate initial cost. Disabled waves contribute zero and skip their distance-dependent trigonometry. Geometry and waveform caches use the existing bounded-cache implementation, with capacity limits per motion profile.

Curve and track-quality queries have independent sampling intervals. Curve sampling defaults to 1 m; distance intervals reuse only averaged curvature, while speed, orientation, and suspension damping remain current. **Frame** remains available for a fresh curvature query on every update at or above 5 km/h. Track-quality sampling defaults to 5 m. Dropping below 5 km/h and clock rewinds invalidate cached curvature, so resuming motion or rewinding queries fresh geometry.

## Irregular profiles

The lateral and vertical profiles use bounded, deterministic value noise at two spatial scales. Quintic interpolation preserves continuous slope and curvature at cell boundaries. The contribution is proportional to the unused amplitude range, so the existing profile limits remain intact without introducing a clipping step. Front and rear vertical inputs are perturbed separately before deriving their average and difference; both support values are retained even when only pitch or heave is enabled.

The short wave's phase also receives a bounded, smooth displacement from a separate seeded profile. Its derivative remains between 0.889375 and 1.110625 of the nominal phase rate, preserving forward progression and bounding local wavelength to approximately 90–112.5% of nominal. The displacement is a pure function of position, without a phase accumulator. Front and rear support positions are evaluated independently because fixed half-wave rotations would cease to represent the same vertical profile after changing the spacing.

Each active carriage lazily allocates six small coefficient caches and their container, then reuses them across sections and frames. These cover amplitude and spacing at the lateral, front, and rear samples. Each cache holds fine and broad cell coefficients. Seeds and cell coordinates fully determine the cached values; callback order, clock changes, distance jumps, and isolated Lua contexts do not change the resulting profile. There are no extra native queries, random-number generator calls, or allocations on warm moving frames. Settled carriages skip this work entirely.

Setting Roll balance to Off skips lateral amplitude and spacing sampling, the centre sine, and roll blending even while pitch or heave remains active. The direct secondary-motion helper also skips this unused roll work. Both vertical support samples remain necessary for coherent pitch and heave; curve lean is still controlled separately.

## Standalone benchmark

Run from the repository root:

```sh
lua scripts/benchmark_motion.lua 250
```

The script measures 1,000 vehicles, reports median CPU time from three runs, and checks separate roll, heave, and pitch pose checksums. It uses the generated configuration's `carriageLag` mode and prints the selection. The stationary case compares the actual controller's forced full path with its settled shortcut, reusing its capture table. Moving cases compare direct and shared evaluation for 1, 7, 20, and 100 cars per consist in one or ten isolated Lua contexts. Extra cases exercise a spectrum that changes every frame during track-response smoothing and check that roll-only motion bypasses sharing. Geometry/phase caches are warmed before timing. An optional second argument supplies a saved motion module for the direct reference evaluator; its sharing preparation is not called, and it must support the selected phase mode.

The review found that folding live spectrum weights into cached coefficients made changing-track cases about 20–27% slower than direct evaluation. Keeping those coefficients fixed removes that rebuild cost. A subsequent run with 250 callbacks per vehicle measured about 62% less Lua controller CPU for settled idle and about 4–13% less evaluator CPU for moving 20/100-car consists, across both steady and changing spectra. Those measurements used the experimental common phase with 20 m carriage lag. Small-consist and roll-only cases retain direct motion maths; their benchmark loops, including eligibility checks, were about 2–3% slower than direct reference loops. Results depend on callback distribution and configuration; this is a tradeoff to assess in the game, not a guaranteed improvement for every vehicle.

The variable-spacing build was compared with the preceding amplitude-irregularity build on Lua 5.2.4, using 120 callbacks per vehicle, median timings from three runs, and default independent carriage phases. Full-axis evaluation across 1-, 20-, and 100-car consist cases increased from about 0.33 seconds to 0.50–0.51 seconds; roll-only evaluation increased from 0.158 to 0.219 seconds. That adds approximately 1.4 ms per update of 1,000 moving carriages with all axes enabled, or 0.5 ms for roll only. The current evaluator totals approximately 4.1–4.3 ms and 1.8 ms respectively per 1,000-carriage update. The settled path is unchanged. Earlier Lua 5.5 measurements predate the compatibility fix and should not be treated as measurements of this build on the game's Lua version.

A subsequent review removed unused lateral work when roll strength is zero. Lua 5.2.4 measurements with the same 1,000 vehicles and 120 callbacks, taking medians of five runs, showed 21–22% less evaluator CPU for pitch/heave-only motion in 1- and 100-car consists: approximately 0.9 ms saved per 1,000-carriage update. Full-axis and roll-only timings were effectively unchanged, and each case retained identical before/after pose checksums.

A separate 10 km sampling check over three carriage seeds and all three motion profiles found less than 0.2% change in RMS strength on each axis relative to the preceding amplitude-irregularity build, with the existing roll, pitch, and heave limits preserved. Nearly 3,000 sampled short-wave cycles ranged from 94.6% to 105.5% of nominal length, averaging 100.002%. These figures describe the synthetic evaluator, not an in-game visual assessment.

These are standalone Lua CPU measurements. The context cases run serially and do not model engine scheduling. Native API calls, rendering, logging, real track transitions, cold-cache costs, and game FPS are not measured. The LOD diagnostic is disabled by the test harness; disable it in the game before collecting performance measurements.
