# Changelog — Plush - Soft Form Studio

All notable changes to Plush are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions echo
[Semantic Versioning](https://semver.org/).

## [2.0.0] — 2026-11-05

**Plush** is the rebuilt, renamed and re-imagined second generation of the
ArchInsights Soft Edges tool. Users of the previous build keep their activated
license — activation state, keys and the validation algorithm are unchanged.

### Added
- **Plush brand**: new name, new gradient mark, new toolbar icon set (PNG + @2x),
  and a full warm cream & rose UI with icon rail, unit segmented control,
  update banners, toasts and a combined License / Updates / About modal.
- **Fabric engine v2**: catenary seam sag, piping/welt crests, dog-ear corner
  pleats, seeded organic wrinkles with envelope control, plateau-raised dome
  rings and a flat apex cap (no more apex pinch).
- **Rest-on-surface** pillow mode — the bottom dome compresses like cloth under
  gravity.
- **Mattress Maker** — straight corners, side bulge, welt, bilinear quilt cap
  (grid / diamond / waves) matched per-edge to the side ring sampling, tufting
  craters, Pillow-Top and Euro-Top layered toppers.
- **Cushion Maker** with hidden top welt stitching.
- **Fabric Drape** — falling cloth skirts with flared hems, hem wobble and
  corner sag; the base face survives.
- **Curved Wall** — bulge / S-curve / wave sweeps along faces or chained edges.
- **Ceiling Curve** — cove, crown and scallop fillets between walls and ceiling.
- **Openings** — rectangular or circular through-cut window and punctuation
  openings with soft corners and jamb strips.
- **Curved Push/Pull**, **Loft Surface** (ruled + smooth ease), **Pipe & Tube**
  (solid or hollow), rebuilt **Soften Corners** with vertex-index bookkeeping.
- **Full metric + imperial unit control**: mm / cm / m / in / ft plus Auto
  (model units), per-field suffix overrides (`2in` works inside a metric plan).
- **Automatic updates** — background release-feed polling, download with
  SHA-256 integrity checking, size and version comparison, per-version
  "remind me later" and a saved-package installer handoff.
- **State persistence** — every slider, chip, swatch, seed and unit choice is
  remembered between sessions.
- Headless test harness (`tests/`) for the pure geometry, the release-feed
  parser and the UI↔Ruby callback contract.

### Changed
- Module renamed from `Archinsights::SoftEdges` heritage to
  `Archinsights::Plush`; preferences live under `com.archinsights.plush.*`
  while legacy license storage (`com.archinsights.softedges.v3`) is preserved
  for continuity.
- Geometry grouping: every generated object lands in a named group
  (`Plush Pillow`, `Plush Mattress`, …) so models stay organised.
- The cutting tools now erase the source face before laying meshes, which
  removes the broken `intersect_with` behaviour of the previous build.

### Fixed
- The cutout tool from the previous build called `intersect_with` with the wrong
  argument order and produced nothing; openings now cut cleanly through.
- "Smooth loft" option previously did nothing; it now applies a smoothstep
  easing between loops.
- Unit-unaware sliders and text fields — all inputs are now unit-aware end to
  end.
- Corners are validated and clamped to the reference length ratio so arcs no
  longer explode on small geometry.
