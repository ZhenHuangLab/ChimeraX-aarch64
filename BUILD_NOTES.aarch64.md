# UCSF ChimeraX — Linux aarch64 (DGX Spark, GB10)

## Result: 🟢 PASS — built from source, **1 upstream fix**

UCSF ChimeraX publishes **no ARM64 Linux binary anywhere**: it is not on
Flathub (`App not found`), every download-site URL 404s, and the Toolshed has no
Linux ARM64 bundles. But RBVI *do* keep an ARM build manifest in the develop
branch — `arm-flatpak.yml` — which nobody appears to have shipped from. This is
that build, plus the one fix it needed.

- **Upstream commit:** `d8e4a0c` (develop, 2026-08-28)
- **Built version:** `1.13.dev202608282219`
- **Runtime:** `org.freedesktop.Platform//24.08` aarch64
  (`freedesktop-sdk-24.08.36`)
- **Bundle:** `dist/ChimeraX-1.13.dev202608282219-linux-aarch64.flatpak` (383 MB)

## Why the manifest works where a normal install cannot

```yaml
build-commands:
  - NO_PREBUILT=1 FLATPAK_DIST=24.08 ... make -j$(nproc) install-rbvi
```

`NO_PREBUILT=1` tells the build **not** to fetch the prebuilt x86 prerequisite
archives from `cxtoolshed.rbvi.ucsf.edu/prereqs`, and to compile the whole stack
from source instead — CPython 3.14, Qt6, numpy, everything. That is exactly what
an ARM64 build needs, and it is why this succeeds without touching any C++.

## The fix: `lib64` vs `lib`

The first build compiled cleanly but failed its own test suite:

```text
tests/test_imports_wheel.py::test_imports[chimerax.ui.widgets.htmlview] FAILED
E   ImportError: cannot import name 'ChimeraXHtmlView' from 'chimerax.ui.widgets'
E       ImportError: libsnappy.so.1: cannot open shared object file: No such file or directory
================== 2 failed, 1073 passed ==================
```

Both failures trace to one cause. The manifest builds **snappy** and **minizip**
with `buildsystem: cmake-ninja`, and on aarch64 CMake's `GNUInstallDirs` defaults
`CMAKE_INSTALL_LIBDIR` to `lib64`:

```text
/app/lib64/libsnappy.so.1
/app/lib64/libminizip.so.1
```

The flatpak runtime only searches `/app/lib`, so Qt WebEngine cannot resolve
`libsnappy.so.1`, which takes `ChimeraXHtmlView` down with it. (Upstream clearly
hit something in this area before — the snappy module still carries a
commented-out `#- -DCMAKE_INSTALL_PREFIX=/app`.)

Fix — pin the libdir on both cmake modules in `arm-flatpak.yml`:

```yaml
  - name: libsnappy
    config-opts:
      ...
      - -DCMAKE_INSTALL_LIBDIR=lib

  - name: libminzip
    config-opts:
      ...
      - -DCMAKE_INSTALL_LIBDIR=lib
```

After this `/app/lib64` is empty and every test passes:

```text
======================= 1075 passed, 3 warnings =======================
======================= 1190 passed, 3 warnings =======================
====================== 94 passed, 1 deselected in 46.62s ==============
```

This is a genuine aarch64-only defect in the upstream manifest — worth sending
back to RBVI.

## Build

```bash
sudo apt install flatpak flatpak-builder
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y flathub org.freedesktop.Platform//24.08 org.freedesktop.Sdk//24.08

git clone --depth 1 --branch develop https://github.com/RBVI/ChimeraX.git
cd ChimeraX                       # apply the CMAKE_INSTALL_LIBDIR patch
flatpak-builder --force-clean --user --disable-rofiles-fuse fp-build.tmp arm-flatpak.yml
flatpak-builder --export-only --user --install --force-clean fp-build.tmp arm-flatpak.yml
```

`--disable-rofiles-fuse` avoids needing FUSE inside the build. Wall time is a
few hours on 20 cores, almost all of it in the prerequisite stack; a rebuild
after editing only the cmake modules reuses the cached early modules.

## Verification

```text
$ flatpak run --user edu.ucsf.rbvi.ChimeraX --nogui --exit --cmd version
UCSF ChimeraX version: 1.13.dev202608282219 (2026-08-28)

$ file fp-build.tmp/files/bin/ChimeraX
ELF 64-bit LSB pie executable, ARM aarch64
```

### Structure and map handling

Loading PDB 1GRL chains A+B+C and the 64^3 @ 4 Å/px map from the STA acceptance:

| operation | result |
|---|---|
| `open groel_abc.pdb` | **12546 atoms, 12429 bonds, 1554 residues, 3 chains (A,B,C)** |
| `measure mapstats` | min 0, max 57.1, mean 0.3714, **SD 3.272** |
| `fitmap #1 inMap #2` | converged in **132 steps**, average map value 29.41, **0 atoms outside contour** |

The reported map SD of **3.272** matches numpy's `std()` of the same file
(3.2725) — the map reader is numerically correct, not just functional.

### GPU rendering

```bash
DISPLAY=:0 flatpak run --user --device=dri --socket=x11 --filesystem="$PWD" \
    edu.ucsf.rbvi.ChimeraX --exit --script gfx.cxc
```

`save render.png width 800 height 600 supersample 3` produces a correct 235 KB
cartoon render with per-chain colouring and soft lighting, through the GPU.

- **`--offscreen` does not work**: `LimitationError: Unable to save images
  because OpenGL rendering is not available`. That mode needs OSMesa, which this
  manifest does not build. Use a real or virtual X display instead.
- `Failed to connect to the bus: /run/dbus/system_bus_socket` from QtWebEngine is
  harmless in the sandbox.

## Remaining limitation

**Toolshed bundles are still x86-only.** ISOLDE and other plugins have no Linux
ARM64 builds, and `NO_PREBUILT=1` does not change that — it only affects
ChimeraX's own prerequisites. The core application, including structure display,
volume viewer and `fitmap`, is fully available.

## Status of this fork

This repository is a downstream fork pinned at upstream `d8e4a0c` **because a
source change was required**. The delta is two lines in `arm-flatpak.yml`. If
RBVI accept the `CMAKE_INSTALL_LIBDIR` fix upstream, this fork can be retired in
favour of a plain build recipe.
