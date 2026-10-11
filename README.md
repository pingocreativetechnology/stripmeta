# stripmeta

Remove metadata from a file. One command, no config.

```
stripmeta abc.txt
```

Most "metadata removers" clean the tags *inside* a file and stop there. On
macOS that leaves the download URL, the Finder tags, the quarantine flag and
the original timestamp sitting right next to it in the filesystem. `stripmeta`
removes all three layers, then re-reads the result and tells you what actually
came off.

## Install

Requires [exiftool](https://exiftool.org).

```sh
brew install exiftool          # macOS
# sudo apt install libimage-exiftool-perl   # Debian/Ubuntu

git clone https://github.com/pingocreativetechnology/stripmeta.git
cd stripmeta && ./install.sh
```

`install.sh` symlinks the script into `~/.local/bin` (or `/usr/local/bin`), so
`stripmeta` works from any directory. To uninstall, delete the symlink.

## Usage

```
stripmeta [options] FILE [FILE...]

  -i, --inplace     Overwrite the original instead of writing a copy.
  -o, --out FILE    Write the cleaned result to FILE (single input only).
  -k, --keep-date   Preserve the filesystem modification time.
  -l, --list        Show all metadata found. Change nothing.
  -n, --dry-run     Show what would be removed. Change nothing.
  -q, --quiet       Only print errors.
  -h, --help        Show help.
  -V, --version     Print version.
```

By default nothing is overwritten — you get a cleaned copy beside the original:

```
$ stripmeta photo.jpg
photo.jpg
  -> ./photo_clean.jpg
  clean  (removed 24 tag(s), 1 xattr(s))
```

Run it twice and you get `photo_clean-2.jpg`; it never clobbers an existing
file. Pass `--inplace` when you want the original scrubbed directly, with no
`.jpg_original` backup left behind.

## Examples

```sh
stripmeta abc.txt                 # -> abc_clean.txt
stripmeta --inplace photo.jpg     # scrub the original, no copy
stripmeta --list report.pdf       # just show me what's in there
stripmeta -n *.jpg                # dry run across a folder
stripmeta -o clean.mov raw.mov    # explicit output name
stripmeta ~/Desktop/*.png         # several files at once
```

Look before you leap:

```
$ stripmeta --dry-run clip.mov
clip.mov
  would remove: 60 embedded tag(s) (5 identifying), 0 extended attribute(s)
  would reset:  filesystem modification time
  target:       a cleaned copy
  identifying:
    · Artist            : Pingo
    · Title             : Confidential Cut
    · SoftwareVersion   : Lavf61.7.100
    · Comment           : do not distribute
    · GPSCoordinates    : 33 deg 52' 7.68" S, 151 deg 12' 33.48" E
```

## What gets removed

| Layer | Examples |
|---|---|
| **Embedded tags** | EXIF, XMP, IPTC, GPS coordinates, QuickTime atoms, ID3, PDF Info dictionary, Office document properties, embedded thumbnails, ICC profiles |
| **Extended attributes** | Finder tags and comments, `com.apple.quarantine` (which app downloaded it), `kMDItemWhereFroms` (the source URL), resource forks |
| **Filesystem mtime** | Reset to now, unless `--keep-date` |

### What necessarily stays

Structural properties are part of the file format and cannot be removed
without re-encoding: image dimensions, video duration, frame rate, codec,
colour depth. `stripmeta` reports these separately rather than pretending
they're gone.

```
clip.mov
  -> ./clip_clean.mov
  clean  (removed 6 tag(s), 0 xattr(s))
  54 structural tag(s) remain — dimensions, duration, codec
```

Two caveats worth knowing:

- **Encoder fingerprint in video containers.** A MOV/MP4 keeps its
  `CompressorName` / `VendorID` (e.g. `libx264`, `FFmpeg`). That identifies
  the encoder, not you. If you need it gone, remux — this rewrites the whole
  file, so expect it to take a while on large ones:
  ```sh
  ffmpeg -i clip.mov -map_metadata -1 -c copy clip_bare.mov
  ```
- **`com.apple.provenance`.** macOS 14+ sets a protected extended attribute
  that userland cannot delete. It records no user data, so `stripmeta` ignores
  it rather than failing.

### Plain text files

A `.txt` has no embedded metadata to strip — exiftool can't write the format
and doesn't need to. What `stripmeta` cleans on a text file is the layer
around it: extended attributes and the timestamp. That's the layer that
actually leaks, and it's the one most tools skip.

```
$ stripmeta abc.txt
abc.txt
  -> ./abc_clean.txt
  clean  (removed 0 tag(s), 2 xattr(s))
```

The two attributes removed there were the Safari quarantine flag and the URL
the file was downloaded from. File contents are byte-identical.

## Verification

`stripmeta` doesn't trust the strip — it re-reads the output afterwards and
compares. Tags are classed as **identifying** (people, places, devices,
organisations) or **structural** (how the file is put together). Identifying
tags surviving means failure:

```
$ echo $?
0    # clean
1    # something identifying survived, or the file couldn't be read
```

That makes it safe in a pipeline: `stripmeta -q -i out.jpg && upload out.jpg`

## Tests

```sh
./test.sh
```

Builds fixtures with real GPS, author and device tags, runs the tool, then
verifies with an independent `exiftool` call that they're gone.

## Why not just `exiftool -all=`?

That's the engine underneath, and for a single image it's most of the job. The
gap: it doesn't touch extended attributes, it leaves `.jpg_original` files
lying around, it errors out on formats it can't write even when there was
nothing to strip, and it doesn't check its own work. `stripmeta` closes those
gaps and gives you a copy-by-default workflow that's hard to lose data with.

## License

MIT © [Pingo Creative Technology](https://www.pingocreativetechnology.com)
