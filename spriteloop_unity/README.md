# SpriteLoop Community Runtime for Unity

Unity 2021.3+ runtime support for SpriteLoop `.spla` version 1 packages.

## Install

The Unity Package Manager ID is `com.justifun.spriteloop`. For the prebuilt `.tgz`, open **Window > Package Manager**, choose **+ > Add package from tarball**, and select `com.justifun.spriteloop-1.0.7.tgz`. To use the source folder instead, choose **+ > Add package from disk** and select this folder's `package.json`. Unity also installs its official Newtonsoft JSON package dependency.

## Use an imported .spla asset

1. Drag a `.spla` file anywhere under the Unity project's `Assets/` folder.
2. Add `SpriteLoopPlayer` to a GameObject.
3. Assign the imported `SpriteLoopAsset` to the component's **Package** field.
4. The first animation frame appears immediately in the Scene view. Disable **Preview In Editor** if a static preview is not wanted.
5. Enable **Load On Start** and **Autoplay**, then enter Play Mode.

The component packs all base and variant images into one runtime atlas, then renders every part through one combined dynamic mesh, one `MeshRenderer`, and one material.

The editor preview does not advance the animation. Its generated mesh, material, texture, and helper objects are transient and are not saved into the scene or prefab.

## Arrow key movement sample

In Package Manager, open the package's **Samples** section and import **Arrow Key Movement**. Add `SpriteLoopArrowKeyMovement` to the same GameObject as `SpriteLoopPlayer`, then adjust **Speed** in the Inspector. The component supports both Unity's legacy Input Manager and the newer Input System.

## StreamingAssets and runtime bytes

Place an unchanged `.spla` file under `Assets/StreamingAssets/` and enter its relative path in **Streaming Assets File**, or call:

```csharp
StartCoroutine(player.LoadFromStreamingAssets("characters/robot.spla"));
player.Load(splaBytes);
player.LoadFile(absolutePath);
```

`LoadFile` is intended for platforms with direct filesystem access. `LoadFromStreamingAssets` uses `UnityWebRequest`, including Android and WebGL-compatible StreamingAssets URLs.

## Playback and appearance API

See [SpriteLoop Animation Controls for Unity](Documentation~/AnimationControls.md) for complete play, pause, resume, animation-changing, loop, speed, seeking, and event examples.
See [Runtime Control Overrides](Documentation~/ControlOverrides.md) for procedural offset and absolute part/control transforms.
See [SpriteLoop Performance](Documentation~/Performance.md) for the current rendering behavior and ranked scaling improvements.

```csharp
player.Play("Idle");
player.Pause();
player.Resume();
player.SetFrame(12);
player.SetTime(0.5f);
player.SetSkin("blue_robot");
player.SetVariant("eyes", "smile");
player.ClearVariant("eyes");
player.SetControlPosition("weapon_control", new Vector2(8f, -3f));
player.SetControlAngle("weapon_control", 20f);
player.SetControlScale("weapon_control", new Vector2(1.1f, 1.1f));
player.ClearControlOverride("weapon_control");
```

Subscribe to `Loaded`, `LoadFailed`, `FrameChanged`, `AnimationLooped`, `AnimationFinished`, and `AnimationEvent`. `TryGetPartTransform` returns the generated pivot transform for attachments.

## Supported SPLA features

- multipart PNG rendering and authored draw order;
- one atlas-backed renderer and draw call per character and camera;
- pivots, position, rotation, independent scale, two-axis skew, opacity, tint, and per-frame Z offsets;
- skins, visibility overrides, manual variants, and state-driven skin variants;
- authored frame events, including frames crossed during low frame rates;
- persistent offset and absolute position, angle, and scale overrides for image and empty control parts;
- looping overrides, seeking, playback rate, and runtime reloads.

The renderer uses Unity's built-in `Sprites/Default` shader and `MeshRenderer`, so it works without a specific render pipeline. Because all parts share one combined renderer, unrelated scene sprites cannot be sorted between individual character parts. State crossfade fields currently select the dominant state image rather than drawing two state images simultaneously. SPLA packages do not define collision geometry, so the runtime does not generate colliders.
