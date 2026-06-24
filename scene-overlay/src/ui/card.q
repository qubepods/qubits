//! src/ui/card.q — a frosted container (a registry component; copy-and-own).
//!
//! A centered `column` carrying a theme-resolved material surface, so a caller
//! gets the per-platform frosted look (iOS / Material / desktop) without naming a
//! color. Returns the node id so callers parent children (labels, buttons) under
//! it; the column arranges them centered with the theme's spacing.

use q64.view.{ Ctx }
use ui.proto.{ KIND, ATTR, SURFACE, ALIGN }

/// A frosted card. `c` allocates ids and holds the theme tokens.
pub fn card(c: Ctx, parent: i64) -> i64 {
  let id = c.next()
  qview.create(id, KIND.column, parent)
  qview.set_attr(id, ATTR.surface, SURFACE.material)   // theme-resolved, not a literal color
  qview.set_attr(id, ATTR.radius,  c.theme.radius)
  qview.set_attr(id, ATTR.align,   ALIGN.center)
  qview.set_attr(id, ATTR.pad,     c.theme.space_4)
  qview.set_attr(id, ATTR.gap,     c.theme.space_2)
  return id
}
