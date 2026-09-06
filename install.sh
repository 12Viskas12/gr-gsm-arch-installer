#!/usr/bin/env bash
set -euo pipefail

if [ -t 1 ]; then
    C_RESET=$'\033[0m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'
    C_RED=$'\033[1;31m'; C_BLUE=$'\033[1;34m'
else
    C_RESET=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""
fi
info()  { printf "%s[*]%s %s\n" "$C_BLUE"  "$C_RESET" "$1"; }
ok()    { printf "%s[+]%s %s\n" "$C_GREEN" "$C_RESET" "$1"; }
warn()  { printf "%s[!]%s %s\n" "$C_YELLOW" "$C_RESET" "$1"; }
fail()  { printf "%s[x]%s %s\n" "$C_RED"   "$C_RESET" "$1"; exit 1; }
trap 'fail "Script interrupted at line $LINENO."' ERR

[ "$(id -u)" -eq 0 ] && fail "Do not run as root."
command -v pacman &>/dev/null || fail "Arch Linux is required."

export CMAKE_POLICY_VERSION_MINIMUM=3.5

info "Installing dependencies from official repositories..."
sudo pacman -S --needed --noconfirm \
    base-devel git cmake ninja autoconf libtool doxygen \
    boost boost-libs gnuradio python-gnuradio fftw swig \
    python python-numpy python-scipy python-setuptools python-pyqt5 \
    pkgconf pybind11 libosmosdr rtl-sdr
ok "Official dependencies installed."

if ! command -v yay &>/dev/null; then
    info "Installing yay..."
    TMP_YAY="$(mktemp -d)"
    git clone https://aur.archlinux.org/yay-bin.git "$TMP_YAY/yay-bin"
    (cd "$TMP_YAY/yay-bin" && makepkg -si --needed --noconfirm)
    rm -rf "$TMP_YAY"
    command -v yay &>/dev/null || fail "Failed to install yay."
    ok "yay installed."
fi

if ! pacman -Qi libosmosdr-git &>/dev/null; then
    info "Installing transitional libosmosdr-git package..."
    DUMMY_DIR="$(mktemp -d)"
    cat > "$DUMMY_DIR/PKGBUILD" <<'EOF'
pkgname=libosmosdr-git
pkgver=9999
pkgrel=1
pkgdesc="Transitional dummy package: real files provided by libosmosdr"
arch=('any')
depends=('libosmosdr')
provides=('libosmosdr-git')
package() { : ; }
EOF
    (cd "$DUMMY_DIR" && makepkg -si --needed --noconfirm)
    rm -rf "$DUMMY_DIR"
    ok "Transitional package installed."
fi

for pkg in gnuradio-osmosdr airspy; do
    if pacman -Qi "$pkg" &>/dev/null; then
        info "Removing '$pkg' (file conflict with the -git version we're about to install)..."
        sudo pacman -Rdd --noconfirm "$pkg" || warn "Could not remove '$pkg', continuing anyway."
    fi
done

remove_conflicts_for() {
    local pkg="$1"
    local conflicts
    conflicts="$(yay -Si "$pkg" 2>/dev/null | awk -F': ' '/^Conflicts With/ {print $2}')"
    [ "$conflicts" = "None" ] && conflicts=""
    for c in $conflicts; do
        c="${c%,}"
        [ -z "$c" ] && continue
        if pacman -Qi "$c" &>/dev/null; then
            info "Removing conflicting package '$c' (required by $pkg)..."
            sudo pacman -Rdd --noconfirm "$c" || warn "Could not remove '$c', continuing anyway."
        fi
    done
}

for pkg in libosmocore libmirisdr-git airspy-git gr-osmosdr-git; do
    remove_conflicts_for "$pkg"
done

info "Installing libosmocore, libmirisdr-git, airspy-git, gr-osmosdr-git..."
yay -S --needed --noconfirm \
    libosmocore libmirisdr-git airspy-git gr-osmosdr-git
ok "AUR dependencies installed."

info "Cloning gr-gsm (matan1008 fork with GNU Radio 3.10+ support)..."
BUILD_DIR="$(mktemp -d)"
git clone https://github.com/matan1008/gr-gsm "$BUILD_DIR/gr-gsm"

UDP_H="$(find "$BUILD_DIR/gr-gsm" -type f -name udp_socket.h | head -n1)"
UDP_CC="$(find "$BUILD_DIR/gr-gsm" -type f -name udp_socket.cc | head -n1)"

[ -n "$UDP_H" ]  || fail "udp_socket.h not found in gr-gsm sources."
[ -n "$UDP_CC" ] || fail "udp_socket.cc not found in gr-gsm sources."

info "Patching $UDP_H and $UDP_CC for the modern Boost.Asio API..."

sed -i 's/boost::asio::io_service/boost::asio::io_context/g' "$UDP_H" "$UDP_CC"

python3 - "$UDP_CC" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, "r") as f:
    content = f.read()

old_block = """      udp::resolver::query rx_query(
        udp::v4(), bind_addr, src_port,
        boost::asio::ip::resolver_query_base::passive);
      udp::resolver::query tx_query(
        udp::v4(), remote_addr, dst_port,
        boost::asio::ip::resolver_query_base::passive);

      d_udp_endpoint_rx = *resolver.resolve(rx_query);
      d_udp_endpoint_tx = *resolver.resolve(tx_query);"""

new_block = """      d_udp_endpoint_rx = *resolver.resolve(
        udp::v4(), bind_addr, src_port,
        boost::asio::ip::resolver_base::passive).begin();
      d_udp_endpoint_tx = *resolver.resolve(
        udp::v4(), remote_addr, dst_port,
        boost::asio::ip::resolver_base::passive).begin();"""

if old_block not in content:
    print("PATCH NOT APPLIED: expected code block not found in udp_socket.cc", file=sys.stderr)
    sys.exit(1)

content = content.replace(old_block, new_block)
with open(path, "w") as f:
    f.write(content)
print("udp_socket.cc patched successfully.")
PYEOF

info "Building gr-gsm..."
mkdir -p "$BUILD_DIR/gr-gsm/build"
cd "$BUILD_DIR/gr-gsm/build"
cmake -DCMAKE_INSTALL_PREFIX=/usr -DENABLE_GRCC=OFF ..
make -j"$(nproc)"
sudo make install
sudo ldconfig
rm -rf "$BUILD_DIR"

ok "gr-gsm built and installed."
echo
ok "Done! Check it with: grgsm_scanner --help"
