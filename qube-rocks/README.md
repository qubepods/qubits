# Qube Rocks — a little Asteroids you can make your own

Fly a ship, thrust, fire, break rocks into smaller rocks. It's a complete browser
game — no backend, no server — and it's meant to be a **starting point**: copy
this folder and change a few files to build your own game.

## Play it

The on-screen buttons work on touch; the keyboard mirrors them.

| Action | Touch | Keyboard |
|---|---|---|
| Turn left / right | ◄ ► | ← → / A D |
| Thrust | ▲ | ↑ / W |
| Fire | ● | Space |

## Make your own game

A game here is four small pieces — a **scene** (what's on screen), a **skill**
(what happens each tick), a **controller** (the buttons), and a tiny page that
ties them together. To make your own, copy `qube-rocks/` and edit two files.

### 1. Your world — `web/scene.json`

Everything on screen is data. Each entity is a shape with a position, plus a
camera and a light. Add, remove, or recolour them:

```json5
{
  "name": "ship",
  "geometry": { "kind": "cone", "radius": 0.32, "height": 0.8 },  // or "sphere"
  "material": { "color": [0.45, 0.85, 1.0, 1.0] },
  "transform": { "position": [0, 0, 0] }
}
```

Want a model instead of a built-in shape? Use `"geometry": { "kind": "gltf",
"source": "ship.glb" }` and list the file under the scene's `assets`.

### 2. Your game loop — `web/qube-rocks.skill.js`

`onPreStep(dt)` runs every tick (64×/second). Read the controller, then move,
turn, and create things:

```js
var ship = world.get("ship");
onPreStep(function (dt) {
  // input(0)=turn, input(1)=thrust, input(2)=fire — driven by the buttons/keys
  var r = ship.transform.rotation;
  ship.transform.rotation = { x: 0, y: r.y + input(0) * 3 * dt, z: 0 };  // steer

  if (input(2) > 0.5) {
    var bullet = world.spawn("bullet");          // clone a template from the scene
    if (bullet) bullet.transform.position = ship.transform.position;
  }
});
```

The toolkit a skill has:

- **Move & turn** — `entity.transform.position` / `entity.transform.rotation` (read and set).
- **Create & remove** — `world.spawn("templateName")` clones a scene entity; `world.despawn(handle)` removes it.
- **Read the controller** — `input(0)`, `input(1)`, … one number per button/axis.
- **Glow** — `entity.material.emissive = { x, y, z }`.

### 3. Your controls

The scene's `"overlay"` links the shared on-screen controller. Keep it as-is, or
point it at your own overlay to change the buttons.

### 4. Ship it

```sh
qube deploy
```

That's it — a static page on the web, no server to run.

## Files

- `web/scene.json` — your world: the entities, the camera, and the links to the skill + controller.
- `web/qube-rocks.skill.js` — your game loop.
- `web/index.html` — loads the engine and ties the scene, skill, and controls together (you rarely touch this).
- `qube.json5` — the manifest (`static: { dir: "web" }`).

## Run it

In Qubonaut (`app.qubepods.com`), from this folder:

```sh
qube run        # serves web/ — open the Preview
```

You can also open `web/index.html` on any local static server.

> The page loads the 3D engine and the controller from `cdn.qubeworlds.com`. If
> that's offline/blocked, it shows a load error instead of the game.
