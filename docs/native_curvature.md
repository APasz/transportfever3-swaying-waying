# Native curvature investigation

The aim is to determine whether `currentInfo.railVehicle.curvature` can replace the per-frame `getAverageCurvature(40, 40)` query without changing curve lean's direction, locality, or smoothness.

## Source findings

The installed `api/tealdef/api/type/transformator.d.tl` and [official API reference](https://wiki.transportfever3.com/script-doc/api/type/transformator.html) expose `RailVehicleScriptingInfo.curvature` as a number. They do not specify its units, sign, sampling position, averaging, or whether carriages share it. `TransformatorParams.DynamicInfo` is documented as updating every render step; this does not establish the update frequency of each field.

A search across the script and sound Lua/Teal files in all 1,092 installed base-content archives found no `.curvature` or `["curvature"]` member reads. This search cannot establish how the native engine populates the field. The shipped tilting-train transformator uses `transformator_util.calculateTilt`, which calls `getAverageCurvature(80, 80)` and applies speed squared and the reversed flag. Swaying Waying uses the same response with a 40 m window in each direction.

Two native captures are analysed below. The supplied value is not used to drive motion. The diagnostic switch is disabled after completing the comparison.

## First native capture

The capture dated 2026-10-18 20:16:39–20:20:05 UTC contains 10,240 samples from ten Lua contexts, observing consist 6615. Its seven-carriage membership was sampled at positions 0, 2, 4, and 6 (carriages 7239, 7377, 7379, and 7381). Removing duplicate carriage/game-time observations leaves 8,386 samples. Matching observations from different contexts agree on supplied, point, and averaged curvature; no diagnostic or curvature-query failures were reported.

All observed vehicles had `reversed=false` and `facing=false`. Reverse running and backward-facing vehicles are therefore untested. The capture spans about 127 game seconds because the isolated contexts receive callbacks at different times and reach their individual sample limits separately.

### Locality

There are 2,628 game-time groups containing observations of multiple carriages. Supplied curvature differs between carriages in every such group. It is not a single consist-wide value in this capture. For example, at game time 2,944,400 ms:

| Position | Carriage | Supplied | Average ±40 m | Point at offset 0 |
| --- | --- | --- | --- | --- |
| 0 | 7239 | -0.000108906119 | -0.000116381256 | -0.000122973142 |
| 2 | 7377 | -0.000120388242 | -0.000119641307 | -0.000117306328 |
| 4 | 7379 | -0.000130869754 | -0.000128507425 | -0.000133971087 |
| 6 | 7381 | -0.000142333694 | -0.000131678971 | -0.000128288113 |

This establishes carriage-specific data, but does not establish that its sampling position matches the geometric query.

### Transition shape and position

The supplied signal changes sharply between straight and curved sections. The existing averaged signal ramps across transitions. More significantly, supplied and point signals encounter the same curve features at different wheel distances, and the difference varies with carriage position.

A spatial alignment of the complex-curve section gives the approximate wheel-distance shifts below. Each row compares the front carriage's signal with the same signal in the indicated carriage. The fit searches integer shifts from 0 to 350 m, uses linear interpolation between captured observations, and excludes interpolation gaps over 15 m. Data before game time 2,950,000 ms is omitted to exclude an early wheel-distance reset.

| Position | Point-query shift from front carriage | Supplied-curvature shift from front carriage |
| --- | --- | --- |
| 0 | 0 m | 0 m |
| 2 | 49 m | 97 m |
| 4 | 103 m | 203 m |
| 6 | 150 m | 299 m |

Thus the supplied signal's apparent separation along this train is about twice the point signal's separation. This is an inference from signal alignment, not a native offset measurement or proof of which engine path is correct. Native carriage offsets and a physical-position comparison are needed before adopting the field.

The difference can reverse the lean target. At game time 3,006,865 ms, front carriage 7239 reports supplied curvature -0.0160792209, while the point query reports +0.0181996338 and the ±40 m average reports +0.0125650866. Its speed is 12.3496199 m/s. Feeding supplied curvature directly into the existing response can therefore change the direction as well as the transition shape.

Across the deduplicated observations, replacing averaged curvature directly would change the normalized 1.5° lean target by a median 0.0025°, a 95th percentile 1.331°, and a maximum 2.938°. These are target differences calculated before time damping at 1x lean intensity, not measured visible roll or a performance benchmark. The sample set is not uniformly time-weighted.

### Assessment after the first capture

The field is populated, carriage-specific, and a possible source for a future query-free response. It is not an equivalent replacement for `getAverageCurvature(40, 40)` in this capture. The apparent sampling-position discrepancy must be resolved; reversal, facing, and tram coverage also remain untested.

The existing read-only spacing inspector can establish native offsets for the captured consist while it remains loaded:

```lua
ug_require("apasz_swaying_waying::/swaying_waying/spacing_probe.lua").inspect(6615)
```

An inspection at 2026-10-18 20:27:22 UTC reported the same consist ID and count, but different carriage membership: 7149 and 7432–7437. That train is 167.053009 m long, with first/last carriage-centre offsets -74.796501 and +74.596504 m (149.393005 m apart). Its current vehicle facing is mixed, and its list reversal flags also differ from the first capture. The centre separation is consistent with the point-query signal alignment, but the changed membership prevents treating it as an exact paired measurement of the first capture. This is supporting evidence, not confirmation of a doubled offset in the engine.

A second capture must preserve membership between render observations and the native inspection. Save the current mixed-facing consist before restarting, capture the curve transitions, then run the inspector before rebuilding or reversing it. Compare carriage IDs explicitly before using the native offsets in the analysis.

The filtered original trace and parsed analysis input were preserved at `/tmp/swaying_waying_curvature_capture.log` and `/tmp/swaying_waying_curvature_rows.json` during this investigation. These temporary files are not part of the mod.

## Second capture: matched carriage offsets

The second log starts at 2026-10-18 20:31:50 UTC and includes the native inspection at 20:34:02 UTC. It contains 9,217 samples from ten contexts, with 7,981 distinct carriage/game-time keys. The sampled carriage IDs 7149, 7433, 7435, and 7437 all match the native inspection of the same seven-carriage consist. Its length is 167.053009 m and its first-to-last carriage-centre separation is 149.393006 m.

Both travel directions occur in the log, including wheel-distance resets and stops. Carriage 7433 faces backward and the other three sampled carriages face forward. Fits are restricted to a single uninterrupted direction and wheel-distance run; data from opposite runs is not combined by wheel distance. The common consist reversal is `reversed ~= facing`.

The spatial-alignment comparison reproduces the discrepancy against measured native geometry:

| Stable run and carriage pair | Native centre separation | Point-query signal separation | Supplied-curvature signal separation |
| --- | --- | --- | --- |
| Forward, positions 4–6 (7435–7437) | 48.250603 m | about 48.5 m | about 96 m |
| Reverse, positions 2–4 (7433–7435) | 52.691799 m | about 52.5 m | about 106 m |

These estimates search shifts in 0.5 m steps with linear interpolation, excluding gaps over 15 m and fits with under 50% reference-sample overlap. The forward run uses game times 3,460,100–3,630,000 ms; the reverse run uses 3,638,400–3,770,000 ms. Samples must be moving and match that run's common reversal state. In reverse, the fitted shifts are negative because the curve feature reaches the opposite carriage first; the table shows their magnitudes. No sign inversion is needed to align either signal in these pairs, including the reverse pair's opposite vehicle facing.

For the forward pair, 177 reference observations give curvature RMS errors of approximately 0.000295 for the point signal and 0.0000367 for the supplied signal at their best shifts. The reverse supplied fit uses 1,355 overlapping observations with RMS error approximately 0.0000901 at -106 m. The point fits are less exact, consistent with the coarser point values in the log, but align near the measured native separations. Supplied curvature consistently requires about twice that separation.

The first-to-last supplied signal also aligns near 299 m, against the measured 149.393006 m centre separation. The tail pair above provides the stronger matched comparison because both of its curve features are captured in full.

There is one duplicate-key disagreement at the initial paused/load game time 3,452,000 ms: carriage 7149 appears with wheel distances 2912.65454 and 116.052567 and slightly different supplied curvature, while point and averaged curvature agree. This observation is outside both fitted runs. It is not used as evidence of a steady-state context discrepancy. No probe or curvature-query failures were logged.

### Conclusion

`railVehicle.curvature` is populated and carriage-specific, but it is not a safe direct replacement for the current averaged query in the tested game build. Its curve features propagate through the consist at approximately twice the native carriage spacing in both tested directions. This is evidence of a sampling-position discrepancy; the closed native implementation prevents identifying its exact cause from these logs alone. It should not be described as a confirmed engine implementation bug without a separate native investigation.

Its abrupt curve transitions also differ from the existing ±40 m spatial average. Time damping alone would not make those spatially different inputs equivalent. No production motion input has been switched to the supplied field, and no performance saving is claimed from this investigation. The diagnostic probe is disabled for the next reload.

The paired trace, including the native offsets, is preserved at `/tmp/swaying_waying_curvature_capture_2.log`; parsed samples are at `/tmp/swaying_waying_curvature_rows_2.json`. These are temporary investigation files. A future optimisation should use the smooth per-frame averaged path as its reference and separately measure query cost and motion error.

## Comparison build

The temporary probe is controlled by `src/swaying_waying/curvature_probe_config.tl`. Its hook runs after the existing motion output, so observation errors cannot suppress that frame's animations. A failed hook disables itself and logs a warning. Failed point queries preserve the unavailable marker and report their original cause once through the shared logger. It issues no game commands and does not use custom state or engine components.

Each isolated Lua context selects the first moving, adapted rail consist with at least two carriages. It observes up to four carriage positions spread across that consist, including its ends. Context and vehicle identifiers are included because contexts may select different consists. Carriage membership should remain fixed during a capture.

Each selected carriage logs at most 256 samples, at least 100 game milliseconds apart, then stops its extra queries. This provides roughly 26 seconds of observations per carriage at normal game speed. Paused frames do not consume the sample budget after the initial observation. Clock rewinds allow a new observation but do not reset the budget. Replaced carriages cannot grow the four-carriage state limit.

Samples include:

- Consist and carriage IDs, carriage position and count, game time, wheel distance, speed, travel reversal, and individual facing.
- `supplied`: the current `railVehicle.curvature`, plus `previousSupplied` from `previousInfo` when available.
- `average40`: the unmodified result already used by the existing lean calculation. The probe does not repeat this query. Skipped or failed queries are reported as `unavailable`; a measured zero remains zero.
- `point`: `getVehicleEdgeInfo(0).curvature`, queried only when a log sample is due. A failed point query is reported as `unavailable`.
- `frames`, `suppliedChanges`, and `averageChanges`: callback and value-change counts since the previous log sample. These preserve evidence of repeated values between logged samples without logging every frame.

The probe adds logging and point queries while enabled. Its frame times are not a performance benchmark. Disabling its configuration removes the observer callback and its state; the runtime only checks whether the callback exists.

## In-game capture

1. Set `CURVATURE_PROBE_ENABLED = true`, run `scripts/validate.sh --generate`, and reload the game so it loads the diagnostic build. Keep curve lean enabled. A focused test save with one moving multi-carriage train makes automatic selection easiest to interpret.
2. Follow the train for about 30 seconds through straight track, a curve entry and exit, and an S-curve if available. A consist with both forward- and backward-facing vehicles helps establish orientation. Check for `Curvature probe begin`, `sample`, and `complete` entries in `stdout.txt`.
3. Keep the log before restarting. Once the initial capture has been assessed, a separate capture after reversing the same consist can test the orientation mapping if needed.
4. Set `CURVATURE_PROBE_ENABLED = false`, run `scripts/validate.sh --generate`, and reload the game to disable diagnostics.

The usual log is `/home/apasz/.local/share/Steam/userdata/101784343/3493540/local/crash_dump/stdout.txt`.

## What establishes suitability

Compare observations for different carriages at the same game time. If supplied curvature is identical while local point and averaged curvature differ substantially, it may be consist-wide and unsuitable as a direct local replacement. A constant-radius curve can help establish sign and scale; transition curves distinguish a point value from the current 80 m spatial average. Facing and reversal must be tested separately.

The value-change counts and previous-frame values show whether supplied curvature updates smoothly or in steps. Different averaging or delayed updates are behaviour changes to assess, even if the sign agrees. A zero field on non-straight track, missing data, or inconsistent orientation would also rule out an unconditional replacement. Trams must be checked separately before removing their land-vehicle query path.
