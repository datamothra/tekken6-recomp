#!/bin/zsh
# Package an already-built macOS host (tools/build_mac.sh) as "Tekken 6.app".
#
#   tools/make_mac_app.sh                  # -> build/mac-<arch>/Tekken 6.app
#   tools/make_mac_app.sh --install        # ...and copy it to /Applications
#   tools/make_mac_app.sh --data-root DIR  # where game/, user/ and cache/ live on this Mac (default: this checkout)
#   tools/make_mac_app.sh --build-dir DIR
#
# The bundle holds the host, its two dylibs, the pinned Vulkan loader and
# MoltenVK, and the ISO extractor; the game data stays outside it (6+ GB). On the
# Mac that built it the app uses the data root, so saves and the shader cache are
# the same ones tools/run_mac.sh uses. On any other Mac it keeps the game, saves
# and cache in ~/Library/Application Support/Tekken 6, and the first launch asks
# for that person's own disc image (or a copy of the disc) and sets it up there.
# The launcher passes run_mac.sh's default settings. The icon is made from the
# disc's own dashboard art (tools/mac_icon.py), so no game art is stored in the repo.
set -euo pipefail

root="${0:A:h:h}"
arch="$(uname -m)"
[[ "$arch" == arm64 ]] && platform=mac-arm64 || platform=mac-amd64
build_dir="$root/build/$platform"
data_root="$root"
install=false

while (( $# )); do
  case "$1" in
    --install) install=true; shift ;;
    --data-root) data_root="${2:A}"; shift 2 ;;
    --build-dir) build_dir="${2:A}"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -x "$build_dir/tekken6" ]] || { echo "missing $build_dir/tekken6; run tools/build_mac.sh first" >&2; exit 1; }
[[ -f "$data_root/game/Default.xex" || -f "$data_root/game/default.xex" ]] || { echo "missing $data_root/game/Default.xex" >&2; exit 1; }

app="$build_dir/Tekken 6.app"
contents="$app/Contents"
rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"

# The GPU plugin is looked up next to the executable and the runtime through
# @executable_path, so all three sit in MacOS/. The SDK finds the loader and
# MoltenVK under Contents/Resources/vulkan.
cp "$build_dir/tekken6" "$build_dir/librexruntime.dylib" "$build_dir/librexgpu-xenos.dylib" "$build_dir/tools/xdvdfs/xdvdfs_tool" "$contents/MacOS/"
cp -R "$build_dir/vulkan" "$contents/Resources/vulkan"
print -r -- "$data_root" > "$contents/Resources/data-root"
# the code is recompiled from this exact Default.xex: another disc's would crash it
xex="$data_root/game/Default.xex"; [[ -f "$xex" ]] || xex="$data_root/game/default.xex"
shasum "$xex" | cut -d' ' -f1 > "$contents/Resources/xex-sha1"

cat > "$contents/MacOS/launch" <<'EOF'
#!/bin/zsh
# Where the game is: $TEKKEN6_DATA, else the folder the app was built from (on the
# Mac that built it), else ~/Library/Application Support/Tekken 6. With none, the
# person's own disc image (.iso) or a copy of the disc (its Default.xex) is asked
# for once and set up in Application Support: an image is copied out (6.6 GB, about
# a minute), a copy is linked where it is. Then the same settings as
# tools/run_mac.sh with no options; exec keeps this process, so the Dock shows the
# app rather than a separate tekken6 binary.
#   TEKKEN6_SOURCE=<iso or Default.xex>  answers the question without the dialog
#   TEKKEN6_PREPARE_ONLY=1               sets the game up and stops before starting it
here="${0:A:h}"
res="$here/../Resources"
support="$HOME/Library/Application Support/Tekken 6"
has_game() { [[ -f "$1/game/Default.xex" || -f "$1/game/default.xex" ]] }
alert() { [[ -n "${TEKKEN6_SOURCE:-}" ]] && print -u2 -- "$1" || osascript -e "display alert \"Tekken 6\" message \"$1\"" >/dev/null }
right_xex() { [[ "$(shasum "$1" | cut -d' ' -f1)" == "$(<"$res/xex-sha1")" ]] }
wrong="That isn't the Tekken 6 this app was made from (Tekken 6 for the Xbox 360, USA/Europe, Rev 1)."

data_root=""
for d in "${TEKKEN6_DATA:-}" "$(<"$res/data-root")" "$support"; do
  [[ -n "$d" ]] && has_game "$d" && { data_root="$d"; break; }
done

if [[ -z "$data_root" ]]; then
  data_root="$support"
  src="${TEKKEN6_SOURCE:-}"
  if [[ -z "$src" ]]; then
    # a file dragged from Finder onto this window picks it
    src="$(osascript -e 'POSIX path of (choose file with prompt "Drag your Tekken 6 disc image (.iso) here, or Default.xex from a copy of the disc." of type {"iso", "xex", "public.disk-image"})' 2>/dev/null)" || exit 0
  fi
  [[ -f "$src" ]] || { alert "Can't find $src."; exit 1; }
  mkdir -p "$support" || { alert "Can't write $support."; exit 1; }
  if [[ "${src:l}" == *.xex ]]; then
    right_xex "$src" || { alert "$wrong"; exit 1; }
    rm -rf "$support/game"; ln -s "${src:A:h}" "$support/game"
  else
    tmp="$support/game.part"; rm -rf "$tmp"; mkdir -p "$tmp"
    "$here/xdvdfs_tool" extract "$src" Default.xex "$tmp/Default.xex" >/dev/null 2>&1 || { rm -rf "$tmp"; alert "Can't read $src as an Xbox 360 disc image."; exit 1; }
    right_xex "$tmp/Default.xex" || { rm -rf "$tmp"; alert "$wrong"; exit 1; }
    rm "$tmp/Default.xex"
    [[ -n "${TEKKEN6_SOURCE:-}" ]] || osascript -e 'display notification "Copying the game from your disc image (about a minute)" with title "Tekken 6"' >/dev/null
    "$here/xdvdfs_tool" extract-all "$src" "$tmp" >/dev/null 2>&1 || true
    [[ -f "$tmp/Default.xex" || -f "$tmp/default.xex" ]] || { rm -rf "$tmp"; alert "Copying from $src failed (is there 7 GB free?)."; exit 1; }
    rm -rf "$support/game"; mv "$tmp" "$support/game"
  fi
fi
[[ -n "${TEKKEN6_PREPARE_ONLY:-}" ]] && { print -- "$data_root"; exit 0; }

mkdir -p "$data_root/user" "$data_root/cache/fbo"
export TEKKEN6_YIELD_STARTUP_SPIN=1
exec "$here/tekken6" \
  --game_data_root="$data_root/game" \
  --user_data_root="$data_root/user" \
  --cache_root="$data_root/cache/fbo" \
  --fullscreen=false \
  --log_file=/dev/null --log_level=off \
  --gpu_backend=vulkan --render_target_path_vulkan=fbo \
  --async_shader_compilation=true --anisotropic_override=0 \
  --execute_unclipped_draw_vs_on_cpu=true \
  --mnk_mode=true \
  "$@"
EOF
chmod +x "$contents/MacOS/launch"

cat > "$contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Tekken 6</string>
  <key>CFBundleDisplayName</key><string>Tekken 6</string>
  <key>CFBundleIdentifier</key><string>com.tekken6recomp.mac</string>
  <key>CFBundleExecutable</key><string>launch</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.action-games</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>GCSupportsControllerUserInteraction</key><true/>
</dict>
</plist>
EOF

icon_tmp="$(mktemp -d)"
trap 'rm -rf "$icon_tmp"' EXIT
python3 "$root/tools/mac_icon.py" "$data_root/game/nxeart" "$icon_tmp/icon.png"
mkdir "$icon_tmp/AppIcon.iconset"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz "$icon_tmp/icon.png" --out "$icon_tmp/AppIcon.iconset/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz * 2)) $((sz * 2)) "$icon_tmp/icon.png" --out "$icon_tmp/AppIcon.iconset/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$icon_tmp/AppIcon.iconset" -o "$contents/Resources/AppIcon.icns"

# Ad-hoc sign the nested code first, then the bundle.
for f in "$contents"/MacOS/*.dylib "$contents"/Resources/vulkan/lib/*.dylib "$contents/MacOS/tekken6" "$contents/MacOS/xdvdfs_tool"; do
  codesign --force --sign - "$f" 2>/dev/null
done
codesign --force --sign - "$app" 2>/dev/null
echo "Built: $app"

if $install; then
  rm -rf "/Applications/Tekken 6.app"
  cp -R "$app" /Applications/
  touch "/Applications/Tekken 6.app"
  echo "Installed: /Applications/Tekken 6.app"
fi
