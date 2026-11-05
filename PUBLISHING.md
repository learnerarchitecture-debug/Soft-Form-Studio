# Publishing guide — Plush - Soft Form Studio

One page, zero ceremony. Every release is: **bump → build → commit → push**.
The plugin itself checks `release.json` at the repository root and downloads
`packages/Plush-x.y.z.rbz`.

## 1. Bump the version

`archinsights_plush.rb`:

```ruby
PRODUCT  = 'Plush - Soft Form Studio'
VERSION  = '2.0.0'   # -> '2.0.1'
```

`CHANGELOG.md` gets a matching entry.

## 2. Build the package + manifest

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_rbz.ps1
```

- Writes `packages/Plush-<version>.rbz`
- Writes `release.json` at the repo root with:
  - `version`
  - `download_url` (raw file URL of the package)
  - `notes` (edit the `notes` field in `tools/build_rbz.ps1` per release)
  - `released_at`
  - `size` (bytes)
  - `sha256` (integrity digest checked by the updater)

Re-run with `-Version 2.0.1` to override the detected version.

## 3. Commit and push

```bash
git add -A
git commit -m "release: Plush 2.0.1"
git push origin main
```

`packages/*.rbz` **is** committed (that is the download URL the feed points to),
while `license_generator.html` and `_legacy_v1/` never leave the machine
(`.gitignore`).

## 4. Verify the feed

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/learnerarchitecture-debug/Soft-Form-Studio/main/release.json
```

`version` must differ from the running `Plush::VERSION` for the update banner
to appear inside the dialog. Older users just start SketchUp and see
"A softer update is ready" within the first minutes.

## 5. Extension Warehouse

`archinsights_plush.rb` already registers a `Sketchup::Extension` with version,
creator and copyright metadata required by review. On the review form, provide
the `packages/Plush-<version>.rbz` from this repository as the uploaded file,
the README.md as listing copy and the EULA.md as license terms.

## Update feed contract

`release.json`:

```json
{
  "version":      "2.0.1",
  "download_url": "https://.../packages/Plush-2.0.1.rbz",
  "notes":        "What changed, one sentence",
  "released_at":  "2026-11-05",
  "size":         74555,
  "sha256":       "d3445d0f..."
}
```

- `version` — three-part tuple, compared numerically.
- `download_url` — the package for this exact version.
- `size`, `sha256` — optional but **strongly recommended**; the updater refuses
  to open a package that fails the digest.
- The feed URL is user-configurable; the default points at this repository.
