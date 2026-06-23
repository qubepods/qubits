# qubepods-examples

Example [Qubes](https://qubepods.com) you can read, pull, and deploy.

Each folder is a self-contained [q64](https://q64.dev) Qube with its own
README. They start small and stay honest: every example is real source you
can build with `qube` and deploy to a qubepods project.

## Examples

| Example | What it shows |
|---------|---------------|
| [**backend-counter**](./backend-counter/) | The backend starter. A page with a button and a shared count — one Durable Object, one SQLite-backed number, every visitor sees the same total. Demonstrates a backend-enabled project and the `env.kv` → `wasi:keyvalue` connection. |

## Using an example

Each example is a normal qube. From its folder:

```sh
qube build --component     # build the wasm component
qube pod deploy            # deploy into one of your qubepods projects
```

See the example's own README for what it does and which kind of project it
needs (some need a project with the **Backend** switch turned on).

## License

MIT — see [LICENSE](./LICENSE).
