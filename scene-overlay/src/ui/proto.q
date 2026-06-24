//! src/ui/proto.q — named QView protocol constants (vendored mirror).
//!
//! The q64-side mirror of runtime/web-retained/protocol.js, owned by `q64.view`
//! (q64.view.proto). Vendored here as a stand-in until q64.view ships, so the
//! registry components read `KIND.scene` / `ATTR.scene_id` instead of magic
//! integers. Pinned to PROTOCOL_VERSION '1.11' (see ui.lock.json5). APPEND-ONLY.

pub const KIND = {
  box: 0, row: 1, column: 2, stack: 3, label: 4, image: 5, button: 6,
  checkbox: 7, switch: 8, radio: 9, slider: 10, progress: 11, dropdown: 12,
  divider: 13, group: 14, meter: 15, knob: 16, text_input: 17, text_area: 18,
  icon: 19, spinner: 20,
  scene: 21,            // a content-agnostic 3D viewport (host-rendered)
}

pub const ATTR = {
  x: 0, y: 1, w: 2, h: 3, radius: 4, border_w: 5, fill: 6, border: 7, fg: 8,
  text_id: 9, image_id: 10, enabled: 11, checked: 12, selected: 13, group: 14,
  min: 15, max: 16, value: 17, z: 18, gap: 19, surface: 20, align: 21, pad: 22,
  value2: 23, peak: 24, peak2: 25, icon: 26, max_w: 27, min_w: 28,
  scene_id: 29,         // host scene-catalog id on a `scene` node (0 = turning cube)
}

pub const SURFACE = { none: 0, surface: 1, material: 2, material_thin: 3, scrim: 4 }
pub const ALIGN   = { start: 0, center: 1, end: 2, stretch: 3 }
pub const EVENT   = { press: 0, change: 1, input: 2 }
