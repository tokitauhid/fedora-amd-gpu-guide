# Fedora AMD GPU Hardware Video Acceleration & Codec Guide

A comprehensive, production-grade guide to unlocking **100% full hardware video decoding and encoding** capabilities on **AMD Radeon GPUs** (RDNA 1/2/3, Vega, Polaris) on **Fedora Linux**.

Includes rationale, manual step-by-step instructions, browser hardware acceleration tuning, and real-world edge cases drawn from production system logs.

---

## Table of Contents

1. [Why This Guide Exists: The Problem with Fedora's Default Stack](#why-this-guide-exists)
2. [Performance & Real-World Impact](#performance--real-world-impact)
   - [CPU Load & Thermal Throttling](#cpu-load--thermal-throttling)
   - [Media Servers (Jellyfin / Plex)](#media-servers-jellyfin--plex)
   - [Gaming & Steam / Proton Compatibility](#gaming--steam--proton-compatibility)
3. [Architecture Overview: How Linux Video Acceleration Works](#architecture-overview)
4. [Step-by-Step Manual Setup](#step-by-step-manual-setup)
   - [Step 1: Enable RPM Fusion Repositories](#step-1-enable-rpm-fusion-repositories)
   - [Step 2: Install Mesa Freeworld VA-API Drivers](#step-2-install-mesa-freeworld-va-api-drivers)
   - [Step 3: Swap Restricted FFmpeg with Full FFmpeg](#step-3-swap-restricted-ffmpeg-with-full-ffmpeg)
   - [Step 4: Install GStreamer Hardware Acceleration Plugins](#step-4-install-gstreamer-hardware-acceleration-plugins)
   - [Step 5: Install 32-bit (i686) Drivers for Steam & Wine](#step-5-install-32-bit-i686-drivers-for-steam--wine)
5. [Browser Hardware Acceleration Tuning](#browser-hardware-acceleration-tuning)
   - [Firefox](#firefox)
   - [Chromium / Helium / Brave / Chrome](#chromium--helium--brave--chrome)
6. [Real-World Edge Cases & Troubleshooting (From Machine Logs)](#real-world-edge-cases--troubleshooting)
   - [Edge Case 1: Mesa 26 / Fedora 44 VDPAU Deprecation](#edge-case-1-mesa-26--fedora-44-vdpau-deprecation)
   - [Edge Case 2: Mirror Redirection Failures & Timeouts](#edge-case-2-mirror-redirection-failures--timeouts)
   - [Edge Case 3: DNF `minrate` and Aggressive Timeout Aborts](#edge-case-3-dnf-minrate-and-aggressive-timeout-aborts)
   - [Edge Case 4: Steam / Proton 32-bit Video Playback Stutters](#edge-case-4-steam--proton-32-bit-video-playback-stutters)
7. [Verification & Benchmarks](#verification--benchmarks)
8. [Automated Installation Scripts](#automated-installation-scripts)

---

## Why This Guide Exists

On a fresh or default installation of Fedora Linux, you may notice that:
- 1080p and 4K YouTube/Twitch videos make your fans ramp up or drop frames.
- Local media streaming clients (e.g., **Jellyfin**, **Plex**) take a long time to buffer or force the server to transcode.
- Battery life drops significantly while watching videos on laptops.

### The Cause: US Software Patents & Legal Restrictions
Due to United States patent liabilities, the Fedora Project cannot legally ship proprietary, patent-encumbered codec acceleration by default. Specifically, starting in Fedora 37+, Fedora's official `mesa` package **explicitly disables hardware decoding and encoding for**:
* **H.264 / AVC**
* **H.265 / HEVC**
* **VC-1**

While royalty-free codecs like **AV1** and **VP9** remain hardware-accelerated out of the box, over **90% of the world's video content** (including almost all streaming libraries, Blu-ray rips, and home media servers) is encoded in H.264 or HEVC.

On Fedora, attempting to play these streams defaults to **unaccelerated software decoding on the CPU**.

---

## Performance & Real-World Impact

### CPU Load & Thermal Throttling
- **With Hardware Acceleration (VA-API):** The dedicated ASIC on your AMD GPU (Video Core Next / VCN) handles video processing directly. CPU utilization remains below **1–3%**, GPU temperatures stay cool, and fan noise is virtually silent.
- **Without Hardware Acceleration (Software Fallback):** The CPU must brute-force decode every frame. A 4K 60fps HEVC stream can easily consume **60–100% of CPU cores**, triggering thermal throttling and stuttering.

### Media Servers (Jellyfin / Plex)
When a client browser (like Helium, Chrome, or Firefox) connects to Jellyfin or Plex:
1. The browser checks with the OS to determine supported hardware codecs.
2. If Fedora lacks H.264/HEVC VA-API support, the browser signals to the server: *"I cannot direct-play this codec."*
3. The server is forced into **real-time server-side transcoding**, converting the video into an uncompressed or baseline stream on the fly.
4. On underpowered home servers (e.g., Intel N100, Raspberry Pi, NAS), transcoding causes **massive initial buffering delays (10–30 seconds)** and choppy playback.

### Gaming & Steam / Proton Compatibility
Many Windows games run via Proton/Wine require in-game cutscene and video playback (using Media Foundation or DirectShow). If 32-bit or 64-bit hardware VA-API libraries are missing, games either crash or freeze during video cutscenes.

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────┐
│     User Applications (Helium, Firefox, MPV, VLC)      │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│      VA-API Interface (libva / libva-utils / vainfo)    │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│   Mesa Gallium Driver (radeonsi_drv_video.so)           │
│   [mesa-va-drivers-freeworld provides H.264/HEVC/VC1]  │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│      Kernel DRM Driver (amdgpu) & AMD VCN Hardware     │
│       (Navi 10 / RDNA 1, RDNA 2, RDNA 3, Vega)         │
└────────────────────────────────────────────────────────┘
```

---

## Step-by-Step Manual Setup

### Step 1: Enable RPM Fusion Repositories
RPM Fusion is the standard community repository providing packages that Fedora cannot distribute for legal/licensing reasons.

```bash
sudo dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
```

> **Note on Network Mirrors:** If `mirrors.rpmfusion.org` hangs or encounters connection drops, see [Edge Case 2](#edge-case-2-mirror-redirection-failures--timeouts) for direct mirror URLs.

---

### Step 2: Install Mesa Freeworld VA-API Drivers
Swap Fedora's restricted `mesa-va-drivers` with the complete `mesa-va-drivers-freeworld`:

```bash
sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld --allowerasing
```

---

### Step 3: Swap Restricted FFmpeg with Full FFmpeg
Fedora provides a stripped-down `ffmpeg-free` package. Swap it with full `ffmpeg` from RPM Fusion:

```bash
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
```

---

### Step 4: Install GStreamer Hardware Acceleration Plugins
Many native desktop applications and media players rely on GStreamer:

```bash
sudo dnf install -y \
  gstreamer1-plugins-bad-freeworld \
  gstreamer1-plugins-ugly \
  gstreamer1-vaapi \
  libva-utils \
  --allowerasing
```

---

### Step 5: Install 32-bit (i686) Drivers for Steam & Wine
For gamers playing 32-bit Windows games via Proton/Wine:

```bash
sudo dnf install -y mesa-va-drivers-freeworld.i686 --allowerasing
```

---

## Browser Hardware Acceleration Tuning

Even with drivers installed, browsers sometimes require explicit flags to utilize VA-API on Linux.

### Firefox
1. Navigate to `about:config` in the address bar.
2. Search and verify the following settings:
   - `media.ffmpeg.vaapi.enabled` ➔ `true`
   - `media.rdd-ffmpeg.enabled` ➔ `true`
   - `media.navigator.mediadatadecoder_vpx_enabled` ➔ `true`
3. Restart Firefox.
4. Verify by checking `about:support` under **Media** ➔ **Hardware Decoding**.

### Chromium / Helium / Brave / Chrome
1. Navigate to `chrome://flags` (or `helium://flags`, `brave://flags`).
2. Search and configure:
   - **Hardware-accelerated video decode** ➔ `Enabled`
   - **Preferred Ozone platform** ➔ `Wayland` (if on KDE/GNOME Wayland)
   - **Vulkan** ➔ `Enabled` (optional, enhances raster performance on AMD)
3. Check status at `chrome://gpu`: Under **Video Acceleration Information**, you should see `Decode h264, vp9, hevc`.

---

## Real-World Edge Cases & Troubleshooting

*(Derived directly from machine logs during real-world Fedora 44 deployment)*

### Edge Case 1: Mesa 26 / Fedora 44 VDPAU Deprecation
* **The Error:**
  ```text
  Failed to resolve the transaction:
  No match for argument: mesa-vdpau-drivers-freeworld
  ```
* **The Cause:** In Mesa 26 (Fedora 44+), the legacy VDPAU state tracker for AMD GPUs (`radeonsi`) has been deprecated and removed in favor of modern VA-API (`libva`). Older tutorials instruct users to install `mesa-vdpau-drivers-freeworld`.
* **The Solution:** Do **not** attempt to install `mesa-vdpau-drivers-freeworld`. Modern media players and browsers use VA-API exclusively.

---

### Edge Case 2: Mirror Redirection Failures & Timeouts
* **The Error:**
  ```text
  Librepo error: Curl error (7): Could not connect to server for 
  https://mirrors.ustc.edu.cn/rpmfusion/free/fedora/rpmfusion-free-release-44.noarch.rpm 
  [Failed to connect to mirrors.ustc.edu.cn port 443 after 183 ms: Could not connect to server]
  ```
* **The Cause:** `mirrors.rpmfusion.org` uses dynamic GeoIP redirection. In parts of Asia, users are redirected to university mirrors in China (e.g., USTC) that may block, throttle, or reject foreign HTTPS connections.
* **The Solution:** Download the release packages directly from top-tier primary mirrors using `curl`:
  ```bash
  curl -L -o /tmp/rpmfusion-free.rpm https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
  curl -L -o /tmp/rpmfusion-nonfree.rpm https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
  sudo dnf install -y /tmp/rpmfusion-free.rpm /tmp/rpmfusion-nonfree.rpm
  ```

---

### Edge Case 3: DNF `minrate` and Aggressive Timeout Aborts
* **The Error:**
  ```text
  Curl error (28): Timeout was reached for ... 
  [Operation too slow. Less than 102400 bytes/sec transferred the last 30 seconds]
  ```
* **The Cause:** If `/etc/dnf/dnf.conf` contains an overly strict `minrate` or `timeout` threshold, momentarily slow mirror responses trigger fatal aborts.
* **The Solution:** Keep `/etc/dnf/dnf.conf` balanced:
  ```ini
  [main]
  max_parallel_downloads=10
  minrate=100k
  timeout=30
  defaultyes=True
  ```

---

### Edge Case 4: Steam / Proton 32-bit Video Playback Stutters
* **The Symptom:** Native Linux games work flawlessly, but Windows games running in Proton show blank screens or stutter heavily during cutscenes.
* **The Cause:** Most video players in 32-bit Windows games require the 32-bit driver `mesa-va-drivers-freeworld.i686`. Installing only the 64-bit driver leaves 32-bit Wine prefixes with no video hardware acceleration.
* **The Solution:** Always install the `.i686` multi-lib package:
  ```bash
  sudo dnf install -y mesa-va-drivers-freeworld.i686
  ```

---

## Verification & Benchmarks

Run `vainfo` to verify all hardware acceleration profiles:

```bash
vainfo
```

### Expected Output for AMD Radeon (e.g., RX 5700 XT / Navi 10):
```text
Trying display: wayland
libva info: VA-API version 1.23.0
libva info: Trying to open /usr/lib64/dri-freeworld/radeonsi_drv_video.so
libva info: Found init function __vaDriverInit_1_23
libva info: va_openDriver() returns 0
vainfo: VA-API version: 1.23 (libva 2.23.0)
vainfo: Driver version: Mesa Gallium driver 26.2.4 for AMD Radeon RX 5700 XT (radeonsi, navi10, ACO)
vainfo: Supported profile and entrypoints
      VAProfileVC1Simple              :	VAEntrypointVLD
      VAProfileVC1Main                :	VAEntrypointVLD
      VAProfileVC1Advanced            :	VAEntrypointVLD
      VAProfileH264ConstrainedBaseline:	VAEntrypointVLD
      VAProfileH264ConstrainedBaseline:	VAEntrypointEncSlice
      VAProfileH264Main               :	VAEntrypointVLD
      VAProfileH264Main               :	VAEntrypointEncSlice
      VAProfileH264High               :	VAEntrypointVLD
      VAProfileH264High               :	VAEntrypointEncSlice
      VAProfileHEVCMain               :	VAEntrypointVLD
      VAProfileHEVCMain               :	VAEntrypointEncSlice
      VAProfileHEVCMain10             :	VAEntrypointVLD
      VAProfileHEVCMain10             :	VAEntrypointEncSlice
      VAProfileVP9Profile0            :	VAEntrypointVLD
      VAProfileVP9Profile2            :	VAEntrypointVLD
      VAProfileNone                   :	VAEntrypointVideoProc
```

#### Understanding the Entrypoints:
- `VAEntrypointVLD`: **Hardware Decoding** (Variable-Length Decoding).
- `VAEntrypointEncSlice`: **Hardware Encoding** (e.g. for OBS Studio, Discord screen sharing).
- `HEVCMain10`: **10-bit HDR video hardware acceleration**.

---

## Automated Installation Scripts

For convenience, ready-to-run automation scripts are provided in the [`scripts/`](./scripts/) directory:

- [`scripts/enable-codecs.sh`](./scripts/enable-codecs.sh): Automates repo setup, direct mirror fallback, codec swaps, and multi-lib installation.
- [`scripts/verify-vaapi.sh`](./scripts/verify-vaapi.sh): Quickly tests VA-API status and outputs available hardware profiles.
