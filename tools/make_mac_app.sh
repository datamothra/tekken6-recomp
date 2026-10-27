#!/bin/zsh
# Package an already-built macOS host (tools/build_mac.sh) as "Tekken 6.app".
#
#   tools/make_mac_app.sh                  # -> build/mac-<arch>/Tekken 6.app
#   tools/make_mac_app.sh --install        # ...and copy it to /Applications
#   tools/make_mac_app.sh --data-root DIR  # where game/, user/ and cache/ live (default: this checkout)
#   tools/make_mac_app.sh --build-dir DIR
#
# The bundle holds the host, its two dylibs and the pinned Vulkan loader and
# MoltenVK; the game data stays outside it (6+ GB) in the data root, so saves and
# the shader cache are the same ones tools/run_mac.sh uses. The launcher passes
# run_mac.sh's default settings. The icon is made from the disc's own dashboard
# art (tools/mac_icon.py), so no game art is stored in the repo.
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
cp "$build_dir/tekken6" "$build_dir/librexruntime.dylib" "$build_dir/librexgpu-xenos.dylib" "$contents/MacOS/"
cp -R "$build_dir/vulkan" "$contents/Resources/vulkan"
print -r -- "$data_root" > "$contents/Resources/data-root"

cat > "$contents/MacOS/launch" <<'EOF'
#!/bin/zsh
# Same settings as tools/run_mac.sh with no options. exec keeps this process, so
# the Dock shows the app rather than a separate tekken6 binary.
here="${0:A:h}"
data_root="$(<"$here/../Resources/data-root")"
if [[ ! -f "$data_root/game/Default.xex" && ! -f "$data_root/game/default.xex" ]]; then
  osascript -e "display alert \"Tekken 6\" message \"No game data in $data_root/game.\"" >/dev/null
  exit 1
fi
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
for f in "$contents"/MacOS/*.dylib "$contents"/Resources/vulkan/lib/*.dylib "$contents/MacOS/tekken6"; do
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
