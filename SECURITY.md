# Security Policy — Plush - Soft Form Studio

## Supported versions

| Version | Supported |
| --- | --- |
| 2.0.x | Yes |
| 1.x (legacy "Soft Edges") | Activation kept working, no new patches |

## Reporting a vulnerability

Email **security@archinsights.com** with:

1. The plugin version (`Plush …` in the About tab).
2. SketchUp version.
3. Steps or a minimal repro.

You will get an initial reply inside 72 hours. Please give us 30 days to patch
before public disclosure.

## Design notes

- **License keys** are validated locally against a salted digest and bound to a
  machine fingerprint. Keys must only be issued by the private generator; that
  file must never be committed or shared. It is excluded by `.gitignore`.
- **The updater** verifies every downloaded package with a SHA-256 digest from
  the release manifest, and ignores versions you told it to skip.
- **No telemetry.** Network access is limited to the configured release feed
  and, on your action, the package download.
- Generated model groups are sandboxed inside named containers (`Plush *`) and
  each operation runs in an undoable SketchUp operation, so a failed pass can
  abort cleanly without tearing the model.

## Verifying a download

The Updates tab shows the package location after download; the release
manifest carries `size` and `sha256`:

```powershell
Get-FileHash .\Downloads\Plush-2.0.0.rbz -Algorithm SHA256
# compare with release.json -> sha256
```
