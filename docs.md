# Defold — Agent Field Guide

Practical reference for reading and writing Defold projects.
**Target: Defold 1.14.x (stable).** If the project's `game.project` or the editor says otherwise, trust the editor.

**Workflow assumption:** a human opens the project in the Defold editor and runs it. You author and read files; you do not run `bob`, bundle, or launch the engine unless explicitly asked.

**Also read `AGENTS.md`** (mistakes already made in this project, with rules) and §13 (how to add art). Where this guide and `AGENTS.md` disagree, `AGENTS.md` wins: it records what the real editor did.

**Environment:** Windows. Every shell snippet below is PowerShell (Windows PowerShell 5.1 or PowerShell 7), and paths in them are Windows paths.

---

## 0. Read this first

1. **The editor is the compiler of record.** `.go`, `.collection`, `.gui`, `.atlas` and friends are protobuf *text* files. Malformed text usually compiles to something wrong or fails with an unhelpful message. When a format is uncertain, open the file in the editor rather than guessing.
2. **Prefer Lua.** ~90% of game logic belongs in `.script` / `.gui_script` / `.lua`. Resource files should change as little as possible.
3. **Never edit** `.internal/` or `build/`. Do not hand-edit `.png`, `.ttf`, `.ogg`, `.wav`.
4. **Verify before claiming done** — see [§8](#8-verifying-your-work).
5. **Don't invent APIs.** If a function is not in [§7](#7-api-quick-reference) and you are not sure, search the reference (§11) instead of writing something plausible.

---

## 1. Mental model

```
game.project                 # project settings; names the bootstrap collection
└── main.collection          # bootstrap collection loaded at startup
    ├── player.go            # instance of a game object prototype
    │   ├── player.script    # component (behaviour)
    │   └── player.sprite    # component (visual)
    └── level.collection     # sub-collection instance
        └── enemy.go
```

- **Collection** — a tree of game objects. A *file* is a prototype; putting it in another collection creates an *instance*.
- **Game object (`.go`)** — a container with `id`, position, rotation, scale. Has no behaviour of its own; it holds components.
- **Component** — script, sprite, label, collision object, factory, sound, tilemap, GUI, camera, particle fx, model, light, collection proxy/factory.
- **Prototype vs instance** — the `.go` file is the prototype; `instances { prototype: "/main/player.go" }` in a collection is an instance. Editing the prototype changes every instance.
- **At runtime there are no collections.** A collection is a compile-time structuring device only. Objects get absolute paths at load, and those paths are their permanent addresses.
- **No inheritance, no classes.** Share behaviour with Lua modules, or with helper game objects you talk to via messages.

The engine loads exactly one collection at startup: `[bootstrap] main_collection` in `game.project`.

---

## 2. Project layout

| Path | Meaning |
| --- | --- |
| `game.project` | INI-style project settings. Bootstrap collection, display size, physics, input binding, etc. |
| `input/game.input_binding` | Project-wide input map: device input → action name. |
| `main/main.collection` | Conventional bootstrap collection. |
| `assets/` | Images, atlases, fonts, sounds. |
| `.internal/` | Editor/runtime state (port, token, build metadata). **Read-only for you.** |
| `build/` | Generated. **Never edit.** |

### Two kinds of paths — do not mix them

| Kind | Style | Example |
| --- | --- | --- |
| Filesystem path (your shell, file tools) | Native Windows: backslashes, quote the spaces | `"D:\Projects\Github Projects\Defold Games\main\player.script"` |
| Resource path (inside any project file) | Forward slashes, leading `/`, relative to project root | `/main/player.script` |

Resource paths are **always** forward-slash on every OS. `component: "/main/player.script"` and `collection: "/levels/level1.collection"` never take backslashes, and a leading `/` is required. Only the filesystem side uses `\`.

### File types

| Ext | What it is | Safe to hand-edit? |
| --- | --- | --- |
| `.script` | Game object Lua | **Yes** — primary workspace |
| `.gui_script` | GUI Lua | **Yes** |
| `.render_script` | Render pipeline Lua | Avoid unless asked |
| `.lua` | Shared module | **Yes** |
| `.go` | Game object prototype | Yes, additively |
| `.collection` | Collection / level | Yes, additively |
| `.gui` | GUI scene | Yes, carefully |
| `.atlas` | Sprite atlas + animations | Yes, carefully |
| `.sprite`, `.label`, `.factory`, `.collectionfactory`, `.collectionproxy`, `.collisionobject`, `.sound`, `.camera`, `.particlefx`, `.tilemap`, `.tilesource`, `.font`, `.material` | Component / resource prototypes | Yes, small edits |
| `.input_binding` | Input map | Yes |
| `.vp` / `.fp` | Shader source | Advanced |
| `game.project` | Project settings | Yes, but never drop existing keys |

> Nothing is instantiated automatically. A `.go` only exists at runtime if a collection places it (or a factory spawns it), and a `.script` only runs if a `.go` references it. "I wrote it and nothing happened" almost always means it was never wired in.

### Reading an existing project

Work top-down, never file-by-file:

1. `game.project` → `[bootstrap] main_collection` tells you the entry collection.
2. In that `.collection`, follow `instances { prototype: ... }` and `collection_instances { collection: ... }` to see what exists and under which id.
3. In each `.go`, `components { component: ... }` tells you which script/sprite/etc. is attached and under which component id. **That id is the address fragment** other code posts to.
4. Read the `.script` last — it is the behaviour, and it will reference `#id` addresses you now recognise.

Useful searches. The five patterns below answer most "where is X?" questions; the tool matters less than the pattern, so use whatever search your harness has if it is better than a shell.

```powershell
# ripgrep, if installed. Skips build\ automatically because Defold gitignores it.
rg "component:"  -g "*.go"          # what a .go is made of
rg "prototype:"  -g "*.collection"  # where a .go is instantiated
rg "collection:" -g "*.collection"  # sub-collections and proxies
rg "script:"     -g "*.gui"         # which gui_script drives a .gui
rg "msg.post"    -g "*.script"      # the actual call graph

# Native PowerShell, no extra tools. Same idea: swap the filter and the pattern.
Get-ChildItem -Recurse -Filter *.go |
  Where-Object FullName -notmatch '\\(build|\.internal)\\' |
  Select-String "component:"
```

The `msg.post` search is the fastest way to understand a codebase: Defold logic is a web of messages, not call stacks.

---

## 3. Addressing and messages

Addresses are the single biggest source of agent bugs. Learn this section.

```
[string socket]:[string path]#[string fragment]
"main:/level/player#sprite"
 └ socket    └ path        └ component id (fragment)
```

| Form | Means |
| --- | --- |
| `"#sprite"` | component `sprite` **in the current game object** |
| `"player#script"` | object `player` **in the current naming context** (relative) |
| `"/level/player#script"` | absolute path from the bootstrap root |
| `"."` | the current game object |
| `"#"` | the current component (the script itself) |
| `"level:/player#script"` | inside a collection proxy game world named `level` |

Rules:

- Absolute paths **must** start with `/`. Relative addresses must be **strings** — `hash("player")` resolves as an absolute path and will fail.
- Ids must be unique within their context and must not contain `:` or `#`.
- `go.get_id()` returns a **hash** of the absolute path. Hashes work anywhere a path string works, but only for absolute paths.
- Use `hash("message_name")` for message ids and constant comparisons; strings are fine as `msg.post` arguments.

### Sending / receiving

```lua
msg.post("#", "reset")                          -- to my own script
msg.post(".", "acquire_input_focus")            -- to my game object (all components)
msg.post("enemy#controller", "punch")
msg.post("/hud#gui", "set_score", { score = 10 })
```

```lua
function on_message(self, message_id, message, sender)
    if message_id == hash("set_score") then
        self.score = message.score          -- message is a table ({} if empty)
        print(sender)                       -- url of the sender
    end
end
```

- Message payload is a Lua table: numbers, strings, booleans, hashes, urls, nested tables. **No functions.** Hard limit **2 KB**.
- Posting is asynchronous: delivery happens later in the frame, in dispatch passes.
- Posting to a **game object** broadcasts to all of its components.
- Unknown recipient → console `ERROR:GAMEOBJECT: Instance ... could not be found`.

### Engine messages worth knowing

| Message | Target | Effect |
| --- | --- | --- |
| `acquire_input_focus` | game object | Add its components to the input stack |
| `release_input_focus` | game object | Remove them |
| `enable` / `disable` | component | Toggle component (sprite, collision, gui, label, …) |
| `set_parent` | game object | `{ parent_id = go.get_id("x"), keep_world_transform = 1 }` |
| `collision_response`, `contact_point_response`, `trigger_response` | collision object | Physics events |
| `play_animation`, `stop_animation` | sprite/model | Animation control |
| `set_text` | label | `{ text = "..." }` |

---

## 4. Lua in Defold

- **LuaJIT, Lua 5.1 semantics.** Use only 5.1 features; HTML5 runs plain Lua 5.1.4.
- Standard libs available: `base`, `coroutine`, `package`, `string`, `table`, `math`, `io`, `os`, `debug`, plus `socket` and `bit`.
- One shared Lua context for all scripts, GUI scripts, render scripts and modules.
  - `local` at the **top level of a file** is shared by every component using that file.
  - A global is shared by the whole game.
  - **Per-instance state belongs in `self`.**
- `self` is userdata: you can read/write fields, but not `pairs(self)` or `pprint(self)`.
- Modules: `require "main.util"` → `/main/util.lua`. Dots become path separators. `require` caches in `package.loaded`.
- Prefer returning a table from a module instead of defining globals.

### Script types and namespaces

| File | Attached to | Has | Does **not** have |
| --- | --- | --- | --- |
| `.script` | a game object | `go.*`, `msg`, `timer`, `vmath`, `factory`, `sprite`, `tilemap`, `sound`, `physics`, `sys` | `gui.*`, `render.*` |
| `.gui_script` | a `.gui` scene | `gui.*`, `msg`, `timer`, `vmath`, `sys` | `go.*`, `render.*` |
| `.render_script` | `game.project` | `render.*` | `go.*`, `gui.*` |

Using `go.*` in a GUI script is a runtime error, not a compile error.

### Lifecycle callbacks

```lua
function init(self) end                 -- component created
function final(self) end                -- component destroyed (cleanup)
function update(self, dt) end           -- every frame; dt in seconds
function fixed_update(self, dt) end     -- only if Physics > Use Fixed Timestep
function late_update(self, dt) end      -- after all update(), before render
function on_message(self, message_id, message, sender) end
function on_input(self, action_id, action) end
function on_reload(self) end            -- editor hot reload
```

The GUI script template provides `init`, `final`, `update`, `on_message`, `on_input` and `on_reload`. GUI scripts have no `go` namespace, so anything that needs the game world goes through messages.

**Delete `update()` if you don't need it.** Prefer reactive code (`timer.delay`, messages, animations) over polling every frame.

### Component properties

Declared at the top level of a `.script` / `.gui_script`, outside any function:

```lua
go.property("speed", 120)                       -- number
go.property("target", msg.url())                -- url
go.property("tint", vmath.vector4(1, 1, 1, 1))  -- vector4
go.property("skin", resource.atlas("/assets/ui.atlas")) -- resource
```

These become editable per-instance in the editor and are read as `self.speed`. A `go.property` with the same name in two scripts is fine; they are per component.

---

## 5. On-disk formats

All of these are protobuf text format: `field: value`, blocks with `{ }`, strings in double quotes, repeated fields simply repeated.

### 5.1 `game.project`

INI sections. Paths are absolute-from-project-root. Note the `.collectionc` suffix the editor uses for the built resource.

```ini
[project]
title = My Game
version = 0.1

[bootstrap]
main_collection = /main/main.collectionc

[display]
width = 960
height = 640
high_dpi = 1

[input]
game_binding = /builtins/input/all.input_bindingc

[physics]
gravity_y = -1000.0
scale = 0.01

[script]
shared_state = 1
```

**Capacity limits (they bite silently):** `[sprite] max_count` defaults to **128** and `[collection] max_instances` to **1024**.
When a limit is hit, `factory.create` fails with `Sprite could not be created since the buffer is full (128)`, and
everything after that call in the same function is skipped. This project sets `max_count = 2048` and `max_instances = 4096`:

```ini
[sprite]
max_count = 2048

[collection]
max_instances = 4096
```

Useful keys: `[display] width/height`, `[physics] gravity_y/scale/debug`, `[graphics] texture_profiles`, `[render] clear_color_red/green/blue`, `[sprite] max_count`, `[collection] max_instances`.

`sys.get_config("display.width")` and `sys.get_config_int(...)` read these at runtime.

### 5.2 `.go` — game object prototype

Two ways to include a component. **Referenced file** (preferred: no escaping):

```text
components {
  id: "script"
  component: "/main/player.script"
  position { x: 0.0 y: 0.0 z: 0.0 }
  rotation { x: 0.0 y: 0.0 z: 0.0 w: 1.0 }
}
components {
  id: "sprite"
  component: "/main/player.sprite"
}
```

**Embedded** (what the editor writes by default). The component's own text is stored in a quoted `data:` string, every line quoted, newlines escaped:

```text
embedded_components {
  id: "sprite"
  type: "sprite"
  data: "tile_set: \"/assets/sprites.atlas\"\n"
  "default_animation: \"idle\"\n"
  "material: \"/builtins/materials/sprite.material\"\n"
  "blend_mode: BLEND_MODE_ALPHA\n"
  ""
  position { x: 0.0 y: 0.0 z: 0.0 }
  rotation { x: 0.0 y: 0.0 z: 0.0 w: 1.0 }
}
```

> Prefer `components { }` with standalone `.sprite` / `.label` files. The escaping in `data:` is easy to get wrong and produces corrupt resources.

Schema: `components` (`id`, `component`, `position`, `rotation`, `scale`), `embedded_components` (`id`, `type`, `data`, `position`, `rotation`, `scale`).

### 5.3 `.collection`

```text
name: "main"
scale_along_z: 0

instances {
  id: "player"
  prototype: "/main/player.go"
  position { x: 480.0 y: 320.0 z: 0.0 }
  rotation { x: 0.0 y: 0.0 z: 0.0 w: 1.0 }
}

instances {
  id: "hud"
  prototype: "/main/hud.go"
}

collection_instances {
  id: "level"
  collection: "/levels/level1.collection"
  position { x: 0.0 y: 0.0 z: 0.0 }
  rotation { x: 0.0 y: 0.0 z: 0.0 w: 1.0 }
}
```

- `instances` → references a `.go` prototype. `collection_instances` → references a `.collection`.
- `embedded_instances` inlines a whole game object as an escaped `data:` string. Same escaping danger; avoid.
- `children` holds ids of child game objects; transformation hierarchy is separate from the addressing hierarchy (addresses never change when you re-parent).
- Runtime path of `player` above: `/player`. A child of `level`: `/level/enemy`.

### 5.4 `.gui` — GUI scene

```text
script: "/main/hud.gui_script"

fonts {
  name: "text24"
  font: "/assets/text24.font"
}
textures {
  name: "ui"
  texture: "/assets/ui.atlas"
}

nodes {
  position { x: 0.0 y: 0.0 }
  size { x: 400.0 y: 300.0 }
  type: TYPE_BOX
  texture: "ui/panel_bg"
  id: "panel"
  layer: "graphics"
  inherit_alpha: true
}

nodes {
  position { x: 0.0 y: 40.0 }
  size { x: 200.0 y: 50.0 }
  type: TYPE_TEXT
  text: "SCORE: 0"
  font: "text24"
  id: "score"
  parent: "panel"
  layer: "text"
  inherit_alpha: true
}

layers { name: "graphics" }
layers { name: "text" }

material: "/builtins/materials/gui.material"
adjust_reference: ADJUST_REFERENCE_PARENT
```

- Node types: `TYPE_BOX`, `TYPE_TEXT`, `TYPE_PIE`, `TYPE_TEMPLATE`, `TYPE_PARTICLEFX`.
- `font:` and `texture:` refer to the **names declared in `fonts`/`textures`**, not file paths.
- Textures are `"atlas_name/animation_name"`.
- **Draw order = order of the `nodes` entries.** Later entries draw on top. `z` does not affect GUI draw order.
- `parent:` must name an existing node id.
- GUI nodes are **not** game objects: no `go.*`, no collision, no `msg.post` to them. Manipulate with `gui.*`.

### 5.5 `.atlas`

**Verified against Defold 1.14.0 in this project.** The editor rejected `animations { start: / end: }` blocks
(`unknown field`). Leave animations out: Defold generates **one animation per image, named after the image file**
(`square.png` -> `"square"`). Do not define an animation with the same id as an image (`"square" is in use by another instance`).

**Update (v5):** the *nested* form is accepted by 1.14.0 and is how this project's flipbooks are stored: `animations { id: "x"` then one
`images { image: "/frame.png" }` per frame, then `playback: PLAYBACK_ONCE_FORWARD`, `fps: 12`, `flip_horizontal: 0`, `flip_vertical: 0` and a closing `}`.
Only `start:`/`end:` are invalid. Do not also list those frames as top-level `images` (that creates extra auto animations). See AGENTS.md item 1.

```text
images {
  image: "/assets/art/square.png"
}
images {
  image: "/assets/art/circle.png"
}
extrude_borders: 2
```

To add images safely use `python tools/add_to_atlas.py <png files>` (additive, idempotent). A multi-frame flipbook
or an animation group should be created in the editor's atlas view; its text format is not documented here, so do not guess it.

### 5.6 Component prototypes

Sprite (`.sprite`):

```text
tile_set: "/assets/sprites.atlas"
default_animation: "idle"
material: "/builtins/materials/sprite.material"
blend_mode: BLEND_MODE_ALPHA
```

`blend_mode` can be `BLEND_MODE_ALPHA` (normal), `BLEND_MODE_ADD` (glows, fire, light), `BLEND_MODE_MULT` or `BLEND_MODE_SCREEN`.
This project has two sprite prototypes: `/main/visual.sprite` (alpha) and `/main/fx.sprite` (`BLEND_MODE_ADD`), each with its own factory (`#visual_factory`, `#fx_factory`).
Glows and light effects look wrong with alpha blending on a dark floor and must use the additive one.

Factory:

```text
prototype: "/main/bullet.go"
load_dynamically: false
dynamic_prototype: false
```

Collection proxy:

```text
collection: "/levels/level1.collection"
exclude: false
```

Label (inside an embedded `data:` or a `.label` file):

```text
text: "Hello"
font: "/builtins/fonts/default.font"
material: "/builtins/fonts/label.material"
blend_mode: BLEND_MODE_ALPHA
line_break: false
```

Font (`.font`):

```text
font: "/assets/SourceSansPro-Semibold.ttf"
material: "/builtins/fonts/font-df.material"
size: 28
output_format: TYPE_DISTANCE_FIELD
```

Builtin resources you can reference without adding files: `/builtins/materials/sprite.material`, `.../gui.material`, `/builtins/fonts/default.font`, `/builtins/fonts/label.material`.

### 5.7 `.input_binding`

```text
key_trigger {
  input: KEY_SPACE
  action: "jump"
}
mouse_trigger {
  input: MOUSE_BUTTON_1
  action: "fire"
}
touch_trigger {
  input: TOUCH_MULTI
  action: "touch"
}
```

Bind multiple inputs to one action to support keyboard + mouse + gamepad together.

---

## 6. Components at a glance

| Type string (in `.go` `data:`) | Lua API | Purpose |
| --- | --- | --- |
| `script` | — | Lua behaviour (referenced file only) |
| `sprite` | `sprite.*`, `go.set` | Flipbook animation / still image |
| `label` | `go.get/set(url,"text")` | World-space text |
| `tilemap` | `tilemap.*` | Tile grid with collision via `.tilesource` |
| `collisionobject` | `physics.*` | Physics body / trigger / static geometry |
| `factory` | `factory.create` | Spawn `.go` instances |
| `collectionfactory` | `collectionfactory.create` | Spawn collections |
| `collectionproxy` | `msg.post(url,"load"/"unload")` | Load/unload a whole game world |
| `sound` | `sound.play` | Audio |
| `camera` | `camera.*` | View/projection |
| `gui` | `gui.*` (in gui_script) | Screen-space UI |
| `particlefx` | `particlefx.*` | Particles |
| `model`, `mesh`, `light` | — | 3D |

Spawning needs the factory component to exist on the object you call `factory.create` from:

```lua
local id = factory.create("#bullet_factory", pos, rot)
go.delete(id)
```

---

## 7. API quick reference

Signatures only; the reference (§11) has the specifics.

```lua
-- go
go.get_id([path])                       -- hash of absolute path
go.get_position([id]) / go.set_position(pos, [id])
go.get_rotation([id]) / go.set_rotation(rot, [id])
go.get_scale([id])    / go.set_scale(scale, [id])
go.get(url, property) / go.set(url, property, value)
go.get_world_position([id])             -- account for parent transforms
go.animate(url, property, playback, to, easing, duration, [delay], [complete_fn])
go.delete([id], [recursive])
go.property(name, default)              -- top level only
go.animate(".", "position.x", go.PLAYBACK_LOOP_PINGPONG, 100, go.EASING_LINEAR, 1.0)

-- math
vmath.vector3(x, y, z) / vmath.vector4(x, y, z, w)
vmath.length(v) / vmath.normalize(v) / vmath.lerp(t, a, b) / vmath.dot(a, b)

-- messages
hash("name")
msg.url([socket], [path], [fragment])
msg.post(receiver, message_id, [table])

-- timers
timer.delay(seconds, repeating, callback)
timer.trigger(hash("name"))

-- input (in on_input)
action.pressed / action.released / action.value / action.x / action.y
action.dx / action.dy / action.source / action_id == hash("jump")

-- factory
factory.create(url, [position], [rotation], [properties], [scale])
collectionfactory.create(url, [position], [rotation], [properties], [scale])

-- sprite
sprite.play_flipbook(url, animation_id, [complete_fn], [properties])
sprite.set_hflip(url, flip) / sprite.set_vflip(url, flip)

-- tilemap
tilemap.get_tile(url, layer, x, y)
tilemap.set_tile(url, layer, x, y, tile)

-- sound
sound.play(url, [properties], [complete_fn])
sound.stop(url)

-- gui (gui_script only)
gui.get_node(id)                        -- nil if missing
gui.new_box_node(pos, size) / gui.new_text_node(pos, text)
gui.set_text(node, s) / gui.get_text(node)
gui.set_color(node, vector4) / gui.set_alpha(node, a)
gui.set_position(node, pos) / gui.set_scale(node, scale)
gui.set_enabled(node, bool) / gui.set_visible(node, bool)
gui.animate(node, property, to, easing, duration, [delay], [complete_fn])
gui.play_flipbook(node, animation_id)
gui.pick_node(node, x, y)               -- hit test in screen coords
gui.clone(node) / gui.clone_tree(node) / gui.delete_node(node)

-- system
sys.get_config("section.key") / sys.get_config_int(...) / sys.get_config_number(...)
print(...) / pprint(table)

-- physics events arrive as messages, not return values
-- contact_point_response: { position, normal, distance, applied_impulse, other_id, other_position, group }
```

---

## 8. Verifying your work

The human runs the game; your job is to make the console clean.

**What the human does:** `Project ▸ Build` (compile only) or `Project ▸ Build and Run` in the editor. A run opens a separate game window.

**What you can check:**

1. **Ask for the console.** Every Lua error appears there with file and line:
   ```
   ERROR:SCRIPT: /main/player.script:42: attempt to index a nil value (field 'target')
   ```
   `ERROR:GAMEOBJECT: Instance '/player' could not be found when dispatching message ...` means a bad address.
   `ERROR:RESOURCE: ...` / `Unable to find resource` means a path in a resource file is wrong.

2. **The editor HTTP API** (only if the editor is open and you are permitted to use it). Port is in `.internal/editor.port`:
   ```powershell
   $port = Get-Content .internal\editor.port
   $base = "http://127.0.0.1:$port"

   Invoke-RestMethod "$base/openapi.json"        # authoritative operations for THIS version

   # compile: 200 = success, 422 = failure. A 422 throws, so catch it to read the issues.
   try   { Invoke-RestMethod -Method Post "$base/command/compile" }
   catch { $_.ErrorDetails.Message | ConvertFrom-Json }   # { success, issues[] }

   Invoke-RestMethod "$base/console"             # console lines + regions
   Invoke-RestMethod "$base/ref?q=go.animate"    # version-correct API search
   ```
   On PowerShell 7 you can add `-SkipHttpErrorCheck` to `Invoke-RestMethod` instead of the try/catch. **`curl` in PowerShell is an alias for `Invoke-WebRequest`**, which takes different flags — if you need curl syntax, call `curl.exe` explicitly.

   A compile failure returns structured `issues` with `resource`, `severity` and a `range` of line/character — far better than guessing. Always read `/openapi.json` first; endpoints are version-dependent. `/eval` needs the token in `.internal/editor.token` — **do not** put that token in prompts, logs, or commits.

   If the call fails with a connection error rather than an `issues` payload, the editor is closed or `.internal\editor.port` is stale — the port can change between editor restarts, so re-read the file.

3. **Editor previews** (1.13.1+): `GET /preview/main/main.collection?width=1280&height=720` renders a scene to PNG. Good for catching layout mistakes without playing.

4. **Headless smoke test** (`tools/smoke_test.lua`, optional but catches a lot): runs `main/game.script` against a mock Defold API
   in LuaJIT: title -> 9 rooms -> win, plus deaths. It checks missing instances, double deletes, unknown animation ids,
   NaN positions, the sprite cap (`SPRITE_MAX`), leaked objects and wall clipping. It does **not** model rendering,
   blending, z-order, the editor's file parsing or real physics, so a green run is never proof the game works.
   Report it as "mock test passed; not modeled: ...".

**Hot reload:** scripts and Lua modules usually reload into a running game when saved. Changes to `game.project`, `.go`/`.collection` structure, component properties and resource prototypes generally need a game restart. If a change seems ignored, restart before debugging the code.

---

## 9. Failure modes that bite agents

1. **Wrong callback name.** `Update` is not `update`; `onMessage` is not `on_message`. Unknown globals fail silently (Lua ignores them), so nothing runs and nothing errors.
2. **Comparing a hash to a string.** `message_id == "punch"` is always false. Use `hash("punch")`.
3. **Relative address passed as a hash.** `go.get_position(hash("enemy"))` fails; use the string `"enemy"`.
4. **`go.*` inside a `.gui_script`.** Runtime error. Send a message to a game script instead.
5. **Forgetting `acquire_input_focus`.** `on_input` is never called.
6. **Editing an unreferenced file.** A `.script` that no `.go` references does nothing.
7. **Assuming GUI `z` controls order.** Only `nodes` order and `layers` do.
8. **Forgetting `parent` references.** A `nodes { parent: "x" }` where `x` doesn't exist corrupts the scene.
9. **Broken `data:` escaping** in `embedded_components` / `embedded_instances`. Prefer separate files.
10. **Rewriting `.collection` from scratch.** You will drop `component_properties`, `children`, `scale3`, or ids other files address. Edit additively.
11. **Creating a render script** because "rendering needs customising". It replaces the entire default pipeline and must be wired in `game.project`. Don't, unless asked.
12. **Assuming physics units are pixels.** `physics.scale` in `game.project` maps pixels to metres (0.01 typical). Gravity of `-1000` in a 0.01-scale project is normal.
13. **Huge per-frame allocations.** `vmath.vector3()` in `update()` allocates every frame. Mutate existing vectors instead.
14. **Editing files the editor has open with unsaved changes.** Your edit can be overwritten when the human saves. Say so, or edit first and ask them to reload.
15. **Capacity limits.** `sprite.max_count` (128) and `collection.max_instances` (1024) defaults are small. See §5.1.
16. **Reading the last error instead of the first.** A failed `factory.create` aborts the rest of `init`, which then produces hundreds of unrelated nil errors. Fix the first.
17. **Initialising state after risky calls.** Set every field `update`/`on_input` reads (`self.aim`, tables, timers) at the top of `init`, before creating sprites.
18. **Tint multiplies.** Tinting dark or coloured art by a colour makes it darker; on a dark floor it vanishes. Tinted art must be white/light grey; use `tint = false` for coloured art.
19. **Additive effects need the additive sprite** (`BLEND_MODE_ADD`), at a visible size (a 64 px sprite at scale 0.15 is a 10 px speck).
20. **Atlas animation blocks.** `animations { start/end }` is rejected by this editor; see §5.5.
21. **BOM.** PowerShell 5.1 `Set-Content -Encoding UTF8` writes a BOM that Defold refuses. Write files without a BOM.
22. **Screen/GUI/world origin is the bottom-left.** `0,0` is the lower-left corner for sprites and GUI; the arena centre is `(480, 320)`.
23. **Deleting a visual twice / leaving one behind.** Delete each instance exactly once, nil the reference when you do, and delete tracked visuals in `clear_world`.
24. **Delayed callbacks use stale state.** `timer.delay` closures run after rooms change; guard them with a world id and a state check.
25. **Lua 5.1 only.** No `goto`, no `//`, no bit operators; use the `bit` module. LuaJIT on desktop, plain Lua 5.1 on HTML5.
26. **Claiming success you did not verify.** Say what you ran and what you could not run.

---

## 10. Recipes

### Minimal wiring for a new behaviour

1. Create `/main/player.script`:
   ```lua
   function init(self)
       self.speed = 200
       msg.post(".", "acquire_input_focus")
   end

   function on_input(self, action_id, action)
       if action_id == hash("left") and action.pressed then
           local p = go.get_position()
           p.x = p.x - self.speed * 0.1
           go.set_position(p)
       end
   end
   ```
2. Reference it from `/main/player.go` (`components { id: "script" component: "/main/player.script" }`).
3. Put `instances { id: "player" prototype: "/main/player.go" }` in `main.collection`.
4. Add `key_trigger { input: KEY_LEFT action: "left" }` to `input/game.input_binding`.

### Spawn, animate, delete

```lua
function fire(self)
    local pos = go.get_position()
    pos.y = pos.y + 40
    local id = factory.create("#bullet_factory", pos)
    go.animate(id, "position.y", go.PLAYBACK_ONCE_FORWARD, pos.y + 800,
               go.EASING_LINEAR, 1.0, 0, function() go.delete(id) end)
end
```

### GUI counter

```lua
-- hud.gui_script
function init(self) self.score = 0 end

function on_message(self, message_id, message, sender)
    if message_id == hash("add_score") then
        self.score = self.score + message.amount
        gui.set_text(gui.get_node("score"), "SCORE: " .. self.score)
    end
end
```
From a game script: `msg.post("/hud#gui", "add_score", { amount = 10 })`.

### Timed sequence without `update` loops

```lua
timer.delay(2, false, function()
    msg.post("#", "spawn_wave")
end)
```

### Camera follow

```lua
function update(self, dt)
    local target = go.get_position("/player")
    local cam = go.get_position("/camera")
    go.set_position(vmath.lerp(0.1, cam, target), "/camera")
end
```

### Switch level with a collection proxy

```lua
msg.post("#level_proxy", "unload")
msg.post("#level_proxy", "load")
```
Proxy `.go` component needs `collection: "/levels/level1.collection"`, and the proxy object must acquire input focus if the loaded world needs input.

### Read a tile / set a tile

```lua
local t = tilemap.get_tile("#ground", "layer1", x, y)
tilemap.set_tile("#ground", "layer1", x, y, 0)
```
Coordinates are tile coordinates, not pixels.

---

## 11. Where to look things up

| Need | Go to |
| --- | --- |
| Concept / workflow | <https://defold.com/manuals/> |
| Exact API signature | <https://defold.com/ref/> — or the editor's `/ref?q=...` for the *installed* version |
| Copy-paste examples that compile | <https://github.com/defold/examples> |
| LLM-oriented doc index | <https://defold.com/llms.txt> (index) · <https://defold.com/llms-full.txt> (offline/RAG only — too big for context) |
| Agent automation contract | <https://defold.com/manuals/ai-agents> · `/manuals/editor-http-api` · `/manuals/engine-service` |
| Resource field names | The protobuf schemas: `engine/gameobject/proto/gameobject/gameobject_ddf.proto` in [defold/defold](https://github.com/defold/defold) |

Prefer `/ref?q=` over fetching the whole reference: it returns only what matches, from the version actually installed.

---

## 12. Provenance of this document

Written 2026-11-06 against Defold **1.14.0** (stable).

- Resource formats verified against real files in `defold/examples` (`.go`, `.collection`, `.gui`, `.atlas`, `.font`, `.input_binding`, `game.project`) and against `gameobject_ddf.proto` (protobuf schema).
- Lua/lifecycle/addressing/messaging rules from the official manuals (`script`, `lua`, `modules`, `addressing`, `message-passing`, `gui`, `gui-script`, `input`).
- Automation endpoints from the `editor-http-api` and `ai-agents` manuals.

**Updated 2026-11-10** after building and reviewing this project on Defold 1.14.0: corrected §5.5 (atlas), added capacity limits (§5.1),
the additive sprite (§5.6), the smoke test (§8), failure modes 15-26 (§9) and the asset pipeline (§13).

If the project uses a different Defold version, re-check §8's `/openapi.json` and prefer the editor's own documentation over this file.

---

## 13. Adding art and assets (this project)

> Everything visual is driven by **one manifest, `src/core/art.lua`**, and **one atlas, `assets/art/shapes.atlas`**.
> The game must keep running with placeholder art, so every change below is "add a file, add one manifest line".

### 13.0 Rules that apply to every asset
1. **One atlas, one namespace.** Every image the game draws must be listed in `assets/art/shapes.atlas`.
   Defold names each animation after its **image file name without the extension**
   (`witch.png` -> `"witch"`). Two files with the same name in different folders collide, so keep names unique
   (prefix with the pack: `td_wall_face.png`, `tc_slime.png`).
2. **Add images with the tool, not by hand:** `python tools/add_to_atlas.py <files...>` appends `images { }` blocks
   additively and skips files that are already there. Never write `animations { start/end }` blocks (see §5.5).
3. **Never edit a PNG in place.** Keep the original downloads **outside** the project (e.g. `downloads/`), copy
   only the sprites you use into `assets/art/<category>/`. Use a script (Pillow) if you must change pixels,
   and note the change in `CREDITS.md`.
4. **Credit in the same change.** One line in `CREDITS.md` **and** in `src/core/credits.lua` per pack/asset
   (name, author, license, URL). Only CC0 / CC BY. No CC BY-SA, NC, ND, "all rights reserved", or unknown licenses.
5. **Keep the fallback.** `art.ENABLED = false` must still give a playable game (tinted shapes). Never make the
   game depend on a third-party file existing.
6. **After any atlas change the human must refresh the editor** (close/reopen the project or use File > Reload)
   and run the game. Then read the console **from the top: the first error is the real one** (see §9).
7. **Count sprites.** The arena uses about 330 sprites; `game.project` sets `[sprite] max_count = 2048`.
   Do not add per-frame sprite spawning without a cap (particles are capped at 260).
8. **Pixel art:** use whole-number scales and set the texture filter to *nearest* in `game.project`
   (Graphics section; check the exact key in the editor's project settings before writing it).

### 13.1 Where each kind of asset plugs in

| Asset | Folder | Manifest key | Tinted by code? | Size rule |
| --- | --- | --- | --- | --- |
| Floor / wall / pillar / torch tiles | `assets/art/tiles/` | `art.TILES.floor_a`, `floor_b`, `wall_face`, `wall_top`, `pillar`, `torch` | per entry: `tint = true` recolours **grey** art with the room palette, `tint = false` keeps the pack's colours | tile cell is **48 px**; `scale = 48 / image_px` (16 px art -> 3) |
| Player | `assets/art/actors/` | `art.ACTORS.player` | **No** (white tint). Flips left/right to face the aim point, blinks (alpha) while invulnerable | on-screen size = `image_px * scale`; aim for about 40 px |
| Enemies | `assets/art/actors/` | `art.ACTORS.wisp`, `slinger`, `charger`, `brute`, `splitter`, `boss` (keys = ids in `src/game/enemies.lua`) | **No**; status colours (burn, slow...) multiply the art; hit flash = a scale pop | match the collision radius: wisp 12 px, brute 18 px, boss 32 px radius -> draw about `2 * radius` px wide |
| Animated spell effects (flipbooks) | `assets/art/fxa/` (generated, do not hand-edit) | generated `src/core/fxanim.lua`; rebuild with `python tools/build_fx_anim.py` | **No** - native element colours (smoke is tinted) | 64 px frames, cropped; see §13.5 |
| Spell effects | `assets/art/fx/` (or `particles/`) | `art.FX.<role>` (table in §13.3) | **Yes**: tinted with the skill's blended element colour | **white / light grey, soft edges, brightness in the alpha channel**, 64-128 px |
| Element icons (HUD, reward cards) | `assets/art/icons/` | `art.ELEMENT_ICONS.fire` ... | Yes (HUD tints with the element colour) | white single-colour art, about 64 px |
| Arena sigil, vignette, glow orb | `assets/art/` | `art.FX.rune`, files `vignette.png`, `glow.png` | rune: yes; vignette: no | `vignette.png` stretches to 960x640; `glow.png` is a 128 px soft orb |
| Fonts | `assets/fonts/` | not in the manifest (HUD uses `/builtins/fonts/default.font`) | n/a | create a `.font` file (see §5.6), then add a `fonts { }` entry to `main/hud.gui` **additively** |
| Sound | `assets/sfx/` | not implemented yet | n/a | would need a `sound` component; read the sound manual and §7/§11 first, do not guess the API |

### 13.2 Recipes

**A. Environment (e.g. Kenney Tiny Dungeon, CC0)**
1. Download the pack to `downloads/`. Pick one image each for: floor, a floor variant, wall face (the front of a wall,
   drawn when floor is south of it), wall top (plain wall seen from above), pillar/column, torch decal.
2. Copy and rename into the project: `assets/art/tiles/td_floor_a.png`, `td_floor_b.png`, `td_wall_face.png`,
   `td_wall_top.png`, `td_pillar.png`, `td_torch.png`.
3. `python tools/add_to_atlas.py "assets/art/tiles/td_*.png"` (quote the pattern: the tool expands `*` itself, which also
   works in PowerShell where the shell would not). Or list the files one by one.
4. In `src/core/art.lua` change the entries, e.g.
   ```lua
   floor_a   = { anim = "td_floor_a",   scale = 3, tint = false },
   wall_face = { anim = "td_wall_face", scale = 3, tint = false },
   pillar    = { anim = "td_pillar",    scale = 3, tint = false },
   ```
   Keep `torch.tint = false` (the torch decal is coloured; the flame glow is added by code).
5. Update credits, ask the human to refresh and run. Expected: the same 9 rooms drawn with the new tiles; the wall
   accent line and torch glow still appear. The collision grid never changes with the art.

**B. Player and enemies (e.g. Tiny Creatures sheet, CC0)**
1. If the pack is one sheet: `python tools/slice_sheet.py downloads/tiny_creatures/tilemap_packed.png assets/art/actors tc 16`
   (use the packed sheet with spacing 0; try spacing 1 if tiles look cut off). This writes `tc_000.png`, `tc_001.png` ...
   Look at the sheet, then rename the ones you want: `tc_witch.png`, `tc_willowisp.png`, `tc_goblin.png`,
   `tc_boar.png`, `tc_golem.png`, `tc_slime.png`, `tc_lich.png`. Delete the rest (do not add unused images to the atlas).
2. `python tools/add_to_atlas.py assets/art/actors/tc_witch.png ...`
3. In `src/core/art.lua`:
   ```lua
   M.ENABLED = true
   M.ACTORS = {
       player   = { anim = "tc_witch",      scale = 3 },
       wisp     = { anim = "tc_willowisp",  scale = 3 },
       slinger  = { anim = "tc_goblin",     scale = 3 },
       charger  = { anim = "tc_boar",       scale = 3 },
       brute    = { anim = "tc_golem",      scale = 3.6 },
       splitter = { anim = "tc_slime",      scale = 3 },
       boss     = { anim = "tc_lich",       scale = 6 },
   }
   ```
   Splitter children and boss summons are spawned as **wisps**, so they use the `wisp` art.
   An enemy with no entry falls back to its tinted shape.
4. Static art is brought to life in code (hit pop, tint, flip). Do not add frame animation unless the sprites are
   a flipbook in the atlas; if you want one, give the actor `anim` a multi-frame animation and ask the human to
   define it in the editor (the text format for animation groups is not documented here).

**C. Spell art**
1. Make or choose **white/light-grey** images with soft edges (brightness in alpha). 64-128 px. Put them in `assets/art/fx/`.
2. `python tools/add_to_atlas.py assets/art/fx/my_orb.png`
3. Point a role at it in `art.FX`, e.g. `glow = "my_orb"` or `star = "my_star"`.
4. Do **not** paint colour into spell art; the colour comes from the elements (Fire + Water = a blended colour).
5. Roles and where they are used:

| `art.FX` role | Blend | Used for |
| --- | --- | --- |
| `glow` | additive | bolt glow and trail, pool disc and bubbles, orbit glow and sparks, cast flash, hit flash, dash afterimages, torch light, motes, player glow, wand tip |
| `core` | normal | bolt head, orbit orbs, enemy bullets (placeholder player body) |
| `circle` (ring) | additive | pool ring, Nova rings, kill ring, player-hit ring, wave-2 pulse, telegraph rings, arena sigil |
| `star` | additive | hit spark, Nova spokes, Spray particles, kill stars |
| `scorch` | additive | kill splat, charger wall-slam burst |
| `rune` | additive | arena centre sigil |
| `square` | additive | wall accent line |
| `spark`, `flare`, `magic`, `twirl`, `smoke`, `flame`, `trace` | additive | available (via `data.ART.particle.*`) |

6. Sizes and counts of each effect are set where it is spawned (`fx_hit`, `fx_kill`, `fx_cast`, and the `do_cast`
   branches in `main/game.script`). Change numbers there, not the art.
7. **Per-element art** (a different bolt sprite for fire and water) is not built in. To add it, create a table
   `art.FX_BY_ELEMENT[element]` and look it up in `do_cast` from the skill's first element; keep the generic role as the fallback.

**D. A new room**
1. Add an entry to `src/levels/rooms.lua` (legend in `src/game/level.lua`; wave-1 enemies lowercase, wave-2 uppercase).
2. Run `python tools/validate_rooms.py`. It must print `0 problem(s)`.
3. The boss room is the **last entry**; `ROOM_COUNT` in `src/core/data.lua` is the number of rooms before the boss.
   Room palettes live in `PALETTES` in `main/game.script` (9 entries; later rooms reuse the last).

**E. Verify (always, in this order)**
1. `python tools/validate_rooms.py`
2. `python tools/run_smoke_test.py` (needs `pip install lupa`), and again with `ART_TEST=1` (PowerShell: `$env:ART_TEST=1`).
   It must print `RESULT: PASS (mock only)`: 0 errors, 0 wall clipping, no leaked objects, every enemy reaches the player.
3. Ask the human to refresh, run, and paste the console. Read the **first** error.
4. Tell the human exactly what was **not** verified (rendering, blending, z-order, the editor's file parsing).

### 13.3 Draw order (z) cheat sheet
`-0.8` floor tiles, `-0.7` walls, `-0.6` sigil and torches, `-0.4` pillars, `0` entities, `0.02` bolt cores,
`0.1` additive effects, `0.9` vignette. The default render script clips outside `-1..1`. GUI is always on top.

### 13.4 Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Nothing draws, console says the animation was not found | image not in the atlas, or the id in `art.lua` is misspelled (ids are file names without `.png`) |
| Sprite is black / very dark | art is dark or coloured **and tinted** (tint multiplies). Use white art for tinted roles, or set `tint = false` |
| Glow looks flat or has a hard square edge | it was drawn with normal blending, or the PNG has an opaque background. Use the additive `fx` factory and a transparent PNG |
| Pixels look blurry | texture filter is not nearest, or the scale is not a whole number |
| `Sprite could not be created since the buffer is full` | raise `[sprite] max_count` in `game.project` (restart the game) |
| Lots of unrelated nil errors after one early error | `init` aborted halfway; fix the **first** error |
| New image ignored | the editor still has the old atlas loaded; reload the project |
| `bad argument #1 to 'disable_state' (number expected, got nil)` repeated every frame | render script uses `render.STATE_*` / `render.BLEND_*`; on 1.14 they are `graphics.*` (AGENTS.md item 44) |
| Game is stretched/blurry when the window is maximised | no letterboxing render script; this project sets `[bootstrap] render = /main/letterbox.renderc` (§13.5) |
| Aim or menu clicks are offset at a non-960x640 window | `to_design()` (game.script) or `hit()` (hud.gui_script) assumptions broke; see AGENTS.md item 47 |

### 13.5 Animated skill effects and the letterboxed view (added v5-v7)

**Animated effects.** `tools/build_fx_anim.py` (run from the project root; needs `pip install pillow numpy` and the pack zips in `downloads/`)
slices effect sheets into `assets/art/fxa/*.png`, rewrites every `fxa_*` animation block in `assets/art/shapes.atlas`, and generates `src/core/fxanim.lua`
(`ANIMS` lengths/sizes, `FAM` size/facing, `COMPOUND` = which effect family each compound uses per shape, `CAST`, `PUFF`). It also writes `docs/fx_anim_preview.png`.
- Colour: each 64 px effect sheet has 9 colour rows; the tool uses row 0 (fire), 2 (water), 5 (wind/white), 4 (earth). Fire-pack flames loop for bolt heads (`headflame`) and orbit orbs (`orbflame`). Smoke (`smoke_a/b`) is white and tinted at runtime.
- Code: `anim_fx`, `smoke_puff`, `flame_make` in `main/game.script`; live one-shots are in `self.anims` (cap 90) and deleted when their animation ends; `clear_world` deletes them. `art.ANIM_FX = false` turns it all off.
- Change a skill's look: edit `COMPOUNDS` in the tool (numbers are file numbers inside the two big packs), re-run, reload the project. `tools/smoke_test.lua` checks that all 50 skills play their own effects and that every animation exists in the atlas.
- Licences: three of the packs have no licence file or recorded author (AGENTS.md item 46); resolve before releasing.

**Letterboxing.** `main/letterbox.render_script` (set via `[bootstrap] render = /main/letterbox.renderc`) draws the world into the largest centred 960x640 rectangle that fits the window; the GUI keeps a window-sized projection whose default "fit" adjust gives the same rectangle.
The mouse is converted by `to_design()` in `main/game.script`; menu buttons are hit-tested by hand in `main/hud.gui_script` (`hit()`), valid while buttons keep the default pivot and no parent.
Render scripts are not exercised by `tools/run_smoke_test.py`; verify them by running the game. On 1.14 use `graphics.*` constants (AGENTS.md item 44).
