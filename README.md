# Swaying Waying

Adds adjustable roll, pitch, vertical suspension motion, outward curve lean, and optional onboard cameras to rail vehicles in Transport Fever 3. Vehicle performance and the transport simulation are unchanged.

The mod supports compatible vanilla and modded trains, wagons, coaches, and trams. It wraps existing transformators to preserve authored wheel, door, pantograph, particle, emitted-model, and tilting behaviour. Sway uses a separate animation state and therefore composes with the game's native tilting trains.

Roll reuses the game's `::/vehicle/shared/ani/tilt.ani` animation on that separate state. The mod supplies `pitch.ani` and `heave.ani` for the other axes; a separate `roll.ani` is unnecessary.

## Settings

- Sway mode: Off, On (default), or Speedless Sway
- Onboard cameras: Disabled (default), Stable, Sway, or Both, with + Extra variants
- Sway intensity from 0.25x to 2x
- Roll balance from off to 2x
- Pitch balance from off to 2x
- Heave balance from off to 2x
- Curve lean intensity from off to 2x (1x by default)
- Curve sampling interval: Frame, 1 m (default), 3 m, 5 m, 10 m, or 15 m
- Track influence from off to 150%
- Track sampling interval: Frame, 1 m, 3 m, 5 m (default), 10 m, or 15 m
- Automatic vehicle variation from off to strong
- Detailed model logging: off by default

Reload the save to apply setting changes.

**On** scales procedural roll, pitch, and heave with speed, starting at 5% strength at 5 km/h. **Speedless Sway** uses full procedural strength from 5 km/h, while retaining the intensity, axis, track, and vehicle modifiers. Below 5 km/h, all procedural motion and curve lean settle back to neutral in both modes. Motion eases back in at 5 km/h; the same threshold applies in reverse. Motion still advances with distance travelled, so rocking progresses more slowly at low speed. Curve lean remains speed-dependent in both modes. **Off** disables sway and curve lean; Stable onboard cameras can still be added. Existing saved Off/On selections retain their meaning, and saves without a selection default to On.

Roll, pitch, and heave balance are multipliers relative to the overall sway intensity, while curve-lean intensity is independent. Their neutral 1x defaults preserve the standard motion: procedural roll reaches at most 1.2 degrees, pitch reaches at most 0.2 degrees, heave reaches at most 2 cm, and curve lean reaches at most 1.5 degrees. Setting a balance to 0x disables that procedural component independently; roll balance does not change curve lean.

Setting curve lean intensity to Off disables curve lean and skips curvature queries.

Pitch and heave are derived from the same synthetic vertical rail profile. The profile is sampled at the vehicle's effective front and rear support points: their average produces heave and their difference produces pitch. This keeps the two movements physically coherent and phase-continuous. Effective wheelbase is inferred from repeated fake-bogie group positions where possible, then from model length as a conservative fallback.

Motion blends three waves with stable phases seeded per carriage by default. The 65 m long wave's travel direction accounts for both consist reversal and individual carriage facing. Its roll and pitch are converted into each carriage's axes, while heave is independent of facing. Each carriage retains its own suspension and intensity response. Waveform results remain independent of callback order and leading-carriage visibility; matching distance calculations can be reused within a Lua context even with independent phases. The experimental `carriageLag` developer switch restores a common consist phase with an approximate 20 m distance lag per carriage position; it is disabled by default and does not use actual carriage lengths.

A small irregular component varies the profile smoothly over distance. Its lateral and vertical shapes use separate deterministic seeds, with fine and broad variation at 20 m and 80 m cell spacing for the default profile (15/60 m for Quick and 28/112 m for Slow). These are interpolation scales, not repeating wave lengths or fixed peak counts. Adjacent cells join with continuous slope and curvature. Irregularity uses up to 10% of the normalized profile range, fading out at the existing amplitude limits. It is applied to both vertical support samples before deriving pitch and heave, so those axes remain coherent. The same coordinates and carriage seed produce the same result across callbacks and Lua contexts. This remains a synthetic carriage profile; it does not identify real track defects or synchronise bumps between carriages.

The dominant short wave also varies its spacing gently over distance. A separate seeded profile shifts its phase by at most 0.08 cycles, with continuous slope and curvature and no accumulated drift. Local wavelength stays within approximately 90–112.5% of nominal; a three-seed sample of nearly 3,000 complete cycles varied by about ±5.5%. Variation develops over two and eight nominal wavelengths (80/320 m for Default). Front and rear support heights use their actual positions in this same varying profile. Strength limits and the 5 km/h cutoff remain unchanged.

Unusual third-party models that cannot be adapted are left unchanged and reported once through the mod logger.

Normal logging emits one concise model result with the active/total LOD count, section count, and original transformator. Author opt-outs and author-owned sway receive a short skipped result; unsafe models retain their failure warnings. Repeated modifier calls on an already adapted model stay quiet. Each mod startup reports the effective settings, model-diagnostic and debug switches, experimental probe switches, and disabled motion components.

Enable the in-game **Detailed model logging** option when investigating model compatibility. It defaults to off, including for existing saves, and is independent of general debug logging. Each active LOD then receives one detailed message with its zero-based LOD number, outcome, wrapped body-group count, animated motion-node names, moving/total visual-node counts, authored `visibleFrom`/`visibleTo` distances in metres, original transformator (including the carrier default), detected body groups, and excluded axle/placement groups. Group names are sorted and only include nodes present in that LOD. Excluded placement groups retain their authored placement; separate wrappers can still animate their visible contents. Inactive LODs receive a short entry with visibility distances and omit identity-anchor details. Missing bounds appear as `unspecified`; invalid bounds are marked explicitly. Graphics settings can scale actual switching distances. Detailed collection and formatting are skipped while the option is off.

Every selected LOD must adapt safely before any changes are committed; rejected models retain their original hierarchy, references, and transformator. A failed result report cannot undo a successfully committed adaptation. General developer debug output remains controlled by `DEBUG_LOGGING_ENABLED` in `src/swaying_waying/logging_config.tl` and uses `log.verbose`; experimental probes retain their separate developer switches.

Multi-group fake-bogie rigs, including locomotive/tender sets and Jacobs-bogie multiple units, keep their authored engine, tender, root, connector, and skin-bone placement groups unchanged. The mod identifies safe axle-bearing body groups per active LOD, allowing normal LOD-specific group names; if it cannot identify those groups safely, it leaves the model unchanged.

When a rig has one detected body group, separate rigid fittings such as couplers receive the same motion about that body's pivot. Their original placement groups retain authored track steering, while axle branches and skinned articulation connectors stay outside this added motion. Paired couplers on adjoining carriages are not synchronised with one another.

When James' Reusable US Assets is active, turn off its **Enable Railcar Swaying** option. Both mods deliberately preserve custom transformators, so enabling both sway implementations stacks their motion on vehicles that use James' helper.

Real Track Cant is supported in either mod order. Its cant roll composes with body sway, and its absolute-part placement data is refreshed if Swaying Waying modifies the model hierarchy afterwards.

Real Track Cant's generic `devers_any` wrapper forwards the original custom transformator's `getEmittableModelsScript` and `computeEmittedModelsScript` callbacks, including their parameters, alongside update and particle callbacks. The earlier missing-callback limitation is resolved in the installed build checked on 2026-10-24.

Authored camera entries retain their order, fields, and anchors. Optional onboard cameras add stable and body-following views at a shared neutral viewpoint; see below for placement and compatibility details.

The rail snow-powder particle transformator from Realistic Environment Pro (formerly Just More Weather) is preserved in either mod order. Swaying Waying delegates installation to that mod's own idempotent model adapter when the mod is enabled. Installed but disabled copies are left inactive.

**Cayde's Track Cant** (`cayde_devers_1`) is declared incompatible with Swaying Waying. Disable one of the two mods; compatibility support is not planned at present. Its cached hierarchy indices and incomplete callback forwarding prevent supported use together. The original **Real Track Cant** (`devers_1`) remains supported in either mod order.

### Installed-mod sway audit

The 2026-10-25 offline pass inspected 4,950 candidate models from the installed mod.io collection. Of 2,798 rail/tram models, 2,712 accept sway, 20 retain their own USRA sway, and 40 are empty menu/helper models. The remaining 26 are safely skipped:

| Models | Remaining limitation |
| --- | --- |
| 6 Köf II locomotives (`maikc_koef_ii`) | Body containers change between active LODs; shared attachment targets cannot be preserved safely yet. |
| 14 JNR 111/113 vehicles (`pz7_jnr_series111`) | Numeric seat-group references need a verified conversion to TPF3's named attachments. |
| 6 Kessel 200 wagons (`mcs_gtw4`) | Authored node transforms do not contain the required 16 finite values. |

This pass enables 206 previously skipped variants: 186 KiHa 261 models by retaining a consistent placement container as distant LODs omit bogies, and 20 FS E.636, FS ALn 663, and BR 130 models by recognising native `::shared/...` transformator names. Relative and foreign-namespace custom transformators retain their own callback resolution.

The installed-model check loaded custom transformator callbacks and verified unchanged visual geometry and materials at rest, with no newly skipped models. Separate modifier-order checks retained sway and valid rest data with Real Track Cant, and four snow emitters with Realistic Environment Pro, in both orders. These are model-data checks; native rendering, moving articulation, and the complete enabled-mod stack still need an in-game check.

## Onboard cameras

The **Onboard cameras** setting defaults to **Disabled**, including in existing saves. It controls additions and does not remove existing cameras:

| Setting | Sway enabled | Sway disabled |
| --- | --- | --- |
| Disabled | No additions | No additions |
| Stable | Stable view | Stable view |
| Sway | Body-following view | No additions |
| Both | Both views | Stable view |
| Stable + Extra | Stable view, including passenger and freight vehicles | Same coverage |
| Sway + Extra | Body-following view, including passenger and freight vehicles | No additions |
| Both + Extra | Both views, including passenger and freight vehicles | Stable view with Extra coverage |

Regular modes select a crew viewpoint, falling back to an existing camera. **+ Extra** selects the preferred valid crew position, then the first valid passenger seat, then an existing camera. If none are usable, it uses an exterior viewpoint near the rear end, looking forward along the vehicle, 0.5 m above the highest model, physical, or transformed cargo-bay bounds. Exterior views without usable bounds are skipped and logged.

One representative viewpoint is selected per vehicle; Both and Both + Extra provide Stable and Sway variants of that point. A vehicle with a valid crew viewpoint has the same additions in Both and Both + Extra. Existing cameras remain available. No other camera mod is required. The Extra choices follow the original choices to preserve saved selections.

Stable views attach outside this mod's motion, using the cab section's placement frame where possible. They still follow vehicle movement, track gradients, and any authored or third-party motion affecting that frame. Sway views follow the cab body, including this mod's roll, pitch, heave, and curve lean. Both variants share their position, orientation, and field of view in the neutral pose.

Placement prefers valid crew viewpoints facing within 45 degrees of the model's forward (+X) direction, using the full attachment transform rather than the seat's `forward` flag. Among those viewpoints, seats using `driving` or `driving_upright` take priority; author order breaks ties. If none face forward, the first valid crew seat remains the fallback, including standing staff and rear-only cabs. Eye level is 1.2 m above seated crew origins, or 1.6 m for standing crew using the `idle` or `walk` posture. A nearby authored view facing the same direction takes precedence, including its FOV. Existing views are reused when their position, FOV, section, and animation ancestry match in every LOD.

The internal `multipleCrewSeats` boolean in `src/swaying_waying/camera_config.tl` defaults to false. In the regular camera modes, enabling it creates the selected views for every valid crew seat, including reverse-facing drivers, firemen, and assistants. Exact duplicate viewpoints are suppressed; passenger seats are excluded. Extra modes always select one representative viewpoint. Regenerate Lua and reload the save after changing the developer switch.

Generated camera anchors exist in every model LOD. They stay outside authored animation branches that could collapse their axes when crew or lights are hidden; the known native tilt and Real Track Cant roll animations remain safe to follow. Views without a safe anchor are skipped and logged. Distant LODs retain the viewpoint without enabling procedural motion beyond its configured range. Camera failures leave independently safe sway work intact. Existing author opt-outs and author-owned sway exclusions still apply.

Auto Passenger Cameras (`dome_wagon_cameras`, formerly Wagon Cameras) has optional model-data compatibility, checked against installed revision 6 in both modifier orders. Its helper modules are loaded only when the mod is enabled. Its own generator supplies its automatic views before ours can suppress them; configured extras remain its responsibility. The adapter preserves complete existing camera entries and checks generated transforms, FOVs, and unique attachment names against every real LOD hierarchy. Added views are included in its camera-overlay layout.

For its known missing-`RootNode` fallback, the adapter supplies a real parent anchor where the coordinate frames can be preserved safely. Existing trees, named attachments, and neutral world poses are retained, including rotated/scaled roots and shared LOD trees. This repair also runs when our onboard cameras are disabled and sway is enabled, so the other modifier can run afterwards. Unsafe rebasing is skipped with a diagnostic.

Adapter generation, onboard camera additions, and overlay updates have separate rollback boundaries. A failure is logged once per model and stage; independently safe sway and camera work continues. Missing or incompatible optional APIs do not disable Swaying Waying. This integration does not change Auto Passenger Cameras' UI, input tracking, or bridge. It cannot guarantee the safety of cameras another modifier adds later, or repair arbitrary invalid existing camera entries. Other camera modifiers that append to the existing list retain their views; modifiers that replace the list later can still discard earlier additions.

### Development camera HUD

The experimental HUD is **off by default**. The internal `hudEnabled` boolean in `src/swaying_waying/camera_config.tl` enables it for development; regenerate Lua and restart the game after changing it. It has no user-facing setting. When off, it loads no native UI modules, registers no HUD recipe or stylesheet rules, installs no UI or camera lifecycle hooks, and publishes no camera-label metadata. Camera additions and sway remain available independently.

The prototype still has a known collision with Compass (`dk_compass`): its callout wrapper shares the native recipe name, causing duplicate HUD mounts. That compatibility issue remains unresolved while the HUD is disabled for normal use.

When enabled, a compact text overlay at the upper right of cockpit view shows the vehicle's current name and the model of the carriage associated with the viewpoint. It matches the native cab HUD's unframed body text and UI scaling, with right-aligned lines and no window background, border, or shadow. Its outer top-right anchor keeps the first line in place as model and camera lines appear or disappear.

When camera preparation publishes viewpoint metadata, the panel can also show **Crew seat 1 · Stable**, **Crew seat 1 · Sway**, or a numbered **Model camera**. Reused authored cameras receive the same labels as equivalent generated views, without changing their original camera entries.

The game does not expose the selected cockpit camera index to Lua. Identification therefore requires a unique nearby viewpoint, accounting for interpolation between simulation transforms. Known viewpoints identify their owning carriage even outside its body. Otherwise, the panel uses physical vehicle extents, falling back to render bounds if those are absent. Coincident Stable/Sway pairs suppress the camera label while retaining the owning model when it is unique. Overlapping carriages, missing camera data, and viewpoints moved away from known cameras suppress the uncertain fields. Vehicle names remain available. This avoids maintaining a switch counter that can drift when native input handling consumes an action.

The panel adds a separate child to the game's full-screen callout layout. The free-camera control subtree is invisible during cockpit view, so it cannot host visible HUD content. The native callout recipe, API, active slot, and existing children are preserved; Auto Passenger Cameras and other callouts can remain visible alongside the panel. Other floating layouts stay untouched. It adds no camera input handlers and does not change camera switching. Model information uses a bounded cache; visible vehicle details refresh five times per second.

Each cockpit entry logs the entity, first vehicle/model snapshot, and native panel bounds and visibility. Model cache misses also log the native description type, resolved model name, and camera metadata availability. These diagnostics distinguish missing camera data from panels placed outside the screen.

In-game UI checks: enter and leave cockpit/free-camera modes; rename a followed vehicle; switch through A4, Big Boy, and Metroliner within one consist; check reversed and repeated vehicles; verify ambiguous pairs hide their labels; and confirm vanilla/Dark UI, Auto Passenger Cameras, keyboard/controller input, screenshots, and 75–150% UI scaling. Native rendering and layout still require this game-side check.

## Track and vehicle response

Sway intensity is derived from the track speed limit: 100 km/h track uses a 1.25x factor, 160 km/h track uses 1x, and 350 km/h track uses 0.7x, with smooth interpolation between those anchors and distance-smoothed transitions. Track quality also changes the motion spectrum without changing its frequencies. The third wave has a fixed 20% weight; the remaining 80% is split between the short and long components in ratios of 0.80/0.20 on rough track, 0.65/0.35 on standard track, and 0.45/0.55 on smooth track. Standard track therefore uses short/long/third weights of 0.52/0.28/0.20. Both amplitude and spectrum transition over distance, so crossing a track boundary does not reset the phase. Vehicle comfort, maintenance, and author tags continue to affect amplitude only.

Track influence scales both of those track-derived changes around the neutral 160 km/h response. At off, all tracks use a 1x amplitude factor and the standard 0.65/0.35 spectrum; values above 100% exaggerate the same continuous response.

A carriage remembers the response of the last normal track while it is on a bridge or in a tunnel. If a save loads there, the mod inspects the surrounding normal track instead. An unsuccessful surrounding-track scan is retried after 100 m; the current edge is still checked at the selected sampling interval (5 m by default), so reaching normal track is detected without that delay. Amplitude and spectrum smoothing continue every frame between edge queries.

Track sampling interval controls track-quality queries. Smaller distances follow track changes more closely but use more CPU. The default is 5 m. Select the interval in the mod settings and reload the save to apply it. Existing saves retain the saved slider position; check the selected distance after updating from the previous interval options.

Curve sampling interval independently controls curvature queries, retaining the native 40 m averaging window ahead and behind. The default is 1 m. **Frame** queries once per moving carriage per update for the smoothest lean through changing curves. Distance intervals reuse curvature to reduce queries and may introduce visible stepping, especially at larger distances. Speed, orientation, and suspension smoothing still update every frame at every interval. Stopped vehicles skip curvature queries, and restarting refreshes the geometry immediately. Select the interval in the mod settings and reload the save to apply it. Existing saves retain their saved selection.

Curve lean and procedural amplitude pass through a short critically damped suspension response. Its 0.15 s response setting brings a step about 95% of the way to its target in 0.36 s, softening changes in both position and movement rate. It uses elapsed game time, so pauses freeze the response and frame rate does not set its strength. Cold loads start at the current target; stops settle briefly toward neutral without curvature queries. Wave phases and consist propagation remain distance-based.

Track authors can add one of these categories to a `.street.lua` track style:

- `swaying_waying_rough` selects the absolute 1.25x preset.
- `swaying_waying_smooth` selects the absolute 0.7x preset.
- `swaying_waying_rougher` multiplies the automatic factor by 1.25.
- `swaying_waying_smoother` multiplies the automatic factor by 0.7.

Absolute presets take precedence over relative modifiers. Conflicting absolute or relative categories are ignored and logged.

Add the selected value to the style's top-level category list, retaining its existing categories:

```lua
categories = { "tracks", "swaying_waying_rougher" },
```

Passenger stock receives a gentle automatic modifier from `metadata.transportVehicle.comfortFactor`: 0 maps to 1.1x, the standard 0.5 is neutral, and 1 maps to 0.9x. It only applies when the vehicle explicitly carries passengers; missing, automatic (`-1`), or invalid values are neutral. Availability years are deliberately ignored, so availability-changing mods cannot alter ride behaviour.

Vehicle variation scales the automatic comfort and live maintenance responses around neutral: Reduced is 50%, Normal is 100%, Enhanced is 150%, and Strong is 200%. Turning it off disables both automatic effects. Explicit `swaying_waying_rougher` and `swaying_waying_smoother` author tags remain fully applied at every setting.

At Normal vehicle variation, current maintenance affects every rail vehicle at runtime, from 1x when fully maintained to 1.1x at the worst condition.

Rolling-stock authors can add `swaying_waying_rougher` or `swaying_waying_smoother` to `metadata.transportVehicle.filterTags` in the `.mdl`. Author modifiers multiply the automatic comfort and maintenance response and are applied per carriage, so mixed consists can have different ride characteristics. Conflicting vehicle response tags are ignored and logged.

```lua
filterTags = { "default", "swaying_waying_smoother" },
```

Authors can independently select how quickly a vehicle's sway develops with speed and distance. In On mode, each profile starts at 5% strength at 5 km/h, then ramps up according to its profile:

- `swaying_waying_quick`: ramp begins at 5 km/h, reaches full strength at 90 km/h, and uses individual 30 m and 73 m waves.
- Untagged/default: ramp begins at 8 km/h, reaches full strength at 120 km/h, and uses individual 40 m and 97 m waves.
- `swaying_waying_slow`: ramp begins at 18 km/h, reaches full strength at 160 km/h, and uses individual 56 m and 137 m waves.

All profiles use the same 65 m long wavelength, with independent carriage phases by default. The regular three-wave component repeats after 50.44 km for the default profile, while the added irregularity breaks that repetition in the full motion. Regular wave weights sum to one, and irregularity preserves the same amplitude bounds.

These profiles change the sway envelope and rhythm, not its amplitude. They compose with `swaying_waying_rougher` and `swaying_waying_smoother`; for example, modern smooth-riding stock may use both `swaying_waying_smoother` and `swaying_waying_slow`. Conflicting quick and slow tags select the default profile and are logged.

For model integration, see the **[model author guide](docs/model-authors.md)**. It covers single bodies, articulated vehicles, LOD-specific group names, custom pivots and axes, fixed components, validation errors, and the offline model checker.

Authors configure `metadata.swayingWaying`. Explicit `sections` select the moving groups and can override their lag, wheelbase, pivot, axes, and LOD group names. Invalid author metadata skips adaptation with a diagnostic instead of silently selecting automatic behavior. The author’s sway LOD cutoff preserves the original transformator’s longer animation range.

Without author metadata, the mod can conservatively infer independent sections when multiple content-bearing body placement groups remain stable across every active LOD. Empty connector and skin-bone locators are excluded. Each group must have at least two support positions spanning a valid wheelbase, with distinct support centres. Otherwise stable body placement groups retain shared sway; axle-bearing groups remain the final fallback.

Without an author override, sway ends at the existing LOD boundary nearest 500 m, excluding boundaries below 350 m. Ties select the shorter range. For example, boundaries at 100, 400, and 1600 m select 400 m, while boundaries at 120, 250, and 1300 m select 1300 m. Models whose entire visibility range is shorter than 350 m use all their LODs. The model's LOD count and visibility ranges are unchanged; graphics settings can scale the actual switching distances.

Original animations retain their longer transformator limit even when sway stops earlier. Direct vanilla-compatible transformator limits can be extended to reach the selected sway LOD; custom-transformator limits remain an upper bound for compatibility. Models with missing or invalid visibility distances retain the previous LOD selection policy: direct transformators receive at least two active sway LODs, while higher inherited limits and custom-transformator limits are preserved. Invalid bounds produce a warning; missing optional bounds are reported only in general debug output and detailed LOD reports. Inactive LODs are left untouched unless an attachment or placement reference requires a compatible unanimated identity anchor. Named attachment anchors remain in their authored coordinate frames even when the distant node has no visual content.

Use `swaying_waying_none` to opt a vehicle out of Swaying Waying entirely. It takes precedence over the other vehicle tags and leaves the model hierarchy and authored transformator untouched.

Use `swaying_waying_only_camera` to retain camera additions while disabling our vehicle motion, or `swaying_waying_no_camera` to retain sway while disabling our camera additions. Add these to `metadata.transportVehicle.filterTags`. Both respect player settings; combining them disables both features. Existing authored cameras remain available. See the [author guide](docs/model-authors.md#enabling-only-cameras-or-only-sway) for camera-mode behavior.

Models that already provide paired `sway` and `tender_sway` tilt-animation pivots are treated as author-owned and left completely unchanged, including their hierarchy and transformator configuration, unless their author explicitly enables camera-only integration with `swaying_waying_only_camera`. Their original sway remains intact. This prevents Swaying Waying from interfering with the USRA steam locomotives or with wrappers such as Real Track Cant; those vehicles continue to use their own sway implementation rather than this mod's track and maintenance response.

## Development

Runtime Lua under `content/` is generated from the typed Teal sources under `src/`. Edit the Teal sources, then regenerate and validate:

```sh
scripts/validate.sh --generate
```

To check a checkout without changing its generated files:

```sh
scripts/validate.sh
```

Both commands run strict Teal checks, generate every source in a temporary directory, verify Lua formatting, run the regression suites, and check whitespace. The default check rejects stale generated files before running tests. Generation updates runtime files only after every source has compiled and formatted successfully. The same command generates the controls in `mod.json` from `settings.tl`; the check mode rejects stale settings as well as stale Lua.

Development requires Teal 0.24.5, StyLua 2.6.0, Lua 5.2 or newer, Python 3.10 or newer, Bash, and Git. `TL` can select a Teal executable; otherwise the script checks `PATH` and `~/.luarocks/bin/tl`. Set `TPF3_GAME_DIR` when the game is installed outside the default Linux Steam library; the type configuration reads definitions from that installation's `api/tealdef` and `base/tealdef` directories.

The game embeds Lua 5.2. Teal's `5.1` generation target converts bitwise operators to the game's built-in `bit32` functions; Teal has no separate `5.2` target. StyLua explicitly parses generated code as Lua 5.2 so newer syntax fails validation before runtime files are replaced. Hash multiplication uses exact partial products within double precision. Regression fixtures supply the required `bit32` operations when testing under newer standalone Lua versions.

All mod-owned runtime logging uses `swaying_waying/logger`, which creates one logger per Lua context through the shared `_logging` factory. Its API types, Teal source, and Lua runtime are relative symlinks to the sibling `../_logging` module. Development requires that sibling module. Validation follows the links, checks the shared code and generated output, and never overwrites the shared runtime; stale shared Lua must be regenerated in `_logging`. Release packages must include the dereferenced `content/swaying_waying/logging.lua` under this mod's namespace, so players need no separate logging mod.

Recurring failures use the shared `warnOnce` ledger. Runtime callback warnings include model, revision, original transformator, consist, carriage, and the original error. They report once per model, revision, and callback failure category, even when error details change between frames. Invalid configuration warnings identify the affected model and revision; a corrected revision reports recovery when the previously rejected configuration remains cached. Callback success on another carriage is not treated as proof of recovery. Unexpected runtime origin-resolution exceptions are logged and retried without escaping into the game callback. Failed native track queries retain their fallback response and report their cause once per query kind. Failed resource factories retain their original error; optional resource lookup failures remain debug-only. Standalone tools and regression runners use stdout for their reports and machine-readable output.

To check installed vanilla train, wagon, and tram models without launching the game:

```sh
python3 scripts/check_game_models.py
```

Use `--game-dir` or `TPF3_GAME_DIR` to select the installation. Supply a `.mdl` file or mod directory to check author content, and repeat `--dependency /path/to/mod` for required resource providers. `--verbose` includes per-LOD diagnostics; `--strict` fails on adaptation warnings or skipped rail models, while explicit opt-outs are successful. Load failures and rest-geometry changes always fail. See the [author guide](docs/model-authors.md#checking-a-model) for examples and limits.

### Code layout

| Module | Responsibility |
| --- | --- |
| `settings` | Typed setting definitions, defaults, UI values, and validation. |
| `model_policy` | Author options, LOD range, vehicle profile, placement data, and geometry inference. |
| `model_analysis` | Per-LOD name, parent, axle, and subtree indices; section detection. |
| `model_modifier` / `model_nodes` | Plan and apply motion wrappers using those indices. |
| `model_references` | Collect and validate known game attachments; keep unknown mod metadata opaque. |
| `model_cameras` / `camera_compatibility` | Select and anchor onboard views; integrate optional Auto Passenger Cameras data. |
| `model_compatibility` / `origin_loader` | Optional weather/cant adapters and authored callback loading. |
| `model_transaction` / `model_reporting` | Prepare an isolated draft, commit a complete model, and report the result. |
| `runtime_config` / `runtime_state` | Validate and compile shared model settings; retain separate carriage samples. |
| `motion` / `motion_response` / `curve_response` / `track_response` / `vehicle_response` | Motion maths, time damping, and curvature/track/vehicle response. |
| `bounded_cache` / `animation_bindings` / `values` | Shared cache, animation names, and validation helpers. |

The private runtime payload is a versioned record at `transformatorConfig.params.swayingWaying`. It contains booleans, named profiles, settings, and an array of section records. The old flat internal parameters are no longer supported. Public settings, author metadata, LOD ranges, and third-party parameters remain intact.

Adaptation operates on an isolated copy during loading and commits only after every selected LOD, generated name, and retargeted attachment passes validation. LOD and child lists must be dense arrays; malformed lists are rejected before adaptation. A rejected draft never changes the source. A successful commit preserves existing table identities and aliases. Authored duplicate node names are retained; generated wrappers cannot introduce new collisions. Empty native placement placeholders do not count as body groups.

Known vanilla transformators use direct wrappers. Custom transformators must resolve every declared callback before adaptation; unresolved callbacks cause the whole model to be skipped and logged. An occupied private runtime namespace also leaves the model unchanged. Real Track Cant and the existing Realistic Environment Pro integration remain behind explicit adapters. Opaque metadata is never searched for arbitrary strings to rewrite.

Runtime configuration, section geometry, and animation names are shared per model and revision. Compiled model identity retains the resource name and revision as scalar values, so reusing an input parameter table cannot reuse another model's carriage state. Each carriage owns one mutable motion sample and its damping clock and velocities, updated in place. Damping, the speed envelope, and enabled curve lean are evaluated once per carriage before its sections; active damping shares one exponential between both responses, and settled or paused responses skip it. Model, carriage, track, geometry, and waveform caches use bounded LRU eviction rather than clearing every entry at capacity. Invalid motion configuration is cached and reported once per revision, independently of authored callbacks.

Once a stopped carriage settles, it emits neutral motion directly and skips response and waveform work while keeping its damping clock current for restart. Consists with at least 20 carriages and enabled pitch/heave can share exact distance-dependent sine/cosine pairs per profile and Lua context; fixed phase and section coefficients are reused while live spectrum weights are applied during evaluation. Sharing activates after observed coordinate reuse. Smaller consists and roll-only motion retain direct evaluation. Both paths preserve the same motion, without assuming worker affinity or retaining waveform history. See [Motion performance](docs/performance.md) for the benchmark and its limits.

The regression suites cover model adaptation, reference safety, staged failures, callback forwarding, settings integration, cache pressure, track-query budgets, and motion maths. Motion tests compare the optimised evaluator against independent front/rear support samples in both long-wave phase modes. Normal validation requires the standard motion components to be enabled; the experimental `carriageLag` switch may be on or off. Explicit isolation validation permits other disabled switches in the generated build while running the regressions with every component enabled, including their individual switch checks.

### Motion isolation

Developer switches live in [`src/swaying_waying/motion_config.tl`](src/swaying_waying/motion_config.tl). All default to `true` except the experimental `carriageLag`, which defaults to `false`. After making an isolation edit, generate and validate the diagnostic build with:

```sh
scripts/validate.sh --generate --isolation
```

Use `scripts/validate.sh --isolation` to check an existing diagnostic build. This preserves disabled switches in the runtime files; the regression fixtures enable all components in memory so their normal expectations and individual switch checks remain meaningful. Type checking, generated-file checks, formatting, and regression checks still run. Normal validation continues to reject disabled standard motion components.

Reload the game so its Lua contexts load the edited configuration. These switches respect the in-game settings and affect Swaying Waying's added motion; native tilting and authored vehicle animations continue to run. Restore the default switch values and run `scripts/validate.sh --generate` before release.

| Switch | Effect when `false` |
| --- | --- |
| `roll` | Disables procedural roll and curve lean. |
| `pitch` / `heave` | Disables that suspension axis. |
| `shortWave` / `longWave` / `thirdWave` | Removes that wave from every axis, retaining the other waves' original weights. |
| `irregularity` | Removes amplitude and spacing variation, restoring the regular three-wave profile for comparison. |
| `curveLean` | Disables outward curve lean while retaining procedural roll. |
| `trackResponse` | Uses neutral track amplitude and spectrum, without track-response queries. |
| `vehicleResponse` | Removes comfort, maintenance, and author-tag amplitude modifiers. |
| `speedEnvelope` | Uses full procedural strength from 5 km/h; motion still settles below that speed. |
| `carriageLag` (default off) | Uses an independent long-wave phase per carriage, removing the experimental common consist phase and approximate 20 m carriage lag. |
| `sectionLag` | Removes section offsets from both individual and shared waves. |

To compare long-wave modes, leave only `roll` and `longWave` enabled, including disabling `irregularity`. This gives independent carriage long waves at their normal 28% neutral-track weight with a common full-strength envelope. Enable `carriageLag` to compare the experimental consist phase and approximate spacing. Restore the default switch values for normal operation.

The read-only native spacing probe and its orientation findings are documented in [Native spacing investigation](docs/native_spacing.md). The disabled bridge module remains a guard for old console-history calls.

The temporary render comparison of supplied and queried curvature is documented in [Native curvature investigation](docs/native_curvature.md). Its dedicated configuration controls bounded diagnostic logging; it does not change the curve-lean input.

The read-only output inventory and capture findings are documented in [Runtime LOD investigation](docs/native_lod.md). Its probe is disabled. Existing native callback limits already match the sway limit on most installed vanilla rail models; an independent runtime gate has not been adopted for models that retain longer native animations.

With all motion components enabled, direct combined roll, pitch, and heave use seven trigonometric evaluations per section. Warmed shared evaluation uses four per matching distance pair and profile in a context, plus three per section for the variable short wave's centre and supports. With irregularity disabled, the regular profile retains six direct or shared evaluations. Irregularity adds polynomial interpolation, with cached lattice coefficients refreshed only when the sampling cell or seed changes. Roll alone uses three trigonometric evaluations per section and samples lateral amplitude and short-wave spacing. Settled motion skips all waveform and irregularity work. Disabled waves skip their trigonometric evaluations. Long-wave roll isolation uses one sine per section. Support-point geometry is cached, and consist propagation requires no engine queries, inter-carriage messages, or waveform history.
