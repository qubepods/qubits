//! src/ui/scene_overlay.q — the reusable "3D scene + form on top" composite.
//!
//! A QView component-registry BLOCK (copy-and-own; you own and may edit this
//! file). It pairs a `scene` viewport (the 3D, rendered host-side by the engine)
//! with a frosted `card` floated over it — the canonical consumer of the `scene`
//! kind (q64 spec/qview-protocol.md §"3D scene viewport"). The block owns the
//! layering and id bookkeeping; the caller fills the returned card.
//!
//! Lowers to nothing but `qview.*`, so it carries only `@ui` — the 3D render is a
//! HOST capability behind the `scene` kind, not a new effect. Swapping the
//! renderer (web quine ↔ native sokol) changes nothing here.
//!
//! Home: q64.view component registry (spec/qview-ui-registry.md). `q64.view`
//! supplies the `Ctx` (id cursor + theme) and `proto` constants it builds on;
//! `proto.q` here is the vendored stand-in until q64.view ships.

use q64.view.{ Ctx }
use ui.proto.{ KIND, ATTR }
use ui.card.{ card }

/// A 3D `scene_id` viewport with a frosted card overlaid. Returns the CARD's node
/// id, so the caller parents its controls under the result and the 3D stays
/// untouched behind them.
///   c        — id-allocating context + theme (q64.view)
///   parent   — where to mount (0 = root)
///   scene_id — host scene-catalog id (0 = the default turning cube)
pub fn scene_overlay(c: Ctx, parent: i64, scene_id: i64) -> i64 {
  // BACK layer — the 3D viewport (the host renders it; Stage 1 = full-bleed).
  let view = c.next()
  qview.create(view, KIND.scene, parent)
  qview.set_attr(view, ATTR.scene_id, scene_id)

  // FRONT layer — the form, composited on top.
  let panel = card(c, parent)
  return panel
}
