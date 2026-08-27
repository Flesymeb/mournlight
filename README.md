# GameLoop Development Record

<!-- GameLoop generated development record; do not edit. -->

**Product:** `mournlight`  
**Workflow:** Project Planner → Developer → QA Tester

This README records high-level autonomous development and QA history.

---

## Publication scope

This product history records iteration goals and QA outcomes. Detailed tool, cache, receipt, and staging provenance remains in the private GameLoop Runtime audit.

---

## Persistent issue ledger

| Field | Value |
| --- | --- |
| Open | 12 |
| Closed | 6 |
| All | 18 |

---

## Loop 05

> A host-derived record of one Planner → Developer → QA Tester cycle.

| Candidate | Base | Current state |
| --- | --- | --- |
| `loop-05-29cbe359529e` | `warm_start:loop-04-29cbe359529e` | PLANNED |

### Project Planner

| Field | Value |
| --- | --- |
| Status | PLANNED |
| Focus | phase / release_convergence |
| Objective | Deliver a release-testable Mournlight run with authoritative five-wave and Bellkeeper behavior, truthful authored animation and semantic audio, and package-safe cemetery presentation that remains readable and stable at representative density, while preserving the native Godot boot, current combat identities, UI hierarchy, and intact authored cemetery source. |
| Strategy | `release_convergence.owner_truth_and_package_binding` |
| Tasks | 3 |

### Developer

| Field | Value |
| --- | --- |
| Status | NOT STARTED |

### QA Tester

| Field | Value |
| --- | --- |
| Status | UNTESTED |

---

## Loop 04

> A host-derived record of one Planner → Developer → QA Tester cycle.

| Candidate | Base | Current state |
| --- | --- | --- |
| `loop-04-29cbe359529e` | `development_snapshot:attempt-36875ab177feb20202f99b31` | BLOCKED |

### Project Planner

| Field | Value |
| --- | --- |
| Status | PLANNED |
| Focus | phase / release_convergence |
| Objective | Complete the release shell and semantic presentation, then extend the preserved authoritative foundation into a five-wave upgrade-and-Bellkeeper run without regressing combat, pause, pooling, retry isolation, or the intact cemetery. |
| Strategy | `release_vertical_completion` |
| Tasks | 3 |

### Developer

| Field | Value |
| --- | --- |
| Status | PASS |
| Summary | Implementation details are retained in the private GameLoop Runtime audit. |
| Completed tasks | 1 |
| Changed paths | 266 |
| Blocker | See the QA outcome below. |
| Attempt | `attempt-36875ab177feb20202f99b31` |

### QA Tester

| Field | Value |
| --- | --- |
| Status | FAIL |
| Candidate | `loop-04-29cbe359529e` |
| Product completion | IN PROGRESS |
| Review scope | `phase` |
| Findings | 9 (8 blocking focus items) |

### Evidence / QA findings

| ID | Severity | Summary |
| --- | --- | --- |
| `mournlight.animation.semantic_binding_missing` | MAJOR | All Warden semantic states still reuse one unrelated imported clip |
| `mournlight.audio.semantic_layer_missing` | MAJOR | Audio remains a small set of reused firearm samples rather than a complete semantic layer |
| `mournlight.ui.pause_actions_missing` | MAJOR | Pause Settings is visible but inert for keyboard and gamepad activation |
| `mournlight.ui.credits_overlap` | MINOR | Credits provenance copy overlaps the Back control |
| `mournlight.upgrades.untruthful_cards` | MAJOR | Upgrade cards are iconless, vague and numerically untruthful |
| `mournlight.wave_director.live_cap_exceeded` | MAJOR | Bellkeeper wave can exceed its configured ordinary-enemy cap |
| `mournlight.presentation.primitive_scaffolding` | MAJOR | World composition and dense combat remain materially below the release visual target |
| `mournlight.lifecycle.title_boss_leak` | MAJOR | Bellkeeper survives into Title after a failed boss run |
| `mournlight.camera.player_occlusion` | MAJOR | Camera offset survives replay and leaves the new run half outside the arena |

---

## Loop 03

> A host-derived record of one Planner → Developer → QA Tester cycle.

| Candidate | Base | Current state |
| --- | --- | --- |
| `loop-03-c2d0ac0293d4` | `development_snapshot:attempt-beaf0b584ecb8dd752da928f` | BLOCKED |

### Project Planner

| Field | Value |
| --- | --- |
| Status | PLANNED |
| Focus | phase / authored_world_presentation |
| Objective | Convert the preserved authored cemetery and combat foundation into a readable, populated, restartable survivor run, and replace the prototype gameplay overlay with a compact Mournlight HUD, while preserving the verified motor, dash, automatic-combat, weapon-build, package-integrity, and Godot boot baselines. |
| Strategy | `authoritative_world_session_plus_state_bound_hud` |
| Tasks | 2 |

### Developer

| Field | Value |
| --- | --- |
| Status | NEEDS VISUAL QA |
| Summary | Implementation details are retained in the private GameLoop Runtime audit. |
| Completed tasks | 2 |
| Changed paths | 50 |
| Blocker | See the QA outcome below. |
| Attempt | `attempt-beaf0b584ecb8dd752da928f` |

### QA Tester

| Field | Value |
| --- | --- |
| Status | FAIL |
| Candidate | `loop-03-c2d0ac0293d4` |
| Product completion | IN PROGRESS |
| Review scope | `phase` |
| Findings | 10 (9 blocking focus items) |

### Evidence / QA findings

| ID | Severity | Summary |
| --- | --- | --- |
| `mournlight.ui.title_actions_missing` | MAJOR | Title screen omits Settings, Credits and Quit |
| `mournlight.ui.pause_actions_missing` | MAJOR | Pause screen omits Settings, Restart Run and Quit |
| `mournlight.ui.result_summary_incomplete` | MINOR | Result omits damage dealt and build summary |
| `mournlight.camera.player_occlusion` | MAJOR | Northeast camera guard still destroys authored framing and useful player context |
| `mournlight.presentation.primitive_scaffolding` | MAJOR | Authored cemetery remains unreadable at player scale and unbounded at the northeast route |
| `mournlight.enemies.shared_static_presentation` | MAJOR | Four enemy roles share one static spinning presentation |
| `mournlight.hud.missing_run_state` | MAJOR | HUD state is now authoritative but visible typography still uses the fallback font |
| `mournlight.wave_director.boss_missing` | MAJOR | Five-wave director and Bellkeeper boss are absent |
| `mournlight.animation.semantic_binding_missing` | MAJOR | Warden still uses arbitrary fallback clips and procedural deformation instead of semantic animation |
| `mournlight.audio.semantic_layer_missing` | MAJOR | Semantic audio layer is absent beyond a generated lantern tone |

---

## Loop 02

> A host-derived record of one Planner → Developer → QA Tester cycle.

| Candidate | Base | Current state |
| --- | --- | --- |
| `loop-02-2be92fe6d572` | `development_snapshot:attempt-1283444ea616f9c3cfc298e2` | BLOCKED |

### Project Planner

| Field | Value |
| --- | --- |
| Status | PLANNED |
| Focus | phase / build_wave_expansion |
| Objective | Deliver a production-presented, spatially reliable cemetery combat slice that preserves the verified movement, dash, input, pause, palette, landmark, and high-angle-camera foundations while adding an inspectable automatic Lantern chain and three genuinely distinct data-driven weapon identities. |
| Strategy | `authored_spatial_slice_then_combat_core_then_weapon_strategies` |
| Tasks | 3 |

### Developer

| Field | Value |
| --- | --- |
| Status | PASS |
| Summary | Implementation details are retained in the private GameLoop Runtime audit. |
| Completed tasks | 2 |
| Changed paths | 46 |
| Blocker | See the QA outcome below. |
| Attempt | `attempt-1283444ea616f9c3cfc298e2` |

### QA Tester

| Field | Value |
| --- | --- |
| Status | FAIL |
| Candidate | `loop-02-2be92fe6d572` |
| Product completion | IN PROGRESS |
| Review scope | `phase` |
| Findings | 5 (4 blocking focus items) |

### Evidence / QA findings

| ID | Severity | Summary |
| --- | --- | --- |
| `mournlight.camera.player_occlusion` | MAJOR | Northeast traversal still removes the Warden from the gameplay frame |
| `mournlight.presentation.primitive_scaffolding` | MAJOR | Authored replacement remains underexposed and unusably framed |
| `mournlight.hud.missing_run_state` | MAJOR | HUD omits authoritative run fields and ships generic system-font panels |
| `mournlight.run.lifecycle_missing` | MAJOR | Configured build has no title, failure, result or retry lifecycle |
| `mournlight.animation.semantic_binding_missing` | MINOR | Adjacent authored-world Warden animation binding is arbitrary |

---

## Loop 01

> A host-derived record of one Planner → Developer → QA Tester cycle.

| Candidate | Base | Current state |
| --- | --- | --- |
| `loop-01-5241562877de` | `development_snapshot:attempt-587dfd4602780bd3f0c8c4a5` | BLOCKED |

### Project Planner

| Field | Value |
| --- | --- |
| Status | PLANNED |
| Focus | phase / survival_foundation |
| Objective | Replace the bootstrap with a playable survival-foundation movement slice whose keyboard and gamepad controls drive a camera-relative CharacterBody3D motor, an explicit readable dash lifecycle, stable collision sliding, clean pause/resume, and a bounded high-angle arena camera without FPS/TPS drift. |
| Strategy | `survival_foundation.player_motor_camera_dash` |
| Tasks | 1 |

### Developer

| Field | Value |
| --- | --- |
| Status | PASS |
| Summary | Implementation details are retained in the private GameLoop Runtime audit. |
| Completed tasks | 0 |
| Changed paths | 17 |
| Blocker | See the QA outcome below. |
| Attempt | `attempt-587dfd4602780bd3f0c8c4a5` |

### QA Tester

| Field | Value |
| --- | --- |
| Status | FAIL |
| Candidate | `loop-01-5241562877de` |
| Product completion | IN PROGRESS |
| Review scope | `phase` |
| Findings | 5 (5 blocking focus items) |

### Evidence / QA findings

| ID | Severity | Summary |
| --- | --- | --- |
| `mournlight.camera.player_occlusion` | MAJOR | A reachable corner tree fully hides the player from the gameplay camera |
| `mournlight.player.vertical_drift` | MAJOR | Obstacle contact moves the planar Warden root upward and leaves it elevated |
| `mournlight.presentation.primitive_scaffolding` | MAJOR | The shipped active arena is engine-primitive presentation scaffolding |
| `mournlight.combat.missing_automatic_chain` | MAJOR | The required automatic combat causal chain is absent |
| `mournlight.enemies.missing_spawn_roles` | MAJOR | No active enemy spawn, motion, attack, death, drop, or pooling lifecycle exists |

---

## Current pointers

- Latest candidate: `loop-05-29cbe359529e`
- Accepted candidate: `none`
- Latest attempted: `loop-05-29cbe359529e`
- Latest warm start: `loop-05-29cbe359529e`
- Last published: `loop-04-29cbe359529e`
- Best verified: `loop-04-29cbe359529e`
- Generated by the GameLoop host from immutable run evidence.
