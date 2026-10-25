# Native spacing investigation

The read-only spacing investigation confirmed that `carriageListSystem` exposes native offsets. One measured 20-carriage consist was 500.808594 m long, with adjacent offset differences of 16.295364–32.304703 m. Offsets decreased along carriage order, spanning positive and negative values around the consist reference point. In that test, render observations showed the same wheel distance across carriages, while the API `reversed` flag differed between carriages. Subsequent paired four-carriage tests established the orientation mapping below.

Transformators cannot call `api.engine`, and a supported way to deliver native offsets to ordinary vehicle transformators has not yet been established. Long-wave motion uses independent carriage phases by default. A common consist phase with approximate 20 m spacing remains available through the default-off `carriageLag` developer switch; it does not use native offsets.

In a loaded test save, run this in the Lua console to inspect every consist:

```lua
ug_require("apasz_swaying_waying::/swaying_waying/spacing_probe.lua").inspect()
```

Pass a consist or carriage entity ID to `inspect(id)` to limit the output. The all-consist scan enumerates transport vehicles and filters for carriage lists; the engine rejects direct enumeration of `CARRIAGE_LIST`. `Spacing probe engine` entries in `stdout.txt` report native offsets and signed differences between adjacent offsets, with explicit begin, completion, and failure markers. This probe only reads game state and is never called by the vehicle transformator.

The custom-state bridge is ruled out for carriages without `CUSTOM_STATE`. In the native test, `makeCustomEntityUpdateStateCmd` asserted in `GetComponentDataIndex` on the simulation thread because the component was absent. It requires an existing component; it does not create one. Lua `pcall` cannot catch this asynchronous native failure. Both old entry points in `spacing_bridge_probe.lua` are disabled and raise a Lua error before accessing any game API, so console-history calls cannot repeat the command.

## Orientation comparison

Community operation names and API field names are separate:

| Community operation | Carriage order | Forward/backward running relative to each vehicle's facing |
| --- | --- | --- |
| Reverse | Preserved | Switches |
| Flip | Reversed | Preserved |

The vehicle `reversible` flag is a capability setting, separate from the runtime orientation flags below. With reversible vehicles at both ends, the consist reverses; otherwise it flips. A single unchanged consist therefore cannot exercise both operations.

Native probe lines distinguish `apiListReversed` (`CarriageListSystem.CarriageInfo.reversed`) and `apiCarriageReversed` (`Carriage.reversed`). The internal `axisReversed` boolean corrects authored model-root axes; it does not describe either community operation. The motion evaluator converts it into a numeric axis sign.

Each paired test used four carriages with facing flags `{false, false, false, true}` and preserved its consist membership between snapshots:

| Measured API property | Community flip | Community reverse |
| --- | --- | --- |
| Carriage IDs and API list indices | Unchanged | Unchanged |
| Render `carriagesReversed` and native `Carriage.reversed` | Unchanged | Unchanged |
| Render `landVehicle.reversed` and native `CarriageInfo.reversed` | Unchanged | Toggled for every carriage |
| Native carriage offsets | Unchanged | Signs inverted |

The API list indices therefore cannot be assumed to reorder when the community calls an operation a flip. Render `carriagesReversed` uses one-based indices, while `positionInCarriageList` is zero-based. The common consist reversal state is `landVehicle.reversed ~= landVehicle.carriagesReversed[positionInCarriageList + 1]`. Every carriage agreed on this state in the measured pairs: `false` before and after the flip, and `false` then `true` across the reverse.

Long-wave motion uses that common state to sign wheel distance in both phase modes. When enabled, the approximate lag is derived from the stable API carriage index. Individual facing converts long-wave roll, pitch, section lag, and longitudinal support offsets into carriage coordinates; it does not change long-wave heave or the short and third waves. The former use of the raw per-carriage `landVehicle.reversed` flag incorrectly gave opposite shared travel directions to opposite-facing vehicles. Orientation is read on each update, including when carriage lag is disabled, without an engine query or a cache refresh. Missing orientation data is reported instead of inventing a facing.

The experimental `MovePath.reverse` reading was `nil` and has been removed from the probe, along with the obsolete custom-state presence checks. Wheel distance also reset during turnarounds, so this orientation correction does not guarantee phase continuity across a distance reset.

The temporary render orientation probe and its update hook were removed after the mapping was verified in game. General debug logging does not collect per-frame orientation diagnostics. The read-only native spacing inspector remains available for further investigation; the disabled bridge module remains as a guard for old console-history calls.

Use two independent before/after comparisons:

1. A mixed consist with reversible vehicles at both ends: inspect normal running, then inspect after a community reverse.
2. A separate mixed consist that flips: inspect normal running, then inspect after a community flip.

Keep membership and vehicle facing unchanged within each pair apart from the operation under test. Different consists may be used between pairs; each needs its own baseline. Where possible, include interior vehicles facing in both directions so the readings can distinguish a common travel direction from individual carriage orientation.

At each inspection, let the train move briefly, pause, and run the native `inspect()` command above; no entity ID is needed. Capture `stdout.txt` after the comparison and before restarting the game. This records native observations without changing the sway calculation.
