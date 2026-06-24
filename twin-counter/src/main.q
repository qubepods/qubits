//! frontend — the twin half that renders.
//!
//! Holds one live channel to the backend twin: it sends `Tap` up on each press
//! and receives the count down. A spawned loop redraws on every value the twin
//! broadcasts, so a tap on *any* device updates this screen too. Compiles to
//! wasm32, renders via WebGPU (qview).
//!
//! `connect<counter.join>()` opens the dual end of the backend's `join` channel
//! (the local name `counter` is bound to the backend in qube.json5's
//! `rpc.import`). The call carries `@wire` — disclosed in `qube audit`.
//!
//! Drawing uses the **retained** QView protocol (`spec/qview-protocol.md`): a
//! producer creates addressable nodes once and then mutates them by id — the
//! host keeps a `node_id → draw record` map and diffs. This is the contract every
//! current host implements (the older immediate-mode `text`/`number`/`button`
//! face was a POC the retained protocol replaced).

import counter.{join}

struct Tap {}

state count = 0

// Stable retained node ids (0 is ROOT). 1: heading, 2: the live count, 3: button.
fn main @wire {
    build()                                         // create the retained scene once

    let twin = connect<counter.join>()              // Channel<Tap, i64>: send Tap, recv counts
    spawn { for n in twin { count = n; paint() } }  // live: re-draw the count on every broadcast

    // HOST SEAM 2 — press source. qview delivers presses through the host event
    // stream `presses()`; each press becomes `twin.send(Tap)`. (env.md's channel
    // frontend.)
    for _press in presses() {
        twin.send(Tap)
    }
}

// Build the scene once. Raw protocol constants (kept inline, as the q64 host
// examples do): KIND.label = 4, KIND.button = 6; ATTR.x = 0, y = 1, w = 2, h = 3,
// radius = 4, text_id = 9. A `text_id` < 1000 renders as that integer (the live
// count); >= 1000 indexes the host glyph catalog (1035 = "Counter", 1011 = "Tap +1").
fn build {
    qview.create(1, 4, 0)           // heading — a label under ROOT
    qview.set_attr(1, 0, 40)        // x
    qview.set_attr(1, 1, 56)        // y
    qview.set_attr(1, 9, 1035)      // text_id → "Counter"

    qview.create(2, 4, 0)           // the live count — a label
    qview.set_attr(2, 0, 40)        // x
    qview.set_attr(2, 1, 120)       // y
    qview.set_attr(2, 9, count)     // text_id < 1000 → the integer count itself

    qview.create(3, 6, 0)           // the tap button
    qview.set_attr(3, 0, 40)        // x
    qview.set_attr(3, 1, 180)       // y
    qview.set_attr(3, 2, 280)       // w
    qview.set_attr(3, 3, 72)        // h
    qview.set_attr(3, 4, 16)        // radius
    qview.set_attr(3, 9, 1011)      // text_id → "Tap +1"

    qview.present()
}

// A new count arrived — mutate just the count node by id and re-present (the
// retained host diffs; identity/focus/animation elsewhere are preserved).
fn paint {
    qview.set_attr(2, 9, count)
    qview.present()
}
