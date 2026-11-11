# Spellcraft System — Phased Implementation Plan

> **Purpose:** Give a local coding agent clear, small, verifiable tasks for expanding the existing spellcraft system in the current 2D roguelite.
>
> **Important scope rule:** Complete the core phases first. **Do not implement Beam, Trap, or Chain unless you stop and explicitly ask the user for approval at the optional-shapes checkpoint.** These shapes are intentionally outside the required scope because the project may be close to its deadline.

---

## 0. Instructions for the coding agent

The agent working from this document may have limited reasoning ability. Follow these rules literally.

1. Work on **one phase at a time**. Do not start the next phase until the current phase's checks pass.
2. Before changing code, inspect the relevant files and find the existing implementation. Do not assume that a system described here is already present in the game.
3. Make small changes. Do not rewrite unrelated systems, rename existing public fields, reorganize the project, change the UI style, or add dependencies unless a phase specifically requires it.
4. Preserve existing behavior unless this plan explicitly changes it.
5. Do not invent new elements, compounds, shapes, statuses, relics, or mechanics outside the listed scope.
6. Reuse the project's current damage, status, collision, particle, animation, room, enemy, pickup, and UI systems wherever possible. Do not create a second system that does the same job.
7. If a required system does not exist, inspect the surrounding code and implement the smallest compatible solution. Explain the missing system in the phase report.
8. Never silently ignore an error. Fix it or stop and report the exact file, function, error, and what is blocking progress.
9. Do not delete existing assets or replace existing animations with placeholders.
10. After each phase, report:
    - Files changed.
    - What was implemented.
    - Tests/checks performed and their results.
    - Known limitations or decisions that need the user's input.
11. Do not claim a feature is complete merely because the game compiles. Test it in-game or with an appropriate automated test.
12. Do not change the game's deadline or add optional work to the required phases.

### Before starting

- Make a Git commit or create a backup branch before editing.
- Read the project's current instructions, README, and relevant source files.
- Run the game once before making changes and record whether it works.
- Locate the spell-casting flow from input to spell creation, projectile/area behavior, damage, status application, and visual effects.
- Locate any existing tests and use their current conventions.

If the repository differs from the two files supplied with this plan, do not force the code to match this document. Preserve the actual project architecture and report the difference.

---

## 1. Current system — confirmed starting point

The plan is based on the supplied `src/core/data.lua` and `src/core/skillgen.lua` files. The agent must inspect the current repository versions before editing.

### Elements

There are currently **four** elements:

- `fire`
- `water`
- `wind`
- `earth`

Do not add a fifth element in this plan.

### Compounds

There are currently ten unordered element pairs:

| Elements | Compound | Base power | Statuses |
|---|---|---:|---|
| Fire + Fire | Inferno | 14 | `burn` |
| Water + Water | Tide | 6 | `pull`, `slow` |
| Wind + Wind | Gale | 8 | `push` |
| Earth + Earth | Quake | 12 | `stun` |
| Fire + Water | Steam | 7 | `push`, `blind` |
| Fire + Wind | Ember | 8 | `burn`, `spread` |
| Earth + Fire | Magma | 9 | `burn`, `slow` |
| Water + Wind | Mist | 3 | `blind`, `hide_self` |
| Earth + Water | Mud | 4 | `root` |
| Earth + Wind | Dust | 5 | `confuse` |

Do not rebalance these numbers or rename these compounds unless a later test proves a concrete bug and the user approves the change.

### Existing shapes

The current shape keys are part of the existing code interface. Keep these exact keys:

| Key | Display name | Cooldown | Radius | Duration |
|---|---|---:|---:|---:|
| `projectile` | Bolt | 0.6 | 10 | 0 |
| `puddle` | Pool | 4.0 | 60 | 5 |
| `orbit` | Orbit | 5.0 | 14 | 6 |
| `cone` | Spray | 1.5 | 90 | 0.3 |
| `burst` | Nova | 2.5 | 70 | 0 |

Do not rename `puddle`, `cone`, or `burst` to match their display names. Other code may depend on these keys.

### Existing quirks

The supplied data file contains five quirk strings:

1. `splits in two`
2. `leaves a trail`
3. `repeats once`
4. `bigger but slower`
5. `costs 5% health`

The current generator:

- Sorts the two element names alphabetically.
- Creates a recipe key using `playerName .. elementA .. "+" .. elementB .. "|" .. shape`.
- Seeds the project's deterministic RNG from that key.
- Uses the first random result for a power variation of approximately ±10%.
- Uses the second random result to choose one of the five quirks.
- Averages the two element colors.
- Returns the compound, shape, power, quirk, color, cooldown, radius, duration, and compound statuses.

**Preserve this deterministic behavior.** In particular, do not change the recipe key format, the order of RNG calls, or the existing quirk ordering without explicit approval. The same player name and recipe should continue to generate the same current power and quirk.

### Current size

There are ten compounds and five shapes, so there are **50 base recipe/shape combinations**. Quirks add variation to these combinations. This is enough content for the core scope; do not increase the number of elements or shapes in the required phases.

---

## 2. Overall target

Improve the existing spell system in this order:

1. Make the existing quirks real, testable gameplay effects.
2. Make compound statuses work consistently with all five existing shapes.
3. Add a small number of interactions between active spell effects and areas.
4. Add a small, data-driven relic system that changes a run's spell build.
5. Balance, test, and document the completed core system.
6. **Only after all required work is complete, ask the user whether to add optional shapes: Beam, Trap, and Chain. Do not implement them without an explicit yes.**

### Non-goals

Do not do any of the following as part of this plan:

- Add a fifth element.
- Add more compounds.
- Add spell crafting slots, a complex rune tree, or a new crafting screen.
- Replace the current spell generator.
- Rebuild the combat, enemy, room, or inventory systems.
- Add multiplayer, networking, or online functionality.
- Add a large collection of relics.
- Add the optional Beam, Trap, or Chain shapes without approval.
- Rewrite the art or animation pipeline.

---

# Phase 0 — Repository audit and safe baseline

**Goal:** Understand how the current game executes a generated skill before changing it.

### Agent tasks

1. Find all references to:
   - `makeSkill`
   - `QUIRKS`
   - `statuses`
   - `shape_key`
   - `cooldown`, `radius`, and `duration`
2. Trace one spell from start to finish:
   - Player input requests a spell.
   - The skill generator creates the skill data.
   - The game selects the shape behavior.
   - The spell creates its projectile, area, orbit, cone, or burst.
   - Collision or overlap is detected.
   - Damage and statuses are applied.
   - Visual and audio effects are played.
3. Find how player health is stored and modified. Identify the authoritative function used to damage/heal the player.
4. Find how enemy statuses are stored, applied, timed, and removed.
5. Find how spell cooldowns and active spell durations are tracked.
6. Find the existing pickup/reward flow, if any, that could support relics.
7. Identify the existing particle and animation assets that can be reused.
8. Run the game and record the baseline result.

### Rules

- Do not implement features in this phase.
- Do not make broad refactors.
- If the agent cannot locate a system, report that instead of inventing a replacement immediately.

### Completion checks

- [ ] The agent can identify the code path for all five existing shapes.
- [ ] The agent can identify where each compound status is applied.
- [ ] The agent can identify how player health is changed.
- [ ] The agent can identify how a generated quirk is consumed by the runtime.
- [ ] The game still runs with no behavior changes.
- [ ] The agent provides a short architecture map with file names and relevant functions.

**Stop after this phase and report the findings.**

---

# Phase 1 — Turn the five existing quirks into real gameplay effects

**Goal:** Make each currently generated quirk affect gameplay. Do not add new quirks.

## 1.1 Keep generation compatible

1. Keep the `M.QUIRKS` list in the same order.
2. Keep the current recipe key format.
3. Keep the same deterministic RNG calls and their order.
4. Keep the current `skill.quirk` field so existing code continues to work.
5. If structured quirk data is useful, add a separate lookup table keyed by stable IDs. Do not replace the ordered list with an unordered map.
6. Add a stable `quirk_id` field to generated skills only if it does not break existing consumers.

Suggested IDs:

| Existing quirk text | Stable ID |
|---|---|
| splits in two | `split_in_two` |
| leaves a trail | `leaves_trail` |
| repeats once | `repeat_once` |
| bigger but slower | `bigger_slower` |
| costs 5% health | `health_cost` |

Do not store executable Lua functions inside the static data table. Store simple values and let the spell runtime execute the behavior.

## 1.2 Implement the quirks

Implement each quirk in the existing spell execution flow. Reuse the existing shape code. Do not create five separate spell systems.

### A. Splits in Two

- The spell creates two effect instances instead of one.
- Keep the two instances close to the original direction/position, with a small angle or position offset so they are visibly separate.
- Reduce the strength of each instance so the total effect is not automatically twice as powerful. Start with each instance doing 60% of the original spell's damage/effect strength; make the value a named tuning constant.
- Apply the same compound statuses to each instance, but avoid applying duplicate status stacks to the same enemy from both instances in the same brief hit window.
- For a Puddle, create two smaller nearby pools rather than two full-size pools.
- For Orbit, split the orbiting particles into two visibly separate groups or two small orbital paths. Do not create twice the normal total damage without compensation.
- For Cone and Burst, create two smaller/offset effect areas. Keep them readable and prevent the player from receiving duplicate hit effects.

### B. Leaves a Trail

- The spell leaves a short-lived secondary effect behind its path or cast area.
- Use existing particle/area assets where possible.
- Projectile: leave a short trail behind the moving projectile.
- Puddle: leave a few small fading patches around/away from the original pool, not an endless stream.
- Orbit: leave a faint short-lived trace along the orbit path.
- Cone: leave a brief residual effect in the cone area.
- Burst: leave a short-lived residual area after the initial burst.
- Trail effects must expire and clean themselves up. They must not create more trails recursively.

### C. Repeats Once

- Execute the same spell a second time after a short delay. Start with a named delay of `0.25` seconds.
- The second execution uses the original cast's direction/target/position, not the player's new position or aim.
- Do not let the repeated execution trigger another repeat. Add an internal flag such as `is_repeat = true`.
- For a sustained shape such as Orbit, do not create an unlimited or permanent orbit. The second activation must have a defined duration and cleanup.

### D. Bigger but Slower

- Increase the spell's effective size by 30% as a starting tuning value.
- Reduce its delivery/cast speed by 20% as a starting tuning value.
- Apply the modifier consistently to all five existing shapes. For shapes without movement speed, increase the time to complete their activation or expansion instead.
- Do not reduce the player's movement speed.
- Put the percentages in named tuning constants so they can be balanced centrally.

### E. Costs 5% Health

- Treat this as a Blood Magic cost paid when the spell is successfully cast.
- Deduct 5% of the player's maximum health per cast.
- Do not let the cost reduce player health below 1 HP.
- If the player cannot pay while keeping at least 1 HP, the spell must not cast; show/use the game's existing failure feedback if one exists.
- Do not charge health when a cast is rejected, on cooldown, or otherwise fails before the spell is created.
- Do not charge health again for a repeated effect or for a split projectile/puddle. It is one cost per player cast.
- Use the game's authoritative health function. Do not directly edit a UI health value.

### 1.3 Prevent common bugs

- Effects must be destroyed when their duration ends or their owner/room is removed.
- A quirk must not accidentally trigger itself recursively.
- A single enemy must not receive many duplicate hits merely because one effect has multiple visual particles.
- If a room resets or the player dies, active trail/repeat effects must be cleaned up safely.
- Do not allow a health-cost spell to repeatedly cast for free because its health payment callback was skipped.

### Completion checks

- [ ] All five quirks produce visible and gameplay effects.
- [ ] Each quirk works with all five existing shapes, or the agent documents a concrete engine limitation and implements a consistent fallback.
- [ ] The same recipe still produces the same quirk and power as before.
- [ ] Health is charged once per successful cast for `costs 5% health`.
- [ ] Repeat and split effects cannot recursively multiply.
- [ ] Temporary effects clean up after their duration.
- [ ] The game runs without errors.

**Stop after this phase and report results. Do not begin Phase 2 until these checks pass.**

---

# Phase 2 — Make compound statuses work consistently with the five existing shapes

**Goal:** Make the compound define *what happens* and the shape define *how it reaches enemies*. Do not add new compounds or statuses.

## 2.1 Preserve the compound data

Use the current `M.COMPOUNDS` table and its existing `statuses` arrays. Do not change the ten compound names, base power values, or status names in this phase.

## 2.2 Use one consistent status application path

1. Find the existing status application function.
2. Ensure every shape sends successful enemy hits through that same function.
3. Pass the generated skill's `statuses` list into the function.
4. Do not create different copies of `burn`, `slow`, `push`, `pull`, `stun`, `blind`, `root`, `confuse`, `spread`, or `hide_self` logic for each shape.
5. Keep the current duration/strength rules if they already exist. If a status is not implemented, report it and implement only the smallest behavior needed for its existing definition.
6. Make sure status effects have sensible refresh/stack rules. Repeated hits should not create an unlimited number of duplicate timers or status objects.

## 2.3 Apply statuses by shape

Use these behavior rules as the target:

| Shape | How it delivers the compound status |
|---|---|
| Projectile | Apply the compound statuses to enemies hit by the projectile. |
| Puddle | Apply or refresh statuses to enemies standing inside the pool at the existing tick interval. Stop applying when they leave. |
| Orbit | Apply statuses when an orbiting particle actually contacts an enemy. Visual proximity alone is not a hit. |
| Cone | Apply statuses to enemies caught inside the cone during its active window. Prevent repeated frame-by-frame applications from becoming unlimited status stacks. |
| Burst | Apply statuses to enemies inside the burst radius when the burst occurs. |

## 2.4 Validate the compounds

Use these examples as expected behavior:

- **Inferno + Projectile:** projectile hit applies Burn.
- **Tide + Puddle:** enemies inside the pool are slowed and pulled according to the current pull implementation.
- **Gale + Cone:** enemies caught in the cone are pushed.
- **Quake + Burst:** enemies inside the burst are stunned.
- **Steam + Projectile:** hit applies Push and Blind.
- **Ember + Puddle:** the area applies Burn and uses the existing Spread behavior if that behavior is already supported.
- **Magma + Burst:** enemies hit are burned and slowed.
- **Mist + Orbit:** contact applies Blind and the existing Hide Self behavior, if that status is intended for the caster rather than enemies, must remain on the correct target.
- **Mud + Puddle:** enemies in the pool are rooted.
- **Dust + Cone:** enemies caught in the cone are confused.

Important: `hide_self` may target the caster rather than an enemy. Inspect the current game behavior and preserve the intended target. Do not blindly apply every status to enemies.

### Completion checks

- [ ] Every existing compound's statuses work through Projectile.
- [ ] Every existing compound's statuses work through Puddle.
- [ ] Every existing compound's statuses work through Orbit.
- [ ] Every existing compound's statuses work through Cone.
- [ ] Every existing compound's statuses work through Burst.
- [ ] Repeated collision/tick checks do not create unlimited status stacks or timers.
- [ ] Caster-targeted effects such as `hide_self` affect the correct target.
- [ ] No status name in `data.lua` was silently removed or renamed.

**Stop after this phase and report results.**

---

# Phase 3 — Add a small set of environmental spell interactions

**Goal:** Let selected active spell areas interact during combat. Start with only the three interactions below. This is not a general-purpose simulation or physics system.

## 3.1 Audit active area effects

Before coding, identify how the game represents active puddles, lingering trails, burst remnants, or other persistent spell areas. Use the existing area representation if possible.

If the game does not have a reusable active-area representation, create the smallest one needed for these interactions. Do not rewrite all spell shapes.

Each active area should expose only the information required for interaction checks, for example:

- owner/caster
- source compound or element pair
- position and radius
- remaining duration
- whether it has already been transformed or spread

## 3.2 Implement only these interactions

### Interaction A — Fire + Mud: Burning Mud

- If a Fire-containing spell effect overlaps an active Mud Puddle, transform that Mud Puddle into Burning Mud.
- Burning Mud keeps the Mud pool's area identity and can keep its existing root behavior.
- It also applies a small Burn effect to enemies inside it.
- Use a short, named transformation duration; start with 3 seconds.
- The same pool must not repeatedly transform and refresh itself every frame.
- Use an existing fire/ground visual if available.

### Interaction B — Wind + lingering Fire: Spread the Fire

- If a Wind-containing spell affects an active lingering Fire/Magma/Ember area, spread that area once to one nearby location in the wind direction.
- The new area must be weaker or shorter-lived than the original. Start with 60% of the original remaining duration and damage strength.
- Mark the original area as already spread so it cannot spread endlessly.
- Do not spread through walls or outside the room bounds.
- Use existing fire particle effects; do not require new art.

### Interaction C — Steam + Dust: Dense Cloud

- If active Steam and Dust areas overlap, create a temporary Dense Cloud in the overlap area.
- Dense Cloud applies the existing Blind and Confuse effects to enemies inside it.
- Start with a 2-second duration.
- It must not create another Dense Cloud every frame while the two source areas remain overlapped. Add a cooldown/handled-pair marker and clean it up when the source areas disappear.
- Use existing mist/smoke particles if available.

## 3.3 Interaction safety rules

- Interaction checks should happen at a controlled update interval or when areas are created/updated, not by creating unbounded objects every frame.
- An interaction-created effect must not recursively trigger the same interaction unless explicitly stated above.
- Effects must respect room boundaries and be cleaned up on room reset, room clear, or player death.
- Keep the interaction list data-driven if that fits the existing architecture, but do not build a generic node/graph crafting framework.

### Completion checks

- [ ] Fire + Mud creates Burning Mud once.
- [ ] Wind + lingering Fire spreads the area no more than once per original area.
- [ ] Steam + Dust creates one Dense Cloud per valid overlap event.
- [ ] Interaction effects expire and clean up correctly.
- [ ] No infinite spread, duplicate cloud creation, or frame-by-frame object spawning occurs.
- [ ] The three interactions are readable in combat using existing visual assets.

**Stop after this phase and report results.**

---

# Phase 4 — Add a small relic system

**Goal:** Add a few run-level rewards that modify spells. Keep the system small and use the current pickup/reward UI if one exists.

## 4.1 Inspect before implementing

1. Find the existing item, pickup, chest, reward, or upgrade flow.
2. Reuse its UI and collection logic.
3. Do not create a new inventory screen if the game already has a suitable reward selection or pickup interface.
4. Relics should be passive effects. They are not new spell ingredients and do not change the recipe key.

If there is no reward infrastructure, implement only a minimal relic pickup/selection mechanism consistent with the existing game. Report this as a scope decision before adding a large UI.

## 4.2 Implement these four relics only

| Relic | Effect | Implementation notes |
|---|---|---|
| Inferno Heart | Fire-containing spells gain 15% power. | Check the generated skill's two elements. Do not affect non-Fire spells. |
| Echoing Crystal | Every fifth successful spell cast repeats once at 50% strength. | Count successful player casts only. The echo must not count as another cast or trigger itself. |
| Ancient Catalyst | Compound status durations increase by 20%. | Apply to status duration, not damage or cooldown. Do not allow permanent statuses. |
| Orbital Crown | Orbit spells gain one additional orbiting particle. | Apply only to the existing `orbit` shape. Keep collision/damage balanced so visual particles do not automatically multiply damage without a deliberate rule. |

Use stable relic IDs such as `inferno_heart`, `echoing_crystal`, `ancient_catalyst`, and `orbital_crown`.

## 4.3 General relic rules

- Relics must be stored as run/player state, not written into the static generated skill data in a way that permanently changes the recipe.
- Relic effects should be applied through a small, central modifier step when a skill is cast or when a status is applied.
- Collecting the same relic twice should follow one clear rule. For this first version, do not stack duplicate relics unless the current game already has a tested stacking convention. Prefer preventing duplicate ownership.
- The relic should be removed/reset at the correct run boundary if the game is run-based.
- Do not add rarity tiers, upgrade trees, rerolls, or dozens of relics.

### Completion checks

- [ ] Each of the four relics can be obtained through the existing reward/pickup flow.
- [ ] Inferno Heart affects only spells containing Fire.
- [ ] Echoing Crystal repeats every fifth successful cast, not every fifth frame or failed cast.
- [ ] Echoes do not recursively trigger Echoing Crystal.
- [ ] Ancient Catalyst affects statuses but not damage/cooldown.
- [ ] Orbital Crown affects Orbit only.
- [ ] Relic effects reset correctly between runs.
- [ ] Existing spell generation remains deterministic and unchanged by relic ownership.

**Stop after this phase and report results.**

---

# Phase 5 — Balance, regression testing, and deadline freeze

**Goal:** Make sure the expanded core system is fun, understandable, stable, and safe to deliver.

## 5.1 Test the existing combinations

Create a test checklist or small test script that generates all 50 combinations:

- 10 existing compounds.
- 5 existing shapes.

Check that every combination generates without errors and has the expected compound, shape key, color, power, cooldown, radius, duration, statuses, and quirk fields.

Do not manually hardcode 50 different skill implementations. The same reusable shape and status systems must handle them.

## 5.2 Test quirks and relics

- Test each of the five quirks with each of the five shapes: 25 quirk/shape cases.
- Test each of the four relic effects independently.
- Test Echoing Crystal together with `repeats once` and verify there is no infinite repeat chain.
- Test `costs 5% health` together with Echoing Crystal and verify health is paid only for the player's original cast, not the echo.
- Test split/trail/repeat effects when a room ends or the player dies.

## 5.3 Test environmental interactions

- Test each of the three interactions alone.
- Test the three interactions near room boundaries.
- Verify no interaction creates unlimited areas or clouds.
- Verify all temporary areas are destroyed when a room is cleared or unloaded.

## 5.4 Balance pass

Use the following only as starting tuning values, not as unquestionable final balance:

| Item | Starting value |
|---|---:|
| Split instance strength | 60% each |
| Repeat delay | 0.25 seconds |
| Bigger spell size | +30% |
| Bigger spell speed | -20% |
| Health quirk cost | 5% maximum HP, minimum 1 HP preserved |
| Burning Mud duration | 3 seconds |
| Spread area duration/strength | 60% of original remaining value |
| Dense Cloud duration | 2 seconds |
| Inferno Heart power | +15% |
| Echoing Crystal strength | 50% |
| Ancient Catalyst status duration | +20% |
| Orbital Crown | +1 orbit particle |

Make tuning values easy to adjust in the project's central data/tuning file. Avoid scattering magic numbers throughout gameplay code.

## 5.5 Performance and cleanup

- Check for leaked timers, collision objects, particles, and game objects.
- Check that repeated status ticks and active-area overlap checks do not create excessive work.
- Check behavior with many enemies and multiple active spell effects.
- Check that all effects are cleaned up on room transitions and run resets.
- Check that debug-only code remains controlled by the existing debug setting.

## Completion checks

- [ ] All 50 generated combinations run without errors.
- [ ] All five quirks pass their 25 shape checks.
- [ ] All four relics work and reset correctly.
- [ ] All three environmental interactions work and clean up correctly.
- [ ] No known infinite loops, duplicate cast chains, or unbounded object creation remain.
- [ ] The game launches and completes a room/run test.
- [ ] Existing UI, movement, enemy behavior, and room flow have not been broken.
- [ ] The agent writes a brief final implementation report and lists any known issues.

### Deadline freeze

Once Phase 5 passes, stop adding required features. Fix bugs only. Do not begin optional content automatically.

---

# Optional checkpoint — Ask before adding Beam, Trap, or Chain

**This section is optional and is not part of the required implementation.** The user likes these ideas but does not want scope creep. The core game may be close to its deadline.

After Phase 5 is complete and tested, ask the user this exact question (or a very close version):

> The core spell system is implemented and tested. Do you want to add the three optional shapes — Beam, Trap, and Chain — now, or should we keep the scope frozen for the deadline?

### Approval rule

- If the user explicitly says **yes**, make a separate estimate/mini-plan and implement only the shape(s) they approve.
- If the user says **no**, do not implement them.
- If the user does not answer, do not implement them.
- Do not interpret the user's earlier enthusiasm as approval.
- Do not start any optional shape before Phase 5 is complete.
- If the user approves only one or two shapes, implement only those shapes.

### If approved, use these definitions

| Optional shape | Intended behavior | Why it is different |
|---|---|---|
| Beam | A continuous line of magic that damages enemies while active. | Rewards aiming/tracking and sustained positioning. |
| Trap | A placed area that waits until an enemy enters, then activates. | Rewards planning and area denial. |
| Chain | A spell that jumps from one enemy to another nearby enemy. | Rewards targeting groups and managing jump range. |

Before implementing an approved shape:

1. Inspect the existing shape interface and follow its conventions.
2. Add one shape at a time.
3. Add its data entry and runtime behavior without changing the five original shape keys.
4. Make it work with all ten compounds through the existing shared status system.
5. Make existing quirks behave sensibly with it, or document a clear compatibility rule.
6. Add tests for that shape and check all ten compound combinations.
7. Stop and report before starting the next optional shape.

If the user has not approved an optional shape, this section is documentation only. **Do not add these entries to `M.SHAPES`.**

---

## Final handoff report format

At the end of the approved work, provide this report:

```text
SPELLCRAFT IMPLEMENTATION REPORT

Completed phases:
- Phase 0: PASS / NOT PASS
- Phase 1: PASS / NOT PASS
- Phase 2: PASS / NOT PASS
- Phase 3: PASS / NOT PASS
- Phase 4: PASS / NOT PASS
- Phase 5: PASS / NOT PASS

Files changed:
- [list files]

Features implemented:
- [list features]

Tests performed:
- [list tests and results]

Known issues:
- [list issues, or "None known"]

Optional shapes:
- Not implemented unless the user explicitly approved them.

Commit:
- [commit hash or "No commit created"]
```

**Final priority:** Deliver a stable, complete core system using the existing four elements, ten compounds, and five shapes. A smaller polished feature set is better than adding optional shapes and missing the deadline.
