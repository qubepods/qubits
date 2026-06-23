// GENERATED from the `@state(app)` declarations in counter.q — do not edit.
//
// This is the backend half of the twin. It runs server-side as ONE instance
// for the whole project (a Durable-Object-backed actor), owns the app-scoped
// `count`, persists it, and fans each change out to every frontend subscribed
// to it. The frontend never writes the number directly — a tap turns into the
// `inc` command below, the twin applies it to the single shared `count`, and
// the new value is pushed to everyone.

state count = 0

pub fn inc() {
  count = count + 1
}
