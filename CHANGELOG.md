# Changelog

## 1.0.0

Initial release.

- Strips embedded metadata via exiftool, macOS extended attributes, and the
  filesystem modification time.
- Copy-by-default; `--inplace` to overwrite, `--out` for an explicit name.
- `--list` and `--dry-run` to inspect before changing anything.
- Verifies its own output: distinguishes identifying tags from structural
  ones, and exits non-zero if anything identifying survives.
