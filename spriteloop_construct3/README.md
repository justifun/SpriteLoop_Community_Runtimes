# SpriteLoop Community Construct 3 plugin

Addon SDK v2 world object for SpriteLoop `.spla` version 1 packages.

## Requirements

- Construct 3 r491 or newer.
- A SpriteLoop `.spla` version 1 package containing `manifest.json` and its referenced images.

The r491 minimum is needed so the custom importer can assign the generated project file to the newly created object using its stable project-file SID.

## Import a character

Install the packaged `.c3addon`, restart Construct, and drag an `.spla` file directly on to an open Layout View. The importer:

1. creates a SpriteLoop object type and instance;
2. assigns the imported data file, canvas size, first animation, and drop position.

If the layout already contains a SpriteLoop object, the importer asks what to do before it changes the project:

- **Overwrite** replaces the nearest existing SpriteLoop object's imported character data and editor preview while preserving its position. **Keep scale** is enabled by default, preserving the current size of every updated instance; clear it to reset them to the new package's canvas size. Copies of that object which use the same imported data are updated too.
- **Add new** creates a separate object type and a uniquely named asset folder at the drop position, so it cannot replace the first character's files.
- **Cancel** leaves the project unchanged.

Construct's custom ZIP importer exposes the files inside an archive but not the original archive blob. For that reason the project stores an internal `<package>.spla.json` plus uniquely named image files rather than retaining the source ZIP. This also avoids runtime ZIP dependencies and works in Construct's worker mode.

Imported part and variant images are combined into 4096×4096-or-smaller PNG atlas pages with two pixels of edge extrusion. The runtime uses each image's generated UV rectangle, reducing texture changes and allowing Construct to batch consecutive character parts which share an atlas page. Images too large for an atlas page remain standalone. Existing projects containing older non-atlased `.spla.json` files remain supported; drop the source `.spla` on the layout again to regenerate it with atlas metadata.

The importer also flattens the resolved first pose to the object type's editor image, so the character is visible in the Layout View. Animation playback remains a runtime Preview/export feature.

At runtime the object remains transparent while its package and textures load, then starts drawing the selected animation without a placeholder-color flash.

## Object properties

- **SpriteLoop data**: generated `.spla.json` project file; assigned automatically by drag-and-drop import.
- **Default animation**: exported animation ID or display name. Empty selects the first animation.
- **Autoplay**: start after all textures load.
- **Loop**: use the package setting, always loop, or never loop.
- **Playback rate**: initial speed multiplier.
- **Default skin**: exported skin ID or display name.
- **Emit events**: enables authored frame-event triggers.

## Event-sheet API

Version 1.0.0.6 exposes all 33 actions in one **SpriteLoop Actions** section of Construct's action dialog. This includes:

- **Loading**: Load package and Reload package.
- **Playback**: Play by index, Play next, Play previous, Play random, Restart, Toggle pause, Step frame forward, Step frame backward, and Set progress.
- **Appearance**: Set skin by index, Set next skin, Set previous skin, Set random skin, Set random variant, Randomize variants, and Reset appearance.

The original Play, Stop, Pause, Resume, Set frame, Set time, Set playback rate, Set looping, skin, variant, tint, and event-emission actions remain available.

There are 65 expressions in total, including matching runtime queries for the new controls:

- **Loading**: `DataFile`, `Loading`, `Loaded`, and `LastError`.
- **Playback**: `AnimationId`, `AnimationName`, `AnimationIndex`, `Frame`, `SourceFrame`, `FrameCount`, `FPS`, `PlaybackTime`, `Duration`, `PlaybackRate`, `AnimationProgress`, `Playing`, `Paused`, `Looping`, and `LoopMode`.
- **Skins and variants**: `SkinId`, `SkinName`, `SkinIndex`, `SkinCount`, `SkinIdAt`, `SkinNameAt`, `VariantCount`, `VariantIdAt`, `VariantKeyAt`, `VariantNameAt`, `VariantPartIdAt`, `VariantPartKeyAt`, `ManualVariantCount`, `PartVariantId`, `PartVariantKey`, `PartVariantName`, `PartManualVariantId`, `TintRed`, `TintGreen`, and `TintBlue`.
- **Parts**: `PartX`, `PartY`, `PartCenterX`, `PartCenterY`, `PartAngle`, `PartScaleX`, `PartScaleY`, `PartOpacity`, `PartSkewX`, and `PartSkewY`.
- **Package and events**: animation/part inventory expressions, last-event expressions, and `EventEmissionEnabled`.

Boolean state expressions return `1` or `0`. Collection indexes are zero-based. `AnimationProgress` is normalized from `0` to `1`, and tint channels use `0` to `255`.

Useful triggers include:

- **On loaded** / **On load failed**
- **On animation finished** / **On animation looped**
- **On frame changed**
- **On any animation event** / **On animation event**

Use `LastEventName`, `LastEventData`, `LastEventFrame`, and `LastEventSourceFrame` inside animation-event triggers.

Part expressions such as `PartX`, `PartY`, `PartCenterX`, `PartCenterY`, `PartAngle`, and `PartOpacity` expose the current resolved transform for attachments. Part positions are returned in layout/world coordinates.

## Runtime support

The renderer supports:

- multi-part PNG composition and authored draw order;
- pivot, translation, rotation, independent scale, two-axis skew, opacity, and tint;
- per-frame Z offsets;
- skins, part visibility, state-driven variants, state crossfades, and manual variant overrides;
- SpriteLoop frame events, including crossed frames during low frame rates;
- instance size, angle, opacity, color, blend mode, sampling, effects, pixel rounding, and savegames;
- WebGL and WebGPU through Construct's renderer abstraction;
- DOM mode and worker mode using `IAssetManager`, `createImageBitmap`, and renderer-managed textures.

While an animation is playing, SpriteLoop keeps rendering active at the project's display rate even when the authored animation itself uses fewer frames per second. Redraw requests are coalesced once per runtime: after the first playing instance requests a frame, all other instances and unlimited ticks reuse that pending request until drawing begins. This keeps Construct's FPS counter intuitive without issuing hundreds of redundant `updateRender()` calls. Paused and stopped instances do not tick or request animation redraws.

Runtime instances that select the same imported data file share its normalized manifest, encoded image blobs, and renderer textures. The resources are loaded and uploaded once per runtime, survive while any matching instance remains, and are deleted when the last matching instance is released. Shared textures are also rebuilt only once after WebGL/WebGPU context restoration.

## Current scope

- SPLA manifest version 1 is supported.
- The object uses its rectangular canvas bounds for picking/collisions; it does not generate per-part collision polygons.
- Editing a source `.spla` externally requires dropping it into Construct again to refresh the extracted project files.
- The Layout View displays a static flattened first pose; it does not animate or update when runtime-only skin and variant actions run.


