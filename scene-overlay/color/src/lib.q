//! test.color — a one-function library qube.
//!
//! `random_color(seed)` turns an integer (here the live tap count) into a
//! packed QView color `0xAARRGGBB` (the format `qview.set_attr(node, fill, …)`
//! and ATTR.fg expect — see runtime/web-retained/protocol.js `unpackColor`).
//!
//! q64 cores are deterministic — there is no host RNG — so "random" is a small
//! integer hash (three independent linear-congruential mixes, one per channel).
//! Each channel is biased into [128, 255] so every colour is bright and visible
//! (never near-black) and consecutive seeds land on visibly different colours.
//!
//! This is a real, separate **library** qube. The `cube` app links it and calls
//! `random_color` from its tap handler (see ../main.q + ../qube.json5
//! `dependencies`). Scalar in, scalar out — exactly the canonical-ABI boundary a
//! qube link crosses.

/// A bright, opaque packed colour `0xFFRRGGBB` derived from `seed`.
pub fn random_color(seed: i64) -> i64 {
    // Per-channel hash, each into [128, 255]: bright, opaque, varied.
    let r = 128 + (seed * 2246822519 + 3266489917) % 128
    let g = 128 + (seed * 668265263  + 374761393)  % 128
    let b = 128 + (seed * 2654435761 + 40503)      % 128
    // Pack: alpha 255 (0xFF) << 24, then r << 16, g << 8, b — via arithmetic
    // (16777216 = 0x1000000, 65536 = 0x10000, 256 = 0x100).
    255 * 16777216 + r * 65536 + g * 256 + b
}
