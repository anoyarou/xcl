# Running & Building XCL on Linux (Proton / Wine)

This guide covers cross-compiling XCL natively on Linux (without a Windows VM) and running titles under Proton/Wine with `vkd3d-proton` and `gamescope`.

---

## 1. Building Natively on Linux

### Option A: MSVC Target via `cargo-xwin` (Recommended)
Produces `x86_64-pc-windows-msvc` binaries (`xcl.exe`, `.pdb` symbols, `xcl_testtitle.exe`, `testgame_mw.dll`) with full MSVC ABI parity.

**Prerequisites (Fedora):**
```bash
sudo dnf install clang lld llvm rustup
rustup-init -y
source ~/.cargo/env
rustup target add x86_64-pc-windows-msvc
cargo install cargo-xwin
```

*(On Arch/Debian/Ubuntu, install the equivalent `clang`, `lld`, `llvm`, and `rustup` packages.)*

**Build:**
```bash
./scripts/linux/build-xwin.sh
```
Or manually:
```bash
CFLAGS="-FIstring.h" cargo xwin build --release --target x86_64-pc-windows-msvc --workspace
```
> **Why `CFLAGS="-FIstring.h"`?** `libudis86-sys` passes GCC's `-includestring.h`, which `clang-cl` ignores; `-FIstring.h` is the `clang-cl` equivalent so `memset` is declared.

Outputs land in `target/x86_64-pc-windows-msvc/release/`.

### Option B: MinGW Target (`x86_64-pc-windows-gnu`)
```bash
rustup target add x86_64-pc-windows-gnu
cargo build --release --target x86_64-pc-windows-gnu --workspace
```
Outputs land in `target/x86_64-pc-windows-gnu/release/`.

---

## 2. Runtime Prerequisites

1. **Proton Experimental** (or recent Wine + `vkd3d-proton`).
2. **DXC DLLs** (`dxcompiler.dll` and `dxil.dll`) placed next to `xcl.exe` (or pointed to via `XCL_DXC_DIR`).
3. **`vkd3d-proton` with recent `dxil-spirv`** (PR `#371` / `#375` or newer): older `dxil-spirv` builds can spike 20+ GiB RAM or fault in `d3d12core.dll` (`cfg_structurizer.cpp`) on large translated compute shaders under RADV.
4. **Optional:** `gamescope` for Wayland compositor isolation and resolution control.

---

## 3. Recommended Environment Variables

```bash
export WINEPREFIX="$HOME/xcl-prefix"
export WINEDEBUG=-all
export WINEDLLOVERRIDES="d3d12,d3d12core,dxgi,d3d11,d3d10core=n,b;wintab32=d"
export VKD3D_CONFIG=ignore_shared_fence
export XCL_NETWORK=0        # Block crash reporter / network uploads
export XCL_PSO_PRELOAD=0    # Avoid runaway background compute preloading under Wine

# Controller (SDL -> winexinput.sys as XInput slot 0; works with DualSense/Xbox pads)
export SDL_JOYSTICK_HIDAPI=1
export PROTON_DISABLE_HIDRAW=1
```

### Tuning & Diagnostic Switches
- `XCL_PSO_WAIT_MS=50` — Bounds per-bind waits for compute PSO compilation so a single slow shader does not freeze rendering.
- `XCL_PSO_FRAME_WAIT_MS=100` — Caps total shader-wait time per frame (refills on each `PresentX`).
- `XCL_COHERENT_HEAPS=0 XCL_COHERENT_MB=512` — Reduces coherent-window read/write stalls on heavy world compute passes.
- `XCL_DIRECT_DXIL=0` — Falls back from direct DXIL to HLSL/DXC translation (useful to isolate Direct DXIL vs driver issues).
- `XCL_DRED=1` — Enables D3D12 DRED breadcrumbs for diagnosing GPU device-removed (`0x887a0005`) hangs.
- `XCL_THREAD_DUMP_AT=<seconds>` — Dumps all thread stacks to `xcl.log` at the given uptime.
- `XCL_PRESS_AT="60:A"` — Sends an automated gamepad button press at the given uptime (seconds).

---

## 4. Offline Compute PSO Precompilation

To warm the DXIL and driver PSO caches before launching a heavy title:
```bash
./scripts/linux/precompile-pso.sh /path/to/unpacked/game --used --threads 6
```
- `--used` compiles pipelines recorded by earlier runs first (default); pass `--all` to precompile every compute shader in `shaders.rpf`.
- Choose `--threads N` based on available RAM, not just CPU cores — large compute pipelines can spike 2–4 GiB each in the driver (e.g. `6` threads on a 32 GiB host, `4` if other heavy workloads are running).

---

## 5. Running the Test Title

Place `xcl_testtitle.exe`, `testgame_mw.dll`, `MicrosoftGame.config`, and `data/` inside a `testgame/` directory next to `xcl.exe`, then run:
```bash
"/path/to/Proton - Experimental/files/bin/wine" ./xcl.exe run ./testgame -- --hello
```
Remove stale overlay state between runs if needed:
```bash
rm -rf "$WINEPREFIX/drive_c/users/steamuser/AppData/Local/XCL/XCL.TestTitle/overlay"
```

---

## 6. Troubleshooting

- **Orphaned processes:** `gamescope` or `wineserver` can stay alive after a crash or GPU reset:
  ```bash
  killall -9 gamescope gamescope-wl gamescopereaper wineserver wine 2>/dev/null || true
  ```
- **Memory headroom:** Heavy titles can consume 20–25+ GiB RAM during world load. Check `free -h` before launching to avoid swap thrashing.
- **AMD `amdgpu` GPU resets (`VkResult: -4` / `0x887a0005`):** Linux `amdgpu` defaults to a 10-second per-ring lockup timeout. If a heavy world compute dispatch exceeds 10s without hanging permanently, `amdgpu.lockup_timeout=30000` can be tested as a kernel parameter, or test `XCL_DIRECT_DXIL=0` / `XCL_DRED=1` to identify the offending shader.
