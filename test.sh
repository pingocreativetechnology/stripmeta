#!/usr/bin/env bash
#
# Regression suite. Builds fixtures with real metadata, runs stripmeta,
# then verifies with an independent exiftool call that the tags are gone.
#
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SM="$here/stripmeta"
TMP="$here/test-tmp"
pass=0; fail=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; pass=$((pass+1)); }
no()   { printf '  \033[31m✗\033[0m %s\n' "$*"; fail=$((fail+1)); }
check(){ if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1 (expected '$3', got '$2')"; fi; }

command -v exiftool >/dev/null || { echo "exiftool required"; exit 1; }
command -v ffmpeg   >/dev/null || { echo "ffmpeg required to build fixtures"; exit 1; }

# Count identifying tags independently of the tool under test.
ident() {
  exiftool -a -G1 -s -e --System:all --File:all --ExifTool:all -- "$1" 2>/dev/null \
    | sed 's/^\[[^]]*\][[:space:]]*//' \
    | grep -Ec '^(GPS|Artist|Copyright|Software|Make|Model|SerialNumber|Comment|Title|Description|Location|Creator|Author)' \
    || true
}
xa() { xattr -- "$1" 2>/dev/null | grep -cv 'com.apple.provenance' || true; }

rm -rf "$TMP"; mkdir -p "$TMP"; cd "$TMP"

echo "building fixtures…"
printf 'hello world\n' > abc.txt
xattr -w com.apple.metadata:kMDItemWhereFroms 'https://secret.example.com/abc.txt' abc.txt 2>/dev/null
xattr -w com.apple.quarantine '0081;65d0f0a0;Safari;' abc.txt 2>/dev/null
touch -t 202001011200.00 abc.txt

ffmpeg -loglevel quiet -f lavfi -i color=c=red:s=64x64 -frames:v 1 -y photo.jpg
exiftool -q -overwrite_original -Artist="Jane Doe" -Copyright="ACME Corp" \
  -Software="Adobe Photoshop 2026" -Make="Canon" -Model="EOS R5" -SerialNumber="12345XYZ" \
  -GPSLatitude=-33.8688 -GPSLatitudeRef=S -GPSLongitude=151.2093 -GPSLongitudeRef=E \
  -XMP:Description="internal draft, do not share" photo.jpg
xattr -w com.apple.metadata:kMDItemWhereFroms 'https://example.com/photo.jpg' photo.jpg 2>/dev/null

ffmpeg -loglevel quiet -f lavfi -i color=c=blue:s=64x64 -frames:v 12 \
  -metadata title="Confidential Cut" -metadata artist="Pingo" \
  -metadata comment="do not distribute" -metadata location="-33.8688+151.2093/" -y clip.mov

echo
echo "fixtures carry metadata:"
check "photo.jpg has identifying tags" "$([[ $(ident photo.jpg) -gt 0 ]] && echo yes || echo no)" "yes"
check "clip.mov has identifying tags"  "$([[ $(ident clip.mov)  -gt 0 ]] && echo yes || echo no)" "yes"
check "abc.txt has extended attrs"     "$([[ $(xa abc.txt)      -gt 0 ]] && echo yes || echo no)" "yes"

echo
echo "copy mode:"
"$SM" -q photo.jpg; check "photo.jpg exits 0" "$?" "0"
check "photo_clean.jpg identifying == 0" "$(ident photo_clean.jpg)" "0"
check "photo_clean.jpg xattrs == 0"      "$(xa photo_clean.jpg)"    "0"
check "original photo.jpg untouched"     "$([[ $(ident photo.jpg) -gt 0 ]] && echo yes || echo no)" "yes"

"$SM" -q abc.txt; check "abc.txt exits 0" "$?" "0"
check "abc_clean.txt xattrs == 0" "$(xa abc_clean.txt)" "0"
cmp -s abc.txt abc_clean.txt && ok "abc_clean.txt bytes identical" || no "abc.txt contents changed"

"$SM" -q clip.mov; check "clip.mov exits 0" "$?" "0"
check "clip_clean.mov identifying == 0" "$(ident clip_clean.mov)" "0"
# decode every frame; ffmpeg (not ffprobe) is what supports -f null
ffmpeg -v error -i clip_clean.mov -f null - 2>/dev/null && ok "clip_clean.mov decodes cleanly" \
                                                        || no "clip_clean.mov is corrupt"
check "clip_clean.mov frame count preserved" \
  "$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 clip_clean.mov)" \
  "$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 clip.mov)"

echo
echo "no-clobber:"
"$SM" -q photo.jpg
[[ -f photo_clean-2.jpg ]] && ok "second run wrote photo_clean-2.jpg" || no "no-clobber failed"

echo
echo "inplace mode:"
cp photo.jpg inp.jpg
"$SM" -q -i inp.jpg; check "inplace exits 0" "$?" "0"
check "inp.jpg identifying == 0" "$(ident inp.jpg)" "0"
[[ -e inp.jpg_original ]] && no "left an exiftool backup file" || ok "no .jpg_original backup left"

echo
echo "flags:"
"$SM" -q -k -o kept.txt abc.txt
check "--keep-date preserved mtime" "$(date -r kept.txt +%Y)" "$(date -r abc.txt +%Y)"
"$SM" -n photo.jpg >/dev/null 2>&1; check "--dry-run exits 0" "$?" "0"
[[ -e photo_clean-3.jpg ]] && no "--dry-run wrote a file" || ok "--dry-run changed nothing"
"$SM" -l photo.jpg >/dev/null 2>&1; check "--list exits 0" "$?" "0"

echo
echo "errors:"
"$SM" -q nope.txt >/dev/null 2>&1; check "missing file exits 1" "$?" "1"
"$SM" --bogus x   >/dev/null 2>&1; check "unknown flag exits 1"  "$?" "1"
"$SM" -o a -i b   >/dev/null 2>&1; check "conflicting flags exit 1" "$?" "1"
"$SM" -o x.jpg photo.jpg clip.mov >/dev/null 2>&1; check "--out with 2 inputs exits 1" "$?" "1"

echo
echo "filenames with spaces:"
cp photo.jpg "my holiday photo.jpg"
"$SM" -q "my holiday photo.jpg"; check "spaces exit 0" "$?" "0"
check "spaced output clean" "$(ident "my holiday photo_clean.jpg")" "0"

cd "$here"; rm -rf "$TMP"
echo
printf '\033[1m%d passed, %d failed\033[0m\n' "$pass" "$fail"
exit $(( fail > 0 ))
