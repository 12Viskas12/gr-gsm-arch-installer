# gr-gsm-arch-installer

One-command installer for GNU Radio + gr-gsm (with gr-osmosdr, RTL-SDR /
OsmoSDR / AirSpy / MiriSDR support) on **Arch Linux**.

## Before you run this

**Your system must be fully up to date and your PGP keyring must be
current.** This script will not work reliably on a stale or
partially-updated system. Run this first:

```bash
sudo pacman -Sy archlinux-keyring
sudo pacman-key --populate archlinux
sudo pacman -Syu
```

Reboot if the kernel or any core package was updated, then continue.

**Do not run `pacman -Sy` by itself** (without `-u`) at any other point —
on Arch this is called a "partial upgrade" and it is explicitly
unsupported; it can desync package versions and break your system
(this has happened during development of this script).

## Installation

```bash
git clone https://github.com/<USERNAME>/<REPO>.git
cd <REPO>
chmod +x install.sh
./install.sh
```

## Requirements

- Arch Linux or an Arch-based distribution.
- A regular user with `sudo` access (do not run as root).
- At least a few GB of free disk space — building GNU Radio's OOT
  modules from source is disk-hungry. Check with `df -h /` first.
- An SDR receiver (RTL-SDR, AirSpy, etc.) if you actually intend to
  receive anything — the script only installs the software stack.

## What the script does

1. Installs official packages (`gnuradio`, `python-gnuradio`, `boost`,
   `libosmosdr`, `rtl-sdr`, etc.) via `pacman`.
2. Installs `yay` if it isn't already present.
3. Installs a transitional dummy `libosmosdr-git` package, since the
   real AUR package by that name was deleted upstream (the library
   was renamed to `libosmosdr` and moved into the official repos, but
   `gr-osmosdr-git`'s PKGBUILD was never updated to reflect that).
4. Removes packages that are known to file-conflict with the AUR
   `-git` versions we're about to install (`gnuradio-osmosdr`,
   `airspy`), then installs `libosmocore`, `libmirisdr-git`,
   `airspy-git`, and `gr-osmosdr-git` via `yay -S`.
5. Clones `matan1008/gr-gsm` (a maintained fork with GNU Radio 3.10+
   support — the original `ptrkrysik/gr-gsm` is abandoned and does
   not build against modern GNU Radio).
6. Patches `udp_socket.cc`/`.h` for the modern Boost.Asio API
   (`io_service` and `resolver::query` were removed in recent Boost
   versions).
7. Builds with `-DCMAKE_INSTALL_PREFIX=/usr` (Arch does not scan
   `/usr/local` for Python site-packages, so the default `/usr/local`
   prefix leaves the Python bindings invisible) and
   `-DENABLE_GRCC=OFF` (skips the optional, long-broken
   `grgsm_livemon`/`grgsm_livemon_headless` PyQt5 scripts).
8. Installs and runs `ldconfig`.

## After installation

```bash
grgsm_scanner --help
```

If this prints usage information, the install worked. `grgsm_scanner`
also needs a larger shared-memory limit for actual scanning:

```bash
sudo sysctl kernel.shmmni=32000
```

## Troubleshooting

- **Disk full errors during build**: check `df -h /`, clean caches
  with `yay -Sc` and `sudo pacman -Scc`, and check `sudo journalctl
  --vacuum-size=200M`.
- **`cmake: error while loading shared libraries`**: your system is
  out of sync — go back and run the full update steps above.
- **File conflict errors not covered by this script**: run
  `sudo pacman -Rdd --noconfirm <package>` for the conflicting
  package named in the error, then re-run `./install.sh`.
