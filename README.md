# Tekken 6 Recomp

Static recompiler project for the Xbox 360 release of Tekken 6. Game data and
generated code come from a user-provided XEX and are kept out of version control.

## Windows build

For a Linux-hosted Windows build, use an extracted LLVM-MinGW distribution.
Initialize the SDK submodule and apply the repository patch before configuring
the native SDK. Generate guest code from your own game XEX, then configure the
Windows build:

```sh
git submodule update --init --recursive
python3 tools/apply_rexglue_patches.py

cmake -S third_party/rexglue-sdk -B build/sdk-native -G Ninja \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS=-mssse3 \
  -DREXGLUE_ENABLE_TRACY=OFF -DREXGLUE_ENABLE_PERF_COUNTERS=OFF
cmake --build build/sdk-native --target rexglue --parallel 3
third_party/rexglue-sdk/out/linux-amd64/rexglue codegen tekken6_manifest.toml

cmake -S . -B build/windows-llvm -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=cmake/windows-clang.cmake \
  -DLLVM_MINGW_ROOT=/path/to/extracted/llvm-mingw \
  -DCMAKE_BUILD_TYPE=Release -DTEKKEN6_USE_PREGENERATED_CODE=ON \
  -DREXGLUE_USE_D3D12=ON -DREXGLUE_USE_VULKAN=ON \
  -DREXGLUE_ENABLE_TRACY=OFF -DREXGLUE_ENABLE_PERF_COUNTERS=OFF \
  -DREXGLUE_RECOMP_DEBUG_INFO=none
cmake --build build/windows-llvm --target tekken6 tekken6_low_overhead \
  tekken6_late_depth tekken6_fused_resolve tekken6_vulkan \
  tekken6_vulkan_fbo --parallel 2

python3 tools/package_windows.py --build-dir build/windows-llvm \
  --game-root /path/to/game --output /path/to/windows-package \
  --llvm-mingw-root /path/to/extracted/llvm-mingw
```

The package tool checks PE imports, stages required compiler runtime DLLs, and
writes a `build-info.json` manifest with source revisions and binary hashes.
SDK changes are maintained in the [project patch](patches/rexglue/README.md).
CMake defaults to `Release` when no build type is selected. Generated guest
code uses FMA3 by default for faster explicit fused operations; the resulting
executable requires an FMA3-capable CPU. Set `-DTEKKEN6_ENABLE_FMA3=OFF` for a
portable build.

## macOS build

Made for Apple Silicon Macs. Intel Macs are experimental: the build works, but
on the one Intel Mac tried so far (Radeon Pro 580, macOS 13) the game freezes at
the main menu after about half a minute.

You need the Xcode command line tools, `brew install cmake ninja`, and your own
Tekken 6 ISO.

```sh
tools/build_mac.sh --iso /path/to/your/Tekken6.iso   # builds it and copies the game into game/
tools/make_mac_app.sh --install                       # puts Tekken 6.app in /Applications
tools/run_mac.sh                                      # or start it from the terminal
```

The app and `run_mac.sh` share the game, saves and shader cache in this folder
(`game/`, `user/`, `cache/`). The app's icon is made from the artwork on your
disc, so no game art is stored here.

On an M5 Max fights run at a steady 60 fps. An M1 Max manages 60 most of the
time and drops the odd frame in busy moments. Keep a laptop on a proper charger;
on battery or a small charger it slows down.

The first launch shows a black screen for 10-20 seconds while it prepares its
shaders. After that it starts straight away. Shaders the game hasn't used before
are prepared in the background: the picture may hold for a moment, but the game
and its sound keep going together.

Motion is kept even: the game's 60 Hz clock follows the display, and it is
nudged so every frame reaches the screen at the same point of the display's
refresh, instead of some frames showing twice and others not at all.
`--vulkan_present_pacing=false` turns this off, and `TEKKEN6_PACING_LOG=<file>`
writes the frame timings for measuring.

Controls: a gamepad works, or the keyboard. Return is Start, Space is A,
Backspace is B, L is X, P is Y, WASD is the stick, Shift+arrows is the d-pad,
1 and 3 are the shoulder buttons, Q and E the triggers. F3 shows the frame rate.

`run_mac.sh` options: `--fullscreen`, `--res 768x432` for a lower 3D
resolution, `--fsi` for a faster mode that has visual glitches on the Mac, and
`--log` to keep a log in `logs/`.

What had to change for the Mac, all in the SDK patch:

- The game froze on its first frame, and sometimes at character select, because
  of two thread-timing bugs in how the SDK imitates the Xbox's events on macOS.
- The 3D scene was missing, because Metal can't draw one kind of shape
  the way the game asks for it.
- Every scene came out washed white, from a wrong value in the shader converter.
- The M1 Max ran at about 21 fps until the graphics work was regrouped into fewer
  passes per frame.
- A white square sat beside the player's name in fights, where the Xbox shows
  the gamer picture; with no profile picture it is now left empty.

`run_mac.sh` also turns on `--execute_unclipped_draw_vs_on_cpu=true`. Without it
Practice mode shows only the HUD and fights flash black.

For developers: after changing the shader converter, delete `cache/`. If the
game hangs, run it with `REX_DEBUG_DUMP_TRIGGER=/some/file` in the environment
and create that file; it prints what every game thread is waiting on.

## Portable ISO builder

The release can include a self-contained `Tekken 6 Builder.exe` beside its
`builder` folder. Players extract the complete release, choose their own ISO
with the Windows file picker, select one or more renderer checkboxes, and pick
an output folder. The D3D12 ROV option is checked by default and is labeled as
the widest-compatibility choice. No compiler installation or network access is
needed on the player's PC. The ISO and its game files are never included in the
builder release.

To assemble that release folder, first build the Windows GUI and XDVDFS helper,
then provide LLVM-MinGW 20260908 MSVCRT x64 (Clang 23.1.1), portable CMake,
Ninja, and the Python embeddable package. The bundled compiler's fixed
capabilities are supplied by `cmake/windows-portable-capabilities.cmake` so
players do not repeat the compiler feature probes.

```sh
cmake --build build/windows-llvm --target tekken6_builder xdvdfs_tool --parallel "$(nproc)"
python3 tools/package_portable_builder.py \
  --builder-exe build/windows-llvm/tekken6_builder.exe \
  --llvm-mingw-root /path/to/llvm-mingw \
  --cmake-root /path/to/cmake \
  --ninja /path/to/ninja.exe \
  --python-root /path/to/python-embeddable \
  --xdvdfs-tool build/windows-llvm/tools/xdvdfs/xdvdfs_tool.exe \
  --output build/Tekken6-Builder-Windows
```

Release versions are set in `VERSION.txt`; the builder window, Windows file details,
and package manifests use that version. For 0.9.4, archive the complete
`build/Tekken6-Builder-Windows` folder as `Tekken6-Builder-Windows-0.9.4.zip`.
Keep `Tekken 6 Builder.exe` and its `builder` folder together. The folder contains
the pinned project sources and build tools; the game itself is extracted from the player's
ISO when they run the builder. Project sources stay in one archive to reduce the
number of files in the initial unzip; the builder unpacks them automatically
when the first build starts.

Game compilation uses the available CPU threads, limited by available memory.
After a successful build, temporary sources, extracted game copies, and compiler
outputs are deleted automatically. The activity indicator keeps animating while
the build runs, and the Build button stays disabled after completion.

Press **F3** in game to show or hide the FPS and frame-time overlay. It reports
guest frame swaps independently of the host's overlay or presentation rate.
Routine logs are disabled in the Windows launcher. Unhandled crashes write
`crash.txt` and `crash.dmp` under `crashes/<run>/`.

The startup chooser offers internal 3D resolutions from 640x360 through the
original 1024x576. It also enables a 512x512 size for the 1024x1024 offscreen
target by default; this can soften shadows. Uncheck the option to keep the
original offscreen size.

## Rendering paths

`tekken6.exe` selects D3D12 ROV. The runtime includes no-blend shader
specialization, ROV sample-count variants, and direct RGBA8 packing for known
targets. Unsupported states retain the general shader path.
Late-depth and fused RGBA8 resolves are available through their optional
launchers.

`tekken6_vulkan.exe` selects Vulkan fragment shader interlock (FSI). It requires
a Vulkan device and driver that expose fragment shader interlock. The explicit
request fails if the extension is unavailable. `tekken6_vulkan_fbo.exe` selects
the experimental framebuffer path, which does not require interlock.

The launcher keeps user saves, shader caches, and crash reports in the package
directory. Game files and generated recompilation sources are local inputs and
must not be committed.
