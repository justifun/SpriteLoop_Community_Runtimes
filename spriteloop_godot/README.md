# SpriteLoop Community Runtime for Godot 4

SpriteLoop for Godot imports `.spla` character packages as native Godot resources and plays their multipart animations with a `SpriteLoopPlayer2D` node.

## Requirements

- Godot 4.2 or newer
- An SPLA version 1 package exported by SpriteLoop

## Install

1. Copy the `addons` folder from this package into the root of your Godot project.
2. In Godot, open **Project > Project Settings > Plugins**.
3. Enable **SpriteLoop**.
4. Add your `.spla` file anywhere under the project folder. Godot imports it as a `SpriteLoopResource`.
5. Add a `SpriteLoopPlayer2D` node and drag the imported `.spla` resource to its **Sprite Loop** property.

The character's first animation frame appears in the 2D editor. At runtime the node plays the first animation automatically unless **Autoplay** is disabled. `SpriteLoopPlayer2D` is centered on the authored canvas by default, so its Node2D position is the visual center of the package.

## Basic playback

```gdscript
@onready var character: SpriteLoopPlayer2D = $SpriteLoopPlayer2D

func _ready() -> void:
	character.play("idle")       # Animation ID or display name.

func pause_character() -> void:
	character.pause()

func resume_character() -> void:
	character.resume()

func switch_animation() -> void:
	character.play("run", SpriteLoopPlayer2D.LoopMode.LOOP)

func play_once() -> void:
	character.play("attack", SpriteLoopPlayer2D.LoopMode.ONCE)
```

`play()` accepts `FROM_PACKAGE`, `LOOP`, or `ONCE`. `FROM_PACKAGE` uses the loop flag authored in SpriteLoop.

## Seeking and speed

```gdscript
character.playback_speed = 0.5
character.set_animation_frame(3)
character.set_animation_time(0.25)
character.set_animation_progress(0.75)
```

Seeking does not emit authored frame events by default. Pass `true` as the second argument if the destination frame's events should fire.

## Skins and variants

```gdscript
character.set_skin("blue")
character.set_variant("hat", "wizard_hat")
character.clear_variant("hat")
character.clear_variants()
```

Parts, skins, variants, animations, states, and their display names can be addressed case-insensitively. Exact IDs remain the preferred stable references.

## Signals

```gdscript
func _ready() -> void:
	character.frame_changed.connect(_on_frame_changed)
	character.animation_looped.connect(_on_animation_looped)
	character.animation_finished.connect(_on_animation_finished)
	character.animation_event.connect(_on_animation_event)

func _on_animation_event(animation_id: String, frame: int, source_frame: int,
		event_name: String, data: String) -> void:
	print(animation_id, " ", frame, " ", event_name, " ", data)
```

Available signals are:

- `package_loaded()`
- `load_failed(message)`
- `frame_changed(frame)`
- `animation_looped(animation_id)`
- `animation_finished(animation_id)`
- `animation_event(animation_id, frame, source_frame, event_name, data)`

## Runtime queries

```gdscript
print(character.is_loaded())
print(character.is_playing())
print(character.is_paused())
print(character.get_package_name())
print(character.get_current_animation_id())
print(character.get_current_animation_name())
print(character.get_current_frame())
print(character.get_frame_count())
print(character.get_animation_time())
print(character.get_animation_duration())
print(character.get_animation_progress())
print(character.get_current_skin_id())
print(character.get_last_error())
```

Indexed enumeration is available through:

- `get_animation_count()`, `get_animation_id(index)`, `get_animation_name(index)`
- `get_skin_count()`, `get_skin_id(index)`, `get_skin_name(index)`
- `get_part_count()`, `get_part_id(index)`, `get_part_name(index)`
- `get_variant_count()`, `get_variant_id(index)`, `get_variant_name(index)`, `get_variant_part_id(index)`

`get_part_transform(part_reference)` returns the current local `Transform2D` at a part's authored pivot. Multiply it by the player's `global_transform` when a world-space transform is needed:

```gdscript
var local_hand := character.get_part_transform("hand")
var world_hand := character.global_transform * local_hand
```

## Rendering notes

- A character uses one `Node2D`, regardless of its part count.
- Imported image bytes and decoded textures are shared by all players using the same `SpriteLoopResource`.
- The player only rebuilds its draw data when the displayed animation frame or appearance changes.
- Godot's normal CanvasItem batching applies. Separate source textures can still require separate draw calls; SPLA packages that use shared atlas images batch best.
- Use the inherited **Texture Filter** CanvasItem property to select nearest or linear filtering.

## Package contents

```text
addons/spriteloop/
  plugin.cfg
  plugin.gd
  icon.svg
  spriteloop_importer.gd
  spriteloop_resource.gd
  spriteloop_player_2d.gd
examples/
  basic_controls.gd
```

