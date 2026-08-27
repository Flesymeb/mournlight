# Maaack FPS Menu Component

Curated from `Maaack/Godot-Menus-Template` at commit
`250147d0e5d573061d7393d127f7f4295b119e73` under the MIT license. Third-party
attribution is preserved in `ATTRIBUTION.md` and the addon attribution files.
This is an editable product-source starting point for opening, main menu,
pause, audio/video/input settings, loading, credits, focus navigation and
controller input. Preserve the complete component bundle, then adapt its page
scenes, Theme resources, autoload paths and project settings to the host game.

## Open in Godot

Import this bundle's `project.godot` in the Godot Project Manager. The
production-skinned main menu is configured as the project's main scene, so
**Run Project** opens the complete main/settings/credits flow immediately.

The curated bundle now applies a production-oriented FPS skin directly to the
real Maaack page hierarchy rather than shipping a parallel mock page:

* `scenes/menus/main_menu/main_menu.tscn` retains `MainMenu` scene loading,
  sub-menu and confirmation behavior while using an image-backed, borderless
  left navigation composition. Connect `game_started` when the host game wants
  to decide start-game routing in code, or set `game_scene_path` normally.
* `master_options_menu_with_tabs.tscn` keeps the real Controls, Audio and Video
  settings/storage implementation. Its main-menu and pause wrappers use the
  same transparent theme and focus behavior.
* `pause_menu.tscn` and `loading_screen.tscn` retain the template's pause,
  return, loading and error flow while using compact floating content.
* The main-menu footer and Credits flow contain replaceable demonstration
  identity fields. Update them for the shipping game or studio.
* `addons/fps_menu_skin/fps_menu_theme.tres` supplies Barlow Condensed,
  transparent normal buttons, restrained focus accents, thin separators and
  compact progress treatment instead of broad bordered cards.
* The main background has a bounded 10-pixel mouse parallax effect with a
  separate 36-pixel overscan, so edge motion stays safely outside the visible
  viewport. Set `background_parallax_pixels` to `0` to disable motion, tune
  `background_overscan_pixels` independently, or replace
  `BackgroundTextureRect.texture` with product art.
* `FPSMenuAudioFeedback` extends the template's existing `UISoundController`;
  focus, confirmation and cancel cues remain routed through the `SFX` bus.

The reusable bundle leaves its setup-wizard editor plugin disabled. Adapt the
editable scenes directly, or enable the plugin manually for an intentional
interactive setup.

Do not replace this flow with a few `Panel` and `Label` nodes. Preserve the
license, copy only the required subsystem into product-owned paths, and verify
every required page and return-to-game transition.

The bundled industrial background is a replaceable production-safe starting
point, not a mandate for every game. Preserve the working navigation,
configuration, focus, motion bounds and sound routing while replacing title,
subtitle and background when the product brief defines another setting. Do not regress
to the original gray background, repeated boxed buttons, opaque page-sized
panels, default Godot font or implementation-facing demo copy. A runnable
default-theme page is still blockout quality and must not pass visual
acceptance.
