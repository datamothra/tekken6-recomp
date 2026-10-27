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

## macOS

Apple Silicon Macs need macOS 13.3 or later, Intel Macs macOS 15 or later (on
older macOS the AMD graphics driver draws the characters black). You need your
own disc image of Tekken 6 for the Xbox 360, USA/Europe, Rev 1.

### Tekken 6 Builder

1. Unzip `Tekken 6 Builder.zip` and open `Tekken 6 Builder`. It isn't notarized,
   so the first time macOS refuses; go to System Settings > Privacy & Security
   and click Open Anyway.
2. Click Choose Disc Image and pick your `.iso`. If Apple's Command Line Tools
   are missing, it offers to install them.
3. It builds the game on your Mac (2 minutes on an M5 Max, longer on older Macs), puts `Tekken 6.app` in
   Applications and the game files in `~/Library/Application Support/Tekken 6`.

The builder contains this project's source, CMake and Ninja, but nothing from
the game. `tools/package_mac_builder.sh` makes it.

### Building from source

Needs the Xcode Command Line Tools and `brew install cmake ninja`.

```sh
tools/build_mac.sh --iso /path/to/Tekken6.iso   # --arch x86_64 builds the Intel version
tools/make_mac_app.sh --install                  # Tekken 6.app in /Applications
tools/run_mac.sh                                 # or start it from the terminal
```

### Game files

The first time the app opens it asks where the game is: a folder with the
disc's files (the one with `Default.xex`) is used where it is, and a disc image
is copied out to a folder you choose. Hold Option while opening the app to
choose again. Saves and the shader cache are in
`~/Library/Application Support/Tekken 6`. `TEKKEN6_DATA=<dir>` makes the app use
`<dir>/game`, `<dir>/user` and `<dir>/cache` instead, and `run_mac.sh --game DIR`
reads the game from `DIR`.

### Playing

Keyboard: Return is Start, Space A, Backspace B, L X, P Y, WASD the stick,
Shift+arrows the d-pad, 1 and 3 the shoulder buttons, Q and E the triggers. In a
fight L, P, ; and ' are 1, 2, 3 and 4. F3 shows the frame rate. Gamepads work.

The first launch shows a black screen for 10 to 20 seconds while shaders are
prepared. Fights run at about 60 fps on an M5 Max, with a few dropped frames a
minute. Laptops slow down on battery or a small charger.

`run_mac.sh` options: `--fullscreen`, `--res 768x432` for a lower 3D resolution,
`--log` to write a log to `logs/`. `--fsi` is faster but has visual glitches.

### Mac changes

All in the SDK patch:

- Two thread-timing bugs in the Xbox event emulation froze the first frame.
- Metal can't draw one primitive type the game uses; it is converted.
- A wrong value in the shader converter washed every scene out white.
- Graphics work is grouped into fewer passes (M1 Max: 21 fps before, 60 after).
- Frames are paced evenly against the display's refresh
  (`--vulkan_present_pacing=false` turns it off).
- Intel Macs bind resources without Metal argument buffers, which hung the AMD
  GPU.
- No white square where the Xbox shows the gamer picture.

`--execute_unclipped_draw_vs_on_cpu=true` (set by the launchers) is needed for
Practice mode and fights to render. After changing the shader converter, delete
`cache/`. If the game hangs, set `REX_DEBUG_DUMP_TRIGGER=/some/file` and create
that file to print what every thread is waiting on.

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
