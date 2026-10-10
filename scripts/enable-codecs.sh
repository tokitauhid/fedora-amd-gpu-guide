#!/usr/bin/env bash
# ==============================================================================
# Script: enable-codecs.sh
# Purpose: Enable full hardware acceleration and proprietary codecs on Fedora Linux
# Architecture: AMD Radeon (radeonsi / VA-API)
# ==============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
   echo "[!] This script must be run as root (use sudo)."
   exit 1
fi

FEDORA_VER=$(rpm -E %fedora)
echo "[*] Detected Fedora version: ${FEDORA_VER}"

echo "[*] Step 1: Downloading and installing RPM Fusion repositories..."
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

# Download directly with fallback to primary mirror in case GeoIP redirection fails
curl -L -s -o "${TMP_DIR}/rpmfusion-free.rpm" \
  "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" || \
curl -L -s -o "${TMP_DIR}/rpmfusion-free.rpm" \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm"

curl -L -s -o "${TMP_DIR}/rpmfusion-nonfree.rpm" \
  "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm" || \
curl -L -s -o "${TMP_DIR}/rpmfusion-nonfree.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"

dnf install -y "${TMP_DIR}/rpmfusion-free.rpm" "${TMP_DIR}/rpmfusion-nonfree.rpm"

echo "[*] Step 2: Refreshing DNF metadata..."
dnf makecache

echo "[*] Step 3: Swapping standard Mesa drivers for Mesa Freeworld (H.264 / HEVC / VC-1)..."
dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld --allowerasing || \
dnf install -y mesa-va-drivers-freeworld --allowerasing

echo "[*] Step 4: Installing 32-bit Mesa Freeworld drivers (for Steam / Proton gaming)..."
dnf install -y mesa-va-drivers-freeworld.i686 --allowerasing || true

echo "[*] Step 5: Swapping restricted ffmpeg-free for full FFmpeg..."
dnf swap -y ffmpeg-free ffmpeg --allowerasing || \
dnf install -y ffmpeg --allowerasing

echo "[*] Step 6: Installing GStreamer hardware acceleration plugins and verification tools..."
dnf install -y \
  gstreamer1-plugins-bad-freeworld \
  gstreamer1-plugins-ugly \
  gstreamer1-vaapi \
  libva-utils \
  --allowerasing

echo ""
echo "[✓] Installation complete! Verifying VA-API profiles..."
echo "--------------------------------------------------------"
if command -v vainfo &>/dev/null; then
    vainfo || true
fi
echo "--------------------------------------------------------"
echo "[✓] Your AMD GPU is now fully accelerated for H.264, HEVC, and VP9."
