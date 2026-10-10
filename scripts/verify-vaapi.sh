#!/usr/bin/env bash
# ==============================================================================
# Script: verify-vaapi.sh
# Purpose: Check VA-API driver initialization, driver path, and supported codecs
# ==============================================================================

set -euo pipefail

echo "========================================================"
echo "           AMD GPU VA-API Acceleration Check            "
echo "========================================================"

if ! command -v vainfo &>/dev/null; then
    echo "[!] 'vainfo' is not installed. Install it with:"
    echo "    sudo dnf install -y libva-utils"
    exit 1
fi

echo "[*] Checking GPU & kernel driver..."
lspci -k | grep -A 3 -E "VGA|3D|Display" || true
echo ""

echo "[*] Running vainfo..."
echo "--------------------------------------------------------"
vainfo || true
echo "--------------------------------------------------------"

echo ""
echo "[*] Codec Support Summary:"
if vainfo 2>&1 | grep -q "VAProfileH264"; then
    echo "  [✓] H.264 / AVC: Hardware Accelerated"
else
    echo "  [✗] H.264 / AVC: Not Accelerated"
fi

if vainfo 2>&1 | grep -q "VAProfileHEVC"; then
    echo "  [✓] H.265 / HEVC: Hardware Accelerated"
else
    echo "  [✗] H.265 / HEVC: Not Accelerated"
fi

if vainfo 2>&1 | grep -q "VAProfileVP9"; then
    echo "  [✓] VP9: Hardware Accelerated"
else
    echo "  [✗] VP9: Not Accelerated"
fi

if vainfo 2>&1 | grep -q "VAProfileAV1"; then
    echo "  [✓] AV1: Hardware Accelerated"
fi
echo "========================================================"
