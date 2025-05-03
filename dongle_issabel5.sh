#!/bin/bash
# Huawei 3G Dongle Auto-Installer for Issabel 5
# Updated with reliable repository and fixes
# By Mohamed Badr (@Idlexaz)

# Exit on error
set -e

# Log everything
exec > >(tee -a /var/log/dongle_install.log) 2>&1
echo "=== Starting installation $(date) ==="

# ========================
# 1. Install Dependencies
# ========================
echo "[1/6] Installing required packages..."
yum install -y \
    gcc make libtool automake autoconf \
    git unzip kernel-devel wget \
    usb_modeswitch usb_modeswitch-data \
    libusb-devel sqlite sqlite-devel acl

ldconfig

# ========================
# 2. Compile chan_dongle
# ========================
echo "[2/6] Building chan_dongle..."
cd /usr/src

# Using reliable alternative repository
REPO="https://github.com/wdoekes/asterisk-chan-dongle.git"
if [ -d "asterisk-chan-dongle" ]; then
    echo "⚠️  Updating existing repository..."
    cd asterisk-chan-dongle
    git pull || { echo "❌ Update failed. Removing and cloning fresh..."; cd ..; rm -rf asterisk-chan-dongle; git clone $REPO; }
else
    git clone $REPO || { echo "❌ Clone failed. Trying alternative..."; git clone https://github.com/irisdev/asterisk-chan-dongle.git; }
fi

cd asterisk-chan-dongle
AST_VER=$(asterisk -rx "core show version" | grep Asterisk | awk '{print $2}')
./bootstrap
./configure --with-astversion=$AST_VER --prefix=/usr
make -j$(nproc)
make install

# ========================
# 3. Download Configs
# ========================
echo "[3/6] Downloading configs from GitHub..."
wget -O /etc/asterisk/dongle.conf \
    https://raw.githubusercontent.com/cBadr/Issabel/main/dongle.conf || \
    { echo "⚠️  Using default dongle.conf"; 
      echo -e "[general]\ninterval=20\nresetdongle=yes\n\n[dongle0]\nmodel=default" > /etc/asterisk/dongle.conf; }

wget -O /etc/udev/rules.d/92-huawei.rules \
    https://raw.githubusercontent.com/cBadr/Issabel/main/92-huawei-3g.rules || \
    { echo "⚠️  Using default udev rules";
      echo 'SUBSYSTEM=="tty", ATTRS{idVendor}=="12d1", MODE="0666", GROUP="asterisk"' > /etc/udev/rules.d/92-huawei.rules; }

# ========================
# 4. Set Permissions
# ========================
echo "[4/6] Configuring permissions..."
chown asterisk:asterisk /etc/asterisk/dongle.conf /var/lock
chmod 640 /etc/asterisk/dongle.conf
usermod -a -G dialout,uucp,lock asterisk
setfacl -R -m u:asterisk:rwx /var/lock
udevadm control --reload
udevadm trigger

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
echo "=== Verifying installation ==="
if asterisk -rx "dongle show devices" | grep -q "dongle0"; then
    echo "✅ Success! Dongle is ready."
    echo "=== Config Summary ==="
    echo "dongle.conf:"
    head -n 10 /etc/asterisk/dongle.conf
    echo "====================="
    asterisk -rx "dongle show devices"
else
    echo "❌ Installation failed!"
    echo "=== Last 50 lines of log ==="
    tail -n 50 /var/log/asterisk/full | grep -i dongle
    exit 1
fi
