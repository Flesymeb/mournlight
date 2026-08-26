# Mournlight — Product Requirements Document

## 1. Product identity

**Mournlight** is an original, single-player, stylized 3D Survivor-like made
with native Godot 4.6 or newer. The player is a lantern-bearing cemetery warden
who must contain a moonlit outbreak, collect escaped wisps, shape a compact
build, and defeat the spirit that is keeping the dead awake.

The target is a polished, replayable seven-to-ten-minute vertical slice. It is
not an FPS, an over-the-shoulder shooter, a twin-stick shooter that requires
continuous manual fire, or a static combat showcase. The camera remains
high-angle and arena-readable; movement, target priority, positioning, dash
timing, and upgrade choices carry the experience while ordinary attacks fire
automatically.

The public demo repository must be buildable and playable without access to
the private GameLoop scaffold, private prompts, a private component pool, or
provider credentials. Public runtime code and shipped assets must carry the
licenses and notices needed for redistribution. Private/local references may
accelerate development, but they cannot remain an undeclared build or runtime
dependency.

## 2. Player promise

The player should feel that a small, nimble keeper is turning a dangerous
graveyard into a moving constellation of protective light. Every minute should
offer three readable decisions:

1. where to move to preserve an escape lane while collecting experience;
2. which immediate threat, elite, or pickup deserves target priority; and
3. which upgrade makes the current build behave differently.

The result should be charming and energetic rather than grim or gory. Pressure
comes from crowd movement, telegraphed attacks, route denial, and build tradeoffs,
not from realistic horror, visual clutter, or surprise contact damage.

## 3. Complete run

A fresh run follows this loop:

1. Start from the title screen and choose Play.
2. Enter one moonlit graveyard arena with the Warden Lantern equipped.
3. Move with ordinary input while the lantern automatically attacks a legal
   nearby target.
4. Defeat enemies, collect dropped wisps, and fill the experience bar.
5. On level-up, pause gameplay and choose one of three truthful upgrades.
6. Survive five escalating waves, including at least one meaningful enemy
   composition change and one elite encounter.
7. Defeat the Bellkeeper boss during the final wave.
8. Reach a result screen showing time, level, defeated enemies, damage dealt,
   damage taken, selected upgrades, and victory or failure.
9. Restart into a clean new run or return to title without stale actors, state,
   audio, pause ownership, or UI.

The normal successful run should last seven to ten minutes including upgrade
drafts and the boss. Individual wave duration, spawn budget, enemy cap, and
boss timing are data-driven and may be tuned from play evidence. Five waves
and the final boss are product requirements; their exact second counts are not.

## 4. Controls, camera, and player movement

### 4.1 Required input

- Keyboard: `WASD` move, `Space` dash, mouse position optionally biases target
  direction, `Esc` pause, and standard UI confirm/cancel/navigation.
- Gamepad: left stick move, south face button dash, right stick optionally
  biases target direction, start pause, and standard UI navigation.
- The player does not hold or repeatedly press a fire button for ordinary
  weapon output.
- Mouse/right-stick target bias is optional during play and can be disabled in
  Settings. With no aim input, deterministic automatic targeting remains fully
  viable.

### 4.2 Camera contract

- One high-angle perspective `Camera3D` frames the player, nearby enemies,
  projectiles, pickups, and at least one useful escape direction.
- The gameplay camera does not enter first-person, ADS, shoulder, or free-orbit
  modes.
- Camera follow is damped but never lags far enough to hide imminent threats.
- Shake and hit stop are short, intensity-bounded, and user-adjustable.
- Arena boundaries, tall props, trees, mausoleums, and particles must not
  repeatedly occlude the player or dangerous telegraphs. Use camera-aware
  composition, transparency, or authored sight lanes where necessary.

### 4.3 Player behavior

The player uses a `CharacterBody3D`-based motor with camera-relative planar
movement, stable collision sliding, visual facing independent from movement,
and an interruptible dash. Dash has a visible anticipation/onset/recovery,
declared cooldown, and a short invulnerability window. Damage grants bounded
post-hit invulnerability so overlapping enemies cannot erase the whole health
bar in one unreadable contact.

Player states include idle, locomotion, dash, attack/cast response, hurt, death,
victory, and UI-paused. State ownership must prevent dash, knockback, normal
movement, and death from writing contradictory velocity or invulnerability.

## 5. Combat and weapons

### 5.1 Shared combat rules

- Weapons use stable ids and data resources for damage, cooldown, range, area,
  projectile count, duration, targeting, hit policy, and upgrade modifiers.
- Automatic targeting chooses a legal threat deterministically. The default
  favors the nearest threat; active mouse/right-stick direction may prioritize
  a threat inside a forward cone with stable tie-breaking.
- Each emitted attack records its owning actor and weapon. A hit applies damage
  exactly as declared; an enemy death and its reward occur once.
- Player attacks, enemy attacks, pickups, and decorative effects remain
  distinguishable at final-wave density.
- There is no magazine, reload, ADS, first-person viewmodel, weapon pickup/drop,
  or firearm simulation requirement.

### 5.2 Weapon set

The demo contains three mechanically distinct weapons:

1. **Warden Lantern** — the starting weapon; fires a spectral bolt at the
   selected legal target. Its identity is reliable focused damage.
2. **Gravespade** — a short-range sweeping arc oriented toward the selected
   threat direction. Its identity is clearing an escape lane.
3. **Wandering Wisps** — persistent lights orbit the player and damage enemies
   according to an explicit per-target hit interval. Its identity is mobile
   area control.

The player can obtain all three during a run. Each weapon visibly and measurably
changes through upgrades in at least three relevant dimensions, such as cadence,
count, area, reach, damage, pierce, return behavior, orbit speed, or utility.
The three weapons cannot be renamed copies of one projectile scene.

## 6. Enemies and boss

The demo contains four ordinary archetypes plus one boss:

- **Mossling:** slow, durable melee pursuer that establishes the baseline lane.
- **Wispbat:** fragile, fast flanker that arrives in readable groups.
- **Bone Slinger:** ranged enemy with a clear wind-up, projectile, and recoverable
  firing lane.
- **Grave Brute:** elite-capable body blocker with a slow, telegraphed slam and
  an obvious danger radius.
- **The Bellkeeper:** final boss with a unique silhouette, boss health bar,
  at least two phases, a readable bell-wave attack, a summon or lane-pressure
  pattern, and a vulnerable recovery window.

Every ordinary enemy supports spawn, approach, attack telegraph, damage frame,
hurt, death, and drop behavior. Enemies must not spawn inside the protected
camera area, on collision, outside the arena, or within the minimum safe radius
around the player. Melee contact damage, ranged projectiles, slam areas, and
boss attacks have separate readable cues.

The representative peak is 25–40 simultaneously active ordinary enemies plus
the player, attacks, pickups, and effects on the target machine. Tuning may
reduce or increase that range only when recorded performance and play evidence
show that the final wave remains visibly dense, readable, and smooth.

## 7. Experience, levels, and build choices

Enemies drop collectible wisps. Collection increments authoritative experience;
crossing a threshold opens exactly one level-up transaction and preserves any
overflow. Gameplay clocks, enemy motion, attacks, and spawning pause while the
three-card draft remains interactive.

The demo includes at least 12 authored upgrades across:

- the three weapon identities;
- movement or dash utility;
- survivability;
- pickup reach or experience economy; and
- one deliberate risk/reward option.

Every card shows its name, icon, current effect, and concrete change. Eligibility,
rarity where used, maximum rank, incompatibility, and stacking order are
data-driven. Held confirm cannot choose more than once. A selected card changes
the authoritative build before gameplay resumes, and its effect must be
observable in the next relevant combat event.

At least three viable end-of-run build shapes must emerge from the available
choices: focused bolts, close-range sweeps, and orbiting area control. They may
share general stats but must not converge to the same visible attack pattern.

## 8. Wave and difficulty curve

The run controller owns warmup, active wave, upgrade pause, elite warning,
boss transition, victory, failure, and result states. A data-driven director
uses elapsed time, wave id, spawn budget, live cap, archetype weights, and boss
state. It cannot continue spawning after victory or failure.

- Wave 1 teaches movement, auto-attacks, collection, and the first draft.
- Wave 2 adds fast flank pressure.
- Wave 3 introduces a ranged lane and the first elite.
- Wave 4 combines archetypes at representative crowd density while preserving
  at least one recoverable movement choice.
- Wave 5 introduces the Bellkeeper and a controlled supporting crowd.

Escalation changes composition and spatial decisions, not only health. The
opening is forgiving enough to understand targeting and pickups. The final
wave demands dash timing and a coherent build without relying on unavoidable
damage or an excessively durable boss.

## 9. Arena and art direction

### 9.1 World layout

The entire run occurs in one authored, bounded cemetery garden with a readable
loop and cross-route. It includes three visually distinct landmarks: the keeper's
lantern post, a small mausoleum, and the cracked moon bell. Low walls, graves,
trees, fences, paths, and elevation accents create navigation decisions without
turning the arena into a maze or trapping swarm steering.

Collision and walkable space agree with visible geometry. Props do not float,
intersect important routes, create invisible barriers, or conceal the arena
edge. Spawn regions lie outside the protected camera area and lead naturally
toward the player.

### 9.2 Visual language

Use a cohesive stylized low-poly/cartoon 3D language with chunky silhouettes,
soft bevels, restrained texture detail, moonlit blue-violet shadows, warm gold
player light, and distinct hostile teal or magenta accents. The game should
look inviting enough for a broad audience while retaining a supernatural
night-time identity.

The implementation may use licensed asset families, generated assets, original
assets, or a deliberate combination after runtime comparison. Source choice is
an implementation decision rather than part of the product identity. Whatever
the source, the final world, actors, props, VFX, and UI must read as one authored
visual language rather than a catalogue of unrelated packs.

Final accepted captures cannot contain visible primitive stand-ins, debug
materials, magenta/checkerboard failures, disconnected kit pieces, placeholder
fonts, floating props, or large empty ground planes presented as finished art.
Imported actors need coherent scale, pivots, materials, collision, and animation
under the real camera and lighting.

The following effect-imagination image is a composition and quality target for
the authored-world and release phases. It is not a runtime asset, exact layout
blueprint, or permission to copy another game's trade dress. Planner should use
it to preserve the high-angle playable framing, coherent cemetery density,
warm-versus-cool lighting hierarchy, readable enemy silhouettes, clear escape
lanes, restrained effects, and compact authored HUD. Developer should compare
current runtime captures against those properties; Tester should judge the same
properties from ordinary play and representative dense-wave evidence.

![Mournlight gameplay effect-imagination reference](visual-references/mournlight-gameplay-imagination.png)

## 10. Animation, VFX, lighting, and audio

- Player and enemy characters expose readable idle, locomotion, attack/cast,
  hurt, and death motion; the player additionally exposes dash and victory.
- Actual planar velocity drives locomotion. Whole-model spinning, bouncing,
  tinting, or translation of one static pose is not sufficient animation.
- Warden Lantern, Gravespade, Wandering Wisps, each enemy attack, pickup,
  level-up, dash, hurt, death, boss phase, victory, and failure have distinct
  causal feedback.
- A moonlit sky, soft ambient fill, warm player lantern, landmark accents,
  restrained fog, ground contact cues, and limited shadows preserve depth and
  silhouettes. Dynamic lights and emission are budgeted for dense play.
- Music covers title, normal waves, boss escalation, and result with clean
  transitions. Audio covers UI, footsteps, dash, every weapon family, enemy
  warnings, impacts, player hurt, pickups, upgrade selection, boss phases,
  death, and victory.
- Repeated hit sounds use variation and voice limits. Boss warnings, player
  damage, upgrade selection, and results remain audible during peak density.

## 11. HUD, screens, and accessibility

Required screens and states:

- Title: Play, Settings, Credits & Notices, Quit.
- Gameplay HUD: health, experience, level, wave/run progress, equipped weapons
  and ranks, dash readiness, and contextual boss health.
- Level-up: three cards with mouse, keyboard, and gamepad focus states.
- Pause: Resume, Settings, Restart Run, Return to Title, Quit.
- Result: victory/failure, summary statistics, build summary, Retry, Title.

The HUD must leave the central arena readable and avoid tiny debug-like text.
Full-screen pages use an authored panel, background treatment, focus hierarchy,
hover/pressed/disabled states, and consistent iconography rather than flat
default controls.

The presentation language is bespoke to Mournlight: warm lantern-glass health
and dash motifs, moon-silver run progress, carved-stone or brass dividers, and
illustrated weapon and upgrade icons. Gameplay HUD elements should be compact,
transparent or unframed wherever legibility permits. Full-screen pages may use
treated surfaces, but they must compose the whole viewport instead of leaving a
small menu in one corner. Reject default Godot fonts, generic rounded web cards,
large opaque blue or purple blocks, repeated bordered rectangles, debug labels,
slash-heavy headings, and text-only information piles. Upgrade choices remain
card-shaped because they are a gameplay object, but each card needs authored
iconography, hierarchy, focus motion, and concrete before-to-after values rather
than a title and paragraph inside a generic panel.

Settings persist across restart and include master/music/effects volumes,
window mode, UI scale, screen shake, hit flash intensity, damage numbers,
high-contrast danger cues, and automatic-only versus directional target bias.
Color is never the sole indicator of player damage, hostile danger, upgrade
focus, rarity, boss warning, or result.

## 12. Architecture boundary

The product uses composable Godot scenes and data resources. At minimum,
separate these responsibilities:

- player intent, motor, visuals, health, dash, targeting, and weapon inventory;
- camera rig and camera configuration;
- enemy intent/steering, motor, attack, health, drop, and presentation;
- run/wave director, spawn validation, experience/level flow, upgrade drafting,
  pause ownership, results, audio, and saveable settings;
- weapon definitions and runtime attack strategies; and
- pool lifecycle for high-churn enemies, projectiles, pickups, impacts, and
  floating labels where used.

Player intent, the `CharacterBody3D` motor, visual facing, and the decoupled
camera must communicate through explicit interfaces. Player and enemy intent
may share a narrow movement/action contract, but neither the player motor nor
the camera may depend directly on one concrete input device or demo scene.

Enemy swarms need not instantiate the full player controller architecture.
Reuse intent and motor contracts where this improves correctness, while using
batched, staggered, pooled, or simplified steering appropriate to dense crowds.

Authoritative systems expose stable snapshots or signals for testing; UI and
effects do not own gameplay truth. Restart disposes or resets every active and
pooled entity, timer, signal, seed, pause reason, and result flag.

## 13. Delivery phases and regression policy

Development grows one continuous game rather than replacing disconnected demos.
The phase boundary controls what should be introduced next; it does not require
every non-fatal defect from an earlier phase to disappear before later work can
begin. A defect blocks progression only when it breaks the playable foundation,
corrupts authoritative state, prevents reliable testing, or would make later
work unsafe. Unresolved issues remain visible and continue to receive bounded
retests while each phase also delivers new player-facing capability.

| Phase | Required player-visible outcome |
|---|---|
| `survival_foundation` | A deliberately simple but truthful playable slice: title-to-game transition, high-angle camera, movement, dash, one automatic lantern attack, one enemy with telegraph/damage/death/drop, wisp collection, one real upgrade choice, player failure, and clean retry. Collision and state are real; primitive or temporary presentation is acceptable. Do not spend the first few loops importing the complete cemetery, final character family, full HUD, or cinematic effects. |
| `build_wave_expansion` | The continuous slice expands to all three weapon identities, four ordinary enemy roles, five wave states, at least 12 upgrades, pause/settings truth, and the Bellkeeper's mechanically complete two-phase encounter. Temporary visuals may remain, but every feature has authoritative state and observable causal feedback. |
| `authored_world_presentation` | Replace visible stand-ins with one coherent cemetery/character family; establish final camera composition, moonlight and lantern lighting, authored animation bindings, bounded VFX/audio layers, production HUD, upgrade presentation, title/pause/result layouts, and landmark identity. Adopt reusable sources as candidate-owned, license-complete units and preserve their working behavior unless evidence justifies a narrow change. |
| `release_convergence` | Complete the seven-to-ten-minute run at representative density; tune pacing and build variety, qualify 1920x1080 performance, accessibility and input paths, verify repeated retry/replay, remove placeholders and debug presentation, complete credits/provenance, and close or explicitly disposition all release-relevant issues. |

Once behavior, transforms, animation bindings, lighting, audio timing, or UI
layout has passed candidate-bound runtime review, it becomes a regression
baseline. Later work must preserve it or provide matched before/after evidence
for an intentional change. Replacing a working imported component with an
approximation, silently changing its authored parameters, or fixing one state
while breaking restart, pause, another input device, or dense-wave behavior
fails acceptance.

## 14. Performance and stability

The target is a stable 60 FPS presentation at 1920×1080 on the designated demo
machine during the representative final-wave scenario. Acceptance uses frame-
time distribution and visible play, not an empty-arena average. No single hard
hardware promise is made until the demo machine is recorded in the quality
contract.

The final-wave profile includes the representative enemy range, three weapon
families, pickups, UI, animation, VFX, lights, and boss behavior. Targeting,
steering, navigation, projectiles, particles, dynamic lights, audio voices,
and physics queries are explicitly bounded. Repeated Retry cycles must not
increase live nodes, signal callbacks, memory without bound, duplicated audio,
or input actions.

The game must import and launch without fatal Godot or GDScript errors. Normal
play cannot produce recurring error spam, invalid freed-instance access, NaN
movement, targets outside the tree, stuck pause state, or a result transition
that fires more than once.

## 15. Evidence-visible Definition of Done

The demo is complete only when candidate-bound runtime evidence shows:

1. boot, title navigation, settings, and transition into gameplay;
2. ordinary movement, automatic target acquisition, attack, hit, enemy death,
   drop, collection, level-up draft, selected upgrade, and visibly changed
   combat behavior;
3. player damage, invulnerability feedback, dash escape, death, result, and a
   clean retry;
4. all three weapon identities and all four ordinary enemy archetypes;
5. wave composition escalation and a representative final-wave performance
   trace at real visual density;
6. the Bellkeeper's telegraph, two phases, defeat, victory, result, and replay;
7. coherent final art from normal camera views of each landmark and from dense
   combat, with no visible placeholder content; and
8. Credits & Notices plus a provenance manifest for every external runtime
   asset or adapted code source.

Short feedback events use pre-action, onset, impact, and recovery frames or
equivalent video segments. Deterministic preparation may select a seed, legal
build, wave, position, or health precondition, but ordinary player input and
real gameplay systems must cause the observed action and outcome.

## 16. Public release boundary

The public repository contains everything required to build and play the demo,
apart from the documented Godot/toolchain installation. Credits & Notices makes
the authorship and licenses of externally sourced runtime content inspectable.
The release contains no private scaffold code, private-pool dependency,
provider credential, machine-specific absolute path, or reference-only media.

The research run may use engines, tools, web search, references, reusable
components, and licensed assets under the selected domain policy. Those inputs
do not change the observable product requirements in this PRD. Research claims
must describe that task boundary accurately rather than equating `from scratch`
with zero permitted external inputs.

## 17. Out of scope

- Multiplayer, online services, accounts, telemetry upload, or live operations.
- Persistent meta-progression, unlock trees, shops, inventory grids, crafting,
  quests, procedural world generation, or multiple arenas.
- FPS/TPS camera modes, ADS, reload simulation, manually fired gunplay, cover
  systems, or first-person viewmodels.
- More than one playable character, character selection, pets, companions, or
  local co-op.
- Mobile/touch release, consoles, localization beyond an English-complete demo,
  or a commercial content volume.
- Copying another game's names, characters, UI, sounds, levels, art, exact
  balance, or other protected product identity.

These exclusions protect the quality of the bounded public demo. They do not
prohibit later experiments from defining a new PRD and quality contract.
