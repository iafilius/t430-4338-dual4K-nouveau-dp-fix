#!/usr/bin/env bash
# ==============================================================================
# build-patched-kernel.sh
# Downloads a mainline Linux kernel tarball, applies the Nouveau DisplayPort
# division-by-zero patch, configures Debian build flags, and compiles installable
# .deb packages using `bindeb-pkg`.
#
# Usage:
#   ./build-patched-kernel.sh [KERNEL_VERSION] [silent|verbose]
# Example:
#   ./build-patched-kernel.sh 7.1.3 verbose
# ==============================================================================
set -euo pipefail

KERNEL_VER="${1:-7.1.3}"
PATCH_MODE="${2:-verbose}"
MAJOR_VER="v$(echo "${KERNEL_VER}" | cut -d. -f1).x"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORK_DIR="${KERNEL_BUILD_DIR:-${HOME}/kernel}"

if [[ "${PATCH_MODE}" == "silent" ]]; then
    PATCH_FILE="${REPO_ROOT}/patches/0001-drm-nouveau-disp-Prevent-divide-by-zero-after-screen-wake-up.patch"
else
    PATCH_FILE="${REPO_ROOT}/patches/0001-drm-nouveau-disp-verbose-dmesg-logging.patch"
fi

echo "=== Building Patched Linux Kernel ${KERNEL_VER} (Mode: ${PATCH_MODE}) ==="
echo "[*] Working directory : ${WORK_DIR}"
echo "[*] Using patch file  : ${PATCH_FILE}"

mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

TARBALL="linux-${KERNEL_VER}.tar.xz"
if [[ ! -f "${TARBALL}" ]]; then
    echo "[*] Downloading https://cdn.kernel.org/pub/linux/kernel/${MAJOR_VER}/${TARBALL} ..."
    wget "https://cdn.kernel.org/pub/linux/kernel/${MAJOR_VER}/${TARBALL}"
fi

SRC_DIR="linux-${KERNEL_VER}"
if [[ ! -d "${SRC_DIR}" ]]; then
    echo "[*] Extracting ${TARBALL} ..."
    tar -xf "${TARBALL}"
fi

cd "${SRC_DIR}"

echo "[*] Applying Nouveau DisplayPort zero-lane patch..."
patch -p1 --forward < "${PATCH_FILE}" || echo "[!] Patch appears to be already applied."

if [[ ! -f .config ]]; then
    echo "[*] Bootstrapping .config from running kernel (/boot/config-$(uname -r))..."
    cp "/boot/config-$(uname -r)" .config
fi

echo "[*] Disabling module signing certificate dependencies and enabling debug symbols..."
./scripts/config --file .config --disable MODULE_SIG
./scripts/config --file .config --set-str SYSTEM_TRUSTED_KEYS ""
./scripts/config --file .config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ""
./scripts/config --file .config -d COMPILE_TEST -e DEBUG_KERNEL -e DEBUG_INFO
yes "" | make oldconfig >/dev/null

THREADS="$(getconf _NPROCESSORS_ONLN)"
echo "[*] Compiling binary .deb packages using ${THREADS} CPU threads (bindeb-pkg)..."
make -j "${THREADS}" bindeb-pkg LOCALVERSION=-custom

echo "=================================================================="
echo "[+] Build complete! Install the generated packages with:"
echo "    sudo dpkg -i ${WORK_DIR}/linux-image-${KERNEL_VER}-custom_*.deb ${WORK_DIR}/linux-headers-${KERNEL_VER}-custom_*.deb"
echo "    sudo update-grub && sudo reboot"
echo "=================================================================="

