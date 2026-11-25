#!/usr/bin/env bash
# Offline compute PSO precompiler wrapper for XCL under Proton/Wine.
# Warms the DXIL and driver PSO blob caches before launching a title.
#
# Usage:
#   ./scripts/linux/precompile-pso.sh <game-dir> [--used|--all] [--threads N] [--records FILE]
#
# Environment overrides:
#   XCL_EXE     Path to xcl.exe (default: target/x86_64-pc-windows-msvc/release/xcl.exe or ./xcl.exe)
#   PROTON_DIR  Path to Proton installation (default: Steam Proton - Experimental)
#   WINEPREFIX  Path to Wine prefix (default: $HOME/xcl-prefix)
#   THREADS     Default --threads count if not passed on CLI (default: 6)
set -euo pipefail

for arg in "$@"; do
    if [ "${arg}" = "-h" ] || [ "${arg}" = "--help" ]; then
        sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
    fi
done

if [ $# -lt 1 ]; then
    echo "Usage: $0 <game-dir> [--used|--all] [--threads N] [--records FILE]" >&2
    exit 2
fi

GAME_DIR="$1"
shift

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTON_DIR="${PROTON_DIR:-${HOME}/.steam/steam/steamapps/common/Proton - Experimental}"
WINEPREFIX="${WINEPREFIX:-${HOME}/xcl-prefix}"
THREADS="${THREADS:-6}"
WINE_BIN="${PROTON_DIR}/files/bin/wine"

if [ -n "${XCL_EXE:-}" ]; then
    EXE="${XCL_EXE}"
elif [ -f "${REPO_DIR}/target/x86_64-pc-windows-msvc/release/xcl.exe" ]; then
    EXE="${REPO_DIR}/target/x86_64-pc-windows-msvc/release/xcl.exe"
elif [ -f "${REPO_DIR}/target/x86_64-pc-windows-gnu/release/xcl.exe" ]; then
    EXE="${REPO_DIR}/target/x86_64-pc-windows-gnu/release/xcl.exe"
else
    EXE="./xcl.exe"
fi

[ -x "${WINE_BIN}" ] || { echo "ERROR: Wine binary not found at '${WINE_BIN}' (set PROTON_DIR)" >&2; exit 1; }
[ -f "${EXE}" ] || { echo "ERROR: xcl.exe not found at '${EXE}' (set XCL_EXE)" >&2; exit 1; }
[ -f "${GAME_DIR}/shaders.rpf" ] || [ -f "${GAME_DIR}" ] || { echo "ERROR: shaders.rpf not found in '${GAME_DIR}'" >&2; exit 1; }

EXTRA_ARGS=()
HAS_SELECTOR=0
HAS_THREADS=0
while [ $# -gt 0 ]; do
    case "$1" in
        --all)
            HAS_SELECTOR=1
            shift
            ;;
        --used)
            HAS_SELECTOR=1
            EXTRA_ARGS+=("--used")
            shift
            ;;
        --records)
            HAS_SELECTOR=1
            EXTRA_ARGS+=("$1" "${2:?--records requires a file path}")
            shift 2
            ;;
        --threads)
            HAS_THREADS=1
            EXTRA_ARGS+=("$1" "${2:?--threads requires a number}")
            shift 2
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

[ "${HAS_SELECTOR}" -eq 0 ] && EXTRA_ARGS+=("--used")
[ "${HAS_THREADS}" -eq 0 ] && EXTRA_ARGS+=("--threads" "${THREADS}")

export WINEPREFIX
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="d3d12,d3d12core,dxgi,d3d11,d3d10core=n,b;wintab32=d"
export VKD3D_CONFIG="${VKD3D_CONFIG:-ignore_shared_fence}"
export XCL_NETWORK=0

WIN_GAME_DIR="$("${WINE_BIN}" winepath -w "${GAME_DIR}" 2>/dev/null | tr -d '\r')"
EXE_DIR="$(cd "$(dirname "${EXE}")" && pwd)"

cd "${EXE_DIR}"
chmod +x "${EXE}"
exec "${WINE_BIN}" "${EXE}" pso-precompile "${WIN_GAME_DIR}" "${EXTRA_ARGS[@]}"
