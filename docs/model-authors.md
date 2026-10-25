# Supporting Swaying Waying

Most rail and tram models work automatically. Add `swayingWaying` to the model's existing `metadata` table when you need to select particular bodies or describe an unusual hierarchy. Keep the model's other metadata and original transformator.

These declarations do not require Swaying Waying to be installed. No import, dependency on its runtime, or custom transformator is needed.

## Opting out entirely

Add `swaying_waying_none` to the existing `metadata.transportVehicle.filterTags` array:

```lua
filterTags = { "default", "swaying_waying_none" },
```

This takes precedence over all other sway settings. Swaying Waying leaves the vehicle's hierarchy, transformator, and cameras untouched. The offline checker reports this as a successful opt-out, including in strict mode.

## Enabling only cameras or only sway

Use these tags in the same `metadata.transportVehicle.filterTags` array:

| Tag | Our vehicle motion | Our camera additions |
| --- | --- | --- |
| `swaying_waying_only_camera` | Disabled | Allowed by the camera settings |
| `swaying_waying_no_camera` | Allowed by the sway settings | Disabled |
| Both tags together, or `swaying_waying_none` | Disabled | Disabled |

`swaying_waying_only_camera` leaves the model's original motion and transformator in place, including author-owned sway. It ignores the unused sway metadata and motion-response tags. It does not create procedural motion for the camera alone. The normal no-sway camera policy applies: **Stable** or **Both** can add stable views; **Sway** or **Disabled** adds no views. Extra cameras still follow their setting when stable views are enabled.

`swaying_waying_no_camera` prevents our generated views and camera HUD descriptors, including Extra views. Existing authored cameras remain available. Vehicle motion still follows the player's sway settings and normal compatibility checks.

Neither tag enables a feature the player has disabled. The offline checker accepts camera-only and complete opt-outs in strict mode; its camera-only classification describes the author policy, rather than verifying generated views.

## Selecting a single body

For a model whose moving body is named `body`, add:

```lua
swayingWaying = {
    sections = {
        { group = "body", lag = 0.0 },
    },
},
```

`group` is a node name, not a mesh filename. It must resolve to exactly one node in each active LOD. The named node's visual content and eligible descendants receive sway. Other branches stay fixed. Existing animations remain attached to their original nodes.

Explicit sections are authoritative. The mod does not automatically add movement to unlisted bodies. If a declared section cannot be wrapped, the entire adaptation is cancelled and the original model is retained.

## Articulated vehicles and tenders

Give each independently moving body a section:

```lua
swayingWaying = {
    skipFromLod = 2,
    wheelbase = 12.0,
    sections = {
        { group = "engine_body", lag = 0.0 },
        { group = "tender_body", lag = 8.0, wheelbase = 8.0 },
    },
},
```

`lag` is required, finite, and non-negative, in metres. A positive value samples individual motion at `distance - lag` and offsets the shared consist profile along the carriage, accounting for its facing. Use zero for the leading section and increasing distances for following sections. Curve lean remains shared across the vehicle.

Groups must not contain one another. Supply between 1 and 32 sections as a dense Lua array. Each group name, including its LOD aliases, must belong to only one section; model attachment references are shared across LODs.

The optional `wheelbase` is between 2 and 30 metres. A section value overrides the top-level value. Otherwise the mod uses the section's fake-bogie support positions or the model length. Wheelbase affects pitch and heave, not roll.

## Different names in different LODs

Keep a stable section identity in `group` and override the actual node name where necessary:

```lua
swayingWaying = {
    skipFromLod = 2,
    sections = {
        {
            group = "body",
            lag = 0.0,
            groupsByLod = {
                [0] = "body_high",
                [1] = "body_medium",
                [2] = "body_low",
            },
        },
    },
},
```

LOD keys are **zero-based**, like the game: `[0]` means the first LOD. Missing entries use `group` as the node name. If every LOD has an override, `group` can be a logical section name that does not occur in the hierarchy.

Map distant inactive LODs too when seats, labels, placement groups, or other references need matching anchors there. Their anchors remain unanimated. Each mapping must refer to an existing LOD; aliases cannot select several nodes or merge several sections into one.

## Unusual origins, rotations, and scale

Sections normally sway in model axes: X longitudinal, Y lateral, Z vertical. The mod compensates for the selected group's inherited translation, rotation, reflection, and scale. Heave is measured in model metres, regardless of export scale. Geometry at rest is preserved.

The default pivot uses the group's model-space X/Y origin and a Z height inferred from the model bounds. Override it if the origin is not the intended suspension centre:

```lua
swayingWaying = {
    sections = {
        {
            group = "offset_body",
            lag = 0.0,
            pivot = { x = 4.0, y = 0.0, z = 0.8 },
        },
    },
},
```

All three pivot coordinates are required, finite, and expressed in **model coordinates**, in metres, before vehicle placement in the world. They are not offsets from the group's local origin. The same pivot applies across LODs, so different export origins do not change the motion centre.

For a body whose authored local axes should define its roll, pitch, and heave directions, add `axes = "group"` to that section. Its inherited orientation is retained while axis scale is removed. The pivot still uses model coordinates. Group axes must be orthogonal; use the default `axes = "model"` for sheared transforms. Singular/non-affine section frames are rejected.

Coordinate frames are calculated at model load. Existing procedural placement and parent animations still apply to the resulting hierarchy; check those combinations in game.

## Keeping wheels and mechanisms fixed

A suitable hierarchy is:

```text
RootNode
  body                 <- select this section
    body_mesh
    windows
    doors
  bogie_front           <- original axle/bogie branch
  bogie_rear
  fixed_mechanism
```

Sections move their descendants, except branches containing axles declared by the model's rail-vehicle configuration. Put other fixed mechanisms outside the selected body. An unlisted child inside a moving body still inherits its parent's movement.

If an axle-bearing branch also contains the whole body, selecting its parent may leave nothing eligible to sway. Select the actual body group or separate the body and axle branches. A diagnostic identifies the affected section and LOD.

Pure empty placement locators can be selected explicitly; their names remain attached to their moving anchor. Locators with their own animations or fixed children need a suitable body group instead. Skin/bone and procedural-placement behavior still needs an in-game check.

## Controlling the sway LOD range

`skipFromLod = 2` enables sway in LODs 0 and 1. It can be used with or without `sections`. It must be a positive integer no larger than the model's LOD count. Use the opt-out tag to disable sway entirely.

This cutoff affects sway. Original animations keep their longer transformator range: an original limit of 4 remains 4 when sway stops at 2. An explicit sway limit may extend the original range, including for a custom transformator, so choose an extension only when that transformator supports the additional LODs.

Without an override, the [automatic LOD policy](../README.md#track-and-vehicle-response) applies.

## Configuration errors

Unknown fields, invalid values, conflicting group names, missing or ambiguous active groups, overlapping sections, and sections that cannot receive motion prevent adaptation. The original model is retained. Check the log for messages such as:

```text
swayingWaying.sections[2].lag must be a finite distance >= 0 metres (got nil)
swayingWaying.sections[1] group 'body_medium' must occur exactly once in LOD 1 (found 0)
```

Check spelling and capitalization. `section` and `sections` are different fields. Do not write to `metadata.transformatorConfig.params.swayingWaying`; that table is reserved for generated runtime configuration.

## Checking a model

Run these commands from the Swaying Waying checkout with Python 3.10+ and Lua 5.2+. Teal is also needed if your resources or their dependencies contain typed `.tl` scripts. Use the development dependencies described in the [README](../README.md#development).

```sh
python3 scripts/check_game_models.py /path/to/my_mod/content/vehicle/train/example.mdl --strict --verbose
python3 scripts/check_game_models.py /path/to/my_mod --dependency /path/to/required_mod --strict
```

The checker discovers `mod.json` and the mod's content directory. For a standalone `.mdl` without a manifest, its containing directory is the resource root; add `--namespace my_mod` if it uses an explicit namespace. Repeat `--dependency` for additional resource providers. Conflicting namespace definitions are rejected.

Use `--game-dir /path/to/Transport\ Fever\ 3` or `TPF3_GAME_DIR` for a non-default installation. Omitting the target checks vanilla rail models as before.

The checker loads model factories, relative/namespaced helpers, and original transformator callbacks. It reports each author's model and checks that adaptation preserves visual content, materials, skins, and geometry at rest. `--verbose` shows selected groups and per-LOD results. Load errors or changed rest geometry always return a failure exit status; `--strict` also fails on skipped rail models and warnings. Explicit opt-outs succeed.

This is an offline load/adaptation check. It does not render meshes, run the game's simulation, or reproduce the complete enabled-mod loading order. A resource that needs native game APIs may require in-game validation. Finish by checking forward/reverse travel, LOD transitions, articulated placement, doors and other animations, wheels, seats, labels, particles, and cameras in game.

## Models with custom transformators

Keep your original transformator. Swaying Waying wraps its supported callbacks and forwards their capture parameters. Avoid relying on cached numeric hierarchy indices across model modifiers: injecting motion groups changes those indices. Named groups and the metadata contract above are the supported author interface.

Models with existing paired `sway` and `tender_sway` tilt pivots remain author-owned and are skipped unless the author explicitly permits camera-only integration with `swaying_waying_only_camera`. That tag keeps their original motion intact. Cayde's Track Cant remains incompatible; the original Real Track Cant is supported. These compatibility decisions are not bypassed by section metadata.
