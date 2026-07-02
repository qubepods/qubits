# open_sesame — variables & secrets, end to end

**Live:** <https://open-sesame.qubepod.app/> — try
[`/open?password=wrong`](https://open-sesame.qubepod.app/open?password=wrong) (403)
and `/open?password=<the secret>` (200).

A door-keeper API in one file. It greets with the project **variable**
`GREETING` and opens only for the project **secret** `SESAME_PASSWORD`.
Neither value appears anywhere in this repo — that's the point.

## The pattern (copy this)

**1. Declare what you need in `qube.json5`** — names only, never values:

```json5
imports: {
  variables: [{ name: "GREETING" }],          // plain config  -> env.GREETING
  secrets:   [{ name: "SESAME_PASSWORD" }],   // sensitive     -> env.SESAME_PASSWORD
}
```

Optional `binding` renames a value inside the qube
(`{ name: "API_KEY", binding: "UPSTREAM_KEY" }` → `env.UPSTREAM_KEY`).

**2. Set the values on the project** — console → your project →
**Variables & Secrets**. Variables stay readable there; secrets are
write-only (replaceable, never viewable) and envelope-encrypted at rest.
Every application in the project shares the same set; other projects see
none of it — which is exactly how the two-project stage/prod pattern keeps
a test key and a live key apart under the same names.

**3. Read them off `env` in your handler** — nothing to fetch or decrypt:

```js
export default {
  async fetch(request, env) {
    env.GREETING          // "Welcome, traveler"
    env.SESAME_PASSWORD   // compare it; never echo it
  }
}
```

## Why declare them in the manifest?

Because it moves failure from runtime to **deploy time**. Deploy with a
declared value unset and `qube deploy` refuses, telling you exactly what to
fix:

```
HTTP 422
this qube requires variable(s) GREETING and secret(s) SESAME_PASSWORD — not
set for this project. Set them in the console (Project → Variables & Secrets),
then redeploy.
```

The declaration is also a least-privilege boundary: **only declared names are
injected**. A project value the manifest doesn't name is invisible to the
qube, so the manifest is the complete, reviewable statement of what the code
can see.

## Deploying it yourself

In the **web shell** ([app.qubepods.com](https://app.qubepods.com), already
signed in): set the two values on your project, then `qube deploy`.

From a **terminal**: mint a project token (Project → API tokens, `deploy`
scope), then

```console
$ qube pod login --token <qube_…>
$ qube deploy
```

Changed a value later? Redeploy (or promote) and the new value rides along —
secrets are resolved fresh on every deploy, never baked into the artifact.

## Files

- [`qube.json5`](./qube.json5) — the manifest; the `imports` block is the example.
- [`worker.js`](./worker.js) — the handler; reads `env.GREETING` / `env.SESAME_PASSWORD`.
