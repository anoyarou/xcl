#!/usr/bin/env bash
# Cross-compile XCL natively on Linux for x86_64-pc-windows-msvc using cargo-xwin.
#
# Usage:
#   ./scripts/linux/build-xwin.sh                    # Build release workspace
#   ./scripts/linux/build-xwin.sh --deploy ~/XCL     # Build and copy binaries to ~/XCL
#   ./scripts/linux/build-xwin.sh -- --bin xcl       # Pass extra flags to cargo
#
# Environment overrides:
#   TARGET  Rust target triple (default: x86_64-pc-windows-msvc)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TARGET="${TARGET:-x86_64-pc-windows-msvc}"

# Ensure rustup's ~/.cargo/bin takes precedence over distro /usr/bin/cargo
if [ -d "${HOME}/.cargo/bin" ]; then
    export PATH="${HOME}/.cargo/bin:${PATH}"
fi

DEPLOY_DIR=""
CARGO_ARGS=()

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --deploy)
            DEPLOY_DIR="${2:?--deploy requires a destination directory}"
            shift 2
            ;;
        --)
            shift
            CARGO_ARGS+=("$@")
            break
            ;;
        *)
            CARGO_ARGS+=("$1")
            shift
            ;;
    esac
done

for tool in cargo cargo-xwin lld-link llvm-lib clang-cl; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "ERROR: Required tool '${tool}' not found in PATH." >&2
        echo "See docs/linux.md for setup instructions." >&2
        exit 1
    fi
done

echo "=================================================="
echo "Building XCL on Linux via cargo-xwin"
echo "Repo:    ${REPO_DIR}"
echo "Commit:  $(git -C "${REPO_DIR}" log -1 --oneline 2>/dev/null || echo unknown)"
echo "Target:  ${TARGET}"
echo "Cargo:   $(command -v cargo)"
echo "=================================================="

cd "${REPO_DIR}"
# libudis86-sys passes GCC's -includestring.h which clang-cl ignores; -FIstring.h is the clang-cl equivalent
export CFLAGS="${CFLAGS:+${CFLAGS} }-FIstring.h"
cargo xwin build --release --target "${TARGET}" --workspace "${CARGO_ARGS[@]}"

OUT_DIR="${REPO_DIR}/target/${TARGET}/release"
echo "Build complete: ${OUT_DIR}"

if [ -n "${DEPLOY_DIR}" ]; then
    mkdir -p "${DEPLOY_DIR}"
    for f in xcl.exe xcl.pdb xcl.d xcl_testtitle.exe xcl_testtitle.pdb xcl_testtitle.d testgame_mw.dll testgame_mw.pdb; do
        if [ -f "${OUT_DIR}/${f}" ]; then
            cp -f "${OUT_DIR}/${f}" "${DEPLOY_DIR}/${f}"
            if [[ "${f}" == *.exe || "${f}" == *.dll ]]; then
                chmod +x "${DEPLOY_DIR}/${f}"
            fi
        fi
    done
    if [ -d "${DEPLOY_DIR}/testgame" ]; then
        [ -f "${DEPLOY_DIR}/xcl_testtitle.exe" ] && cp -f "${DEPLOY_DIR}/xcl_testtitle.exe" "${DEPLOY_DIR}/testgame/"
        [ -f "${DEPLOY_DIR}/testgame_mw.dll" ] && cp -f "${DEPLOY_DIR}/testgame_mw.dll" "${DEPLOY_DIR}/testgame/"
    fi
    echo "Deployed release binaries to ${DEPLOY_DIR}"
fi
