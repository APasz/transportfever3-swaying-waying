# Runtime LOD investigation

The aim is to skip added sway calculations beyond the existing sway cutoff while continuing every authored transformator callback. Model LODs, visibility ranges, and longer native animation limits must remain intact.

## Exposed interface

The installed `api/tealdef/api/type/transformator.d.tl` and `base/tealdef/scripts/transformator_util.d.tl` expose no current-LOD or camera-distance field in the transformator input. The supported `TransfOutput:getUserTransfs()` and `getAnimationStates()` getters can inspect output already produced by the original callback. Neither getter is documented as identifying the rendered LOD.

A runtime cutoff is therefore not implemented yet. A transform count or animation name must not be treated as a LOD signal without checking it against camera movement, model geometry, and other wrappers.

## Diagnostic build

`src/swaying_waying/lod_probe_config.tl` enables a bounded, read-only capture. It is disabled after the capture below; the separate curvature probe is also disabled.

Each Lua context selects its first adapted leading carriage, including a stationary one. It logs up to 48 samples, every 64 callbacks. Callback cadence permits captures while paused. Different contexts may select different vehicles or reach their limits at different times.

The initial inventory records exposed input keys, scalar numbers/booleans, and model metadata keys. Each sample repeats dynamic input inventories and records:

- Context, vehicle, carriage, model path, callback count, and game time.
- Native user-transform count and transform-type counts.
- Authored animation names, sorted for comparison.

Inspection runs after the original callback and before this mod adds animation states. Only the two documented output getters are called. Getter failures are recorded as unavailable and report their original cause once through the shared logger; an unexpected observer failure logs once and disables that observer without interrupting motion. Completed probes stop their getter calls and logging. Disabling the configuration removes the observer and its diagnostic state.

The probe performs no track queries, game commands, custom-state operations, or writes to animation output. Logging and getter calls add overhead, so this diagnostic build is unsuitable for measuring game performance.

## Capture

1. Set `LOD_PROBE_ENABLED = true`, regenerate with `scripts/validate.sh --generate`, and restart the game to load its Lua contexts.
2. Enable **Detailed model logging** in the mod settings before loading a focused test save. Pause and focus the leading vehicle of an adapted train. Start close, zoom gradually beyond the sway cutoff, then zoom back. Spend several seconds at each distance and repeat for roughly 30–60 seconds.
3. Preserve `local/crash_dump/stdout.txt` before another restart. Match `LOD probe` model paths with the detailed model-adaptation logs, which report each authored LOD visibility range and whether it carries sway. Graphics settings may scale actual switching distances.
4. Disable `LOD_PROBE_ENABLED`, regenerate, and restart after the capture has been assessed.

Stable game time helps separate camera effects from wheel, door, and other animation changes. Transform counts alone are insufficient evidence: some models have identical hierarchy sizes across LODs, and native/custom wrappers may produce different output for other reasons. If the capture exposes no reliable signal, retain the current callback behaviour rather than guessing at camera distance.

## Native capture

The preserved segment from 2026-10-18 21:34:05–21:36:21 UTC contains 125 samples from ten Lua contexts. All observe vehicle 6615, leading carriage 7149, using `::/vehicle/train/china_df5/china_df5.mdl`. Game time remains 3,452,000 ms throughout the paused camera test. No sway runtime or probe failures were logged in the analysed segment.

Native output has two transform counts: 29 in 85 samples and 22 in 40 samples. An offline adaptation of the same installed model gives the following correspondence:

| LOD | Authored visibility | Adapted hierarchy nodes | Sway | Transformator callback |
| --- | --- | --- | --- | --- |
| 0 | 0–100 m | 29 | Enabled | Enabled |
| 1 | 100–400 m | 22 | Enabled | Enabled |
| 2 | 400–1600 m | 4 | Disabled | Disabled |

The original model has `skipFromLod = 2`, and adaptation preserves that callback limit. Thus this model already stops executing the wrapper, including added sway calculations, from LOD 2 onward. The observed counts match its two callback-enabled LODs. No four-transform sample appears. Camera distances were not recorded, so the trace does not independently measure the 400 m switching distance; graphics settings can scale it.

All samples contain the same 18 authored animation names. The Lua parameter table exposes a constant `instIndex = 0` and no LOD field. Nested world/static/model-info values are native userdata that this inventory cannot enumerate with `pairs`; their unavailable inventories do not prove the absence of undocumented native fields. The supported definitions still expose no current-LOD or camera-distance input.

The filtered capture is preserved at `/tmp/swaying_waying_lod_capture.log`, with parsed samples at `/tmp/swaying_waying_lod_rows.json`. These temporary files are not part of the mod.

## Scope and decision

A standalone adaptation/policy analysis of all 166 train, wagon, and tram model tables in the installed base vehicle archives, with default settings and without other mods' hierarchy changes, finds that 164 already have a callback limit equal to their selected sway limit. Two retain a longer authored callback range:

| Model | Active sway LODs | Active callback LODs | Authored sway endpoint |
| --- | --- | --- | --- |
| CarGoTram | 0–1 | 0–2 | 400 m |
| Changchun 3000 | 0 | 0–1 | 434.306 m |

Those counts describe model resources, not the number of active vehicles or measured CPU cost. Other mods may introduce additional cases. The DF5 capture does not exercise callbacks beyond a sway cutoff, so it cannot validate a gate for those exceptions.

Keep the existing callback limits and smooth curvature input. Inferring LOD from `getUserTransfs()` would require a native getter and output-table inspection on otherwise cheap callbacks, plus handling ambiguous hierarchy sizes and later model wrappers. This capture establishes a useful correspondence for one model, not a general API guarantee. The remaining vanilla scope is too small to justify an unvalidated heuristic that could suppress visible sway or authored behaviour. A future independent gate needs a reliable, inexpensive LOD signal and an in-game capture of a model whose native callback range exceeds its sway range.

## Reduced distance comparison (2026-10-20)

The installed catalogue was evaluated with the production `model_policy.lodCount` function and two temporary policy variants. Standard uses the current 500 m target and 350 m minimum. Reduced uses a 350 m target with the same minimum. Neither policy changes authored LOD ranges or removes inherited transformator callbacks.

The scan evaluated 166 vanilla rail models and 2,349 mod rail model resources across 111 mod IDs. A further 2,126 decorative/non-vehicle resources and eight empty menu models were excluded. All candidate files evaluated successfully after loading the installed vector/matrix helpers and providing the game's `math.pow` equivalent. Resources were deduplicated by mod ID and content path, preferring local development copies over downloaded copies. Paint variants and separate vehicle sections remain separate model resources.

| Catalogue | Vehicle model resources | Reduced sway LOD changes | Reduced callback-limit changes |
| --- | ---: | ---: | ---: |
| Vanilla | 166 | 0 | 0 |
| Installed mods | 2,349 | 0 | 0 |

Lowering the target alone has no effect in this catalogue. Existing boundaries are too widely spaced. For example, 100/400/1600 m boundaries select 400 m for both targets. A model with boundaries below 350 m followed by 700 m must still select 700 m. The most common Standard endpoints are 400 m for 108 vanilla models, and 500/400/700 m for 655/549/354 mod resources respectively.

An additional counterfactual used a 200 m target and 100 m minimum to show what relaxing the agreed minimum might permit. This policy is diagnostic only and has not been installed:

| Catalogue | Earlier sway endpoint | Earlier transformator callback endpoint |
| --- | ---: | ---: |
| Vanilla | 162 / 166 | 12 / 166 |
| Installed mods | 1,780 / 2,349 | 745 / 2,349 |

Earlier visible sway does not imply that its Lua calculations stop earlier. The wrapper still preserves authored wheel, door, tilting, particle, and other callbacks. In the counterfactual, 154 vanilla and 1,209 mod resources retain callbacks beyond the sway endpoint. Some callback savings are possible where the current policy extends a shorter native limit for added sway, or creates the transformator configuration itself. Other models retain their original callback range.

These are static model-policy counts, not active vehicle counts, measured CPU savings, or FPS predictions. Mod run scripts, save-specific variants, load-order changes, custom callback resolution, and safe-body adaptation can affect the actual eligible population; the mod counts are an upper bound before those checks. Full vanilla adaptation/rest-pose validation still passes for all 166 models. The temporary per-model comparison is `/tmp/swaying-distance-audit/comparison.csv`.

A Reduced toggle that preserves the 350 m minimum would currently be ineffective. A useful shorter-distance mode needs a deliberate change to that minimum, and reliable runtime LOD information would be needed to stop added calculations independently of longer authored animation limits. The existing distance policy remains unchanged.
