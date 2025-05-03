#!/bin/bash
# Huawei 3G Dongle Automatic Installer for Issabel 5
# Developed by Mohamed Badr (@Idlexaz)
# Telegram: https://t.me/Idlexaz
# License: GPLv3

# Exit on error
set -e

# Log everything
exec > >(tee -a /var/log/chan_dongle_install.log) 2>&1
echo "=== Starting installation at $(date) ==="

# ========================
# 1. Install Dependencies
# ========================
echo "[1/6] Installing dependencies..."
yum install -y \
    gcc make libtool automake autoconf \
    git unzip kernel-devel \
    usb_modeswitch usb_modeswitch-data \
    libusb-devel sqlite sqlite-devel acl wget

ldconfig  # Refresh libraries

# ========================
# 2. Compile chan_dongle
# ========================
echo "[2/6] Compiling chan_dongle..."
mkdir -p /usr/src
cd /usr/src

git clone https://github.com/chorovich/asterisk-chan-dongle.git || \
    { cd asterisk-chan-dongle; git pull; }

cd asterisk-chan-dongle

AST_VERSION=$(asterisk -rx "core show version" | grep "Asterisk" | awk '{print $2}')
./bootstrap
./configure --with-astversion=$AST_VERSION --prefix=/usr
make -j$(nproc)
make install

# ========================
# 3. Configuration Files
# ========================
echo "[3/6] Setting up configs..."

# Download dongle.conf from your GitHub
wget -O /etc/asterisk/dongle.conf https://raw.githubusercontent.com/cBadr/Issabel/main/dongle.conf

# UDEV rules
cat > /etc/udev/rules.d/92-huawei.rules << 'EOL'
SUBSYSTEM=="tty", ATTRS{idVendor}=="12d1", MODE="0666", GROUP="asterisk"
SUBSYSTEM=="usb", ATTRS{idVendor}=="12d1", MODE="0666", GROUP="asterisk"
EOL

udevadm control --reload
udevadm trigger

# ========================
# 4. Permission Fixes
# ========================
echo "[4/6] Fixing permissions..."
chown asterisk:asterisk /etc/asterisk/dongle.conf
chmod 640 /etc/asterisk/dongle.conf
chown asterisk:asterisk /var/lock
usermod -a -G dialout,uucp,lock asterisk
setfacl -R -m u:asterisk:rwx /var/lock

# ========================
# 5. Initialize Modem
# ========================
echo "[5/6] Initializing modem..."
usb_modeswitch -v 0x12d1 -p 0x1446 -M "5553424312345678000000000000061b000000030000000000000000000000" || true

# ========================
# 6. Restart Services
# ========================
echo "[6/6] Restarting services..."
asterisk -rx "module load chan_dongle.so" || \
    asterisk -rx "module reload chan_dongle.so"

systemctl restart asterisk

# ========================
# Verification
# ========================
if asterisk -rx "dongle show devices" | grep -q "dongle0"; then
    echo "✅ Success! Dongle is ready."
    echo "=== Current dongle.conf ==="
    cat /etc/asterisk/dongle.conf
else
    echo "❌ Installation failed! Check logs:"
    tail -n 50 /var/log/asterisk/full | grep -i dongle
    exit 1
fi