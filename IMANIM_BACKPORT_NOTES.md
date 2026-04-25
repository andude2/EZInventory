# ImAnim + Item Inspector Backport Notes

This note summarizes the MQ2Mono / E3Next work that is relevant if we want to backport the same UI ideas into `EZInventory` later.

## 1. MQ2Mono ImAnim runtime ownership

The important native-side fix was not just exposing ImAnim calls. `MQ2Mono` now owns a stable ImAnim context and rebinds it before wrapper calls run. That matters because ImAnim is stateful, unlike the thin ImGui passthroughs.

Practical rule for a Lua port:
- treat ImAnim like a shared frame-scoped service
- initialize or restore the context once per render path
- call `BeginFrame` once per frame before issuing tween calls
- use stable IDs per row/item/property

## 2. ImAnim wrappers that were exposed

The MQ2Mono bindings now include thin pass-throughs for the common UI animation calls used by `E3Inventory`:
- `TweenFloat`
- `TweenColor`
- `TweenVec2`
- `TweenVec2Rel`
- `StyleTween`
- `StyleBlend`
- `Shake`
- `ShakeVec2`
- `Wiggle`
- `OscillateColor`
- `NoiseChannelColor`
- `SmoothNoiseColor`
- `TextStagger`
- gradient helpers
- clip/path helpers where needed

The key design point is that the wrappers stay thin; MQ2Mono handles the native state so C# only asks for animation values.

## 3. Missing ImGui helpers that were added back

We also restored a few small ImGui pass-throughs that made the inspector easier to build cleanly:
- `Dummy`
- `BeginGroup`
- `EndGroup`
- `Spacing`
- `NewLine`
- `TextDisabled`
- `SeparatorText`

These are useful for composing compact header/body sections without custom layout hacks.

## 4. Item inspector popup pattern

`E3Inventory` now uses a custom item inspector popup instead of opening the native EQ item window directly.

Behavior:
- clicking an item name or icon opens a dedicated inspector window
- the window is a normal titled ImGui window, not a hidden popup
- the titlebar `X` closes it the same as the `Close` button
- there is still an `Open EQ Link` button if we want the native item window

Layout idea to copy:
- top header row: icon, name, flags
- compact metadata block: owner, location, type, quantity, value, classes, races
- stat area: totals plus heroic stats
- resist area: separate right-side block
- augments: slot-centric lines like `Slot 1: Type 24: <aug name>`

## 5. Layout details worth copying

The inspector was tuned to feel closer to the EQ `ItemDisplay` window, but cleaner.

Useful rules:
- keep the window narrow enough to feel like a tooltip/inspector, not a full modal
- use a short fade/slide entrance so it feels anchored to the clicked item
- keep the top summary dense and avoid one-field-per-line layouts
- give the stat block enough width so parenthetical heroic values do not overlap the resist column
- use a visible gap between the stat and resist halves

## 6. Stat formatting pattern

The current E3 implementation uses:
- left side: primary stats with a separate heroic column
- right side: resists with a separate heroic column
- utility values like AC/HP/Mana/End/Tribute shown in a compact block above the stat grid

Example style:
- `STR  80  +220`
- `MR   35  +10`

That pattern maps well to `EZInventory` if we want to preserve EQ feel without copying the old XML window exactly.

## 7. Suggested Lua backport shape

If we port this to `EZInventory`, the cleanest structure is:
- a shared animation helper layer that owns `BeginFrame` and stable IDs
- an item inspector component that renders from the clicked item
- an anchor/positioning helper so the inspector opens near the clicked row or tile
- a compact stat table with a gap between primary stats and resists

The main thing to avoid is building the popup as a modal dialog. It works better as an anchored inspector card.
