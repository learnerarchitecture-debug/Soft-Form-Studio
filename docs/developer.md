<div align="center">

<!-- Screenshot banner slot: replace with a real view catch when available -->

**Plush — Soft Form Studio · Developer docs**

</div>

---

## Update feed

The updater reads one small JSON file:

| Key | Meaning |
| --- | --- |
| `version` | newest published build, compared as a numeric tuple |
| `download_url` | direct file link to the matching `.rbz` |
| `notes` | shown inside the update banner |
| `released_at` | display date |
| `size` | expected byte length (optional) |
| `sha256` | integrity digest (optional but recommended) |

Behaviour:

- A **background poll** runs shortly after startup and repeats at most hourly;
  failures are silent (status console only).
- **Check now** reports "latest" or raises the banner with notes.
- **Get it** downloads to the user's `Downloads` folder, verifies the
  SHA-256 digest, and hands the file to the operating system - which routes it
  to the installed editor's extension installer prompt.
- **Later** stores the version under `com.archinsights.plush.update.ignored`
  until the feed moves past it.

Prefs (all overridable, all live in the registry-backed XML):

| Pref | Key |
| --- | --- |
| Feed URL | `com.archinsights.plush.update.feed` |
| Auto check | `com.archinsights.plush.update.auto` |
| Last check | `com.archinsights.plush.update.last_check` |
| Ignored version | `com.archinsights.plush.update.ignored` |

## Licensing

- Keys are `YYYYMMDD-AAAA-BBBB-CCCC`; the triple is
  `SHA256(email.lower | YYYYMMDD | SALT)` slices upper-cased.
- Validity requires: 4 segments, 8-digit expiry, future expiry, digest match,
  and a stored machine fingerprint equal to the current one.
- **Storage keys:** legacy `com.archinsights.softedges.v3` (unchanged algorithm
  = existing customers keep working), new UI state under
  `com.archinsights.plush.state`.
- The generator tool that mints keys holds the salt and stays **local-only**
  (gitignored). Losing it is recoverable; leaking it is a key for everyone.

## Architecture (developer's map)

```
main.rb ─────────────┐
  - HtmlDialog       │  owns license state, update prefs, ops
  - callbacks        ▼
                 apply_pillow / mattress / cushion / drape / wall / ceiling
                 pushpull / opening / loft / pipe / batch soften
                      │
      ┌───────────────┴───────────────┐
fabric_engine.rb              curves.rb
  rest/floating pillows        corners, walls, ceilings
  mattress side rings +        push/pull, openings, lofts,
  quilt grid, tuft craters     pipes, bulk edge passes
  drape skirts                 │
      │                        │
      └────► core_geometry.rb ◄────┘
              pure math: rng, catenary, ring_scale, wrinkle
              harmonics, resample, winding, corner data,
              cove/crown profiles, annulus rays, quilt field,
              version tuple
updater.rb        feed → download → sha256 → tell UI
```

**Rules that keep SketchUp stable here**

- Undoable: every mutating op runs inside `start_operation('Plush …', true)`.
- Groups: outputs land in named groups (`Plush *`), never as scattered edges.
- Meshes: `add_faces_from_mesh` + explicit edge soft/smooth pass - cheaper than
  hand-lofting and review-friendly.
- Ruby 2.2 compatible core (no `&.`, no `sum`, no `clamp`) so olders SketchUps
  still parse the files.

## Tests

```powershell
ruby tests\run_all.rb
```

A headless double of the SketchUp/Geom surface (`tests/support/sketchup_stub.rb`)
loads `main.rb` through the extension registration path, then exercises:

1. the pure math (catenary, ring scale, wrinkle envelope, resample, winding,
   quilt field, version tuples),
2. the release manifest parser and ignore-list prefs,
3. the UI ↔ Ruby callback contract (every `sketchup.*` call in the UI must have
   a registered action callback, every `execute_script` entry point must exist
   in `ui.js`, every icon must exist),
4. the toolbar icon names vs `main.rb` TOOLS table.

Suite output is `PASS/FAIL <name>` lines with a summary and a non-zero exit
code on failure.
