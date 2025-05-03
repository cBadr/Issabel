#!/bin/bash
# Huawei 3G Dongle Auto-Installer for Issabel 5
# Final Optimized Version - Uses Git Clone for Configs
# By Mohamed Badr (@Idlexaz)

# Exit on error
set -e

# Log everything
exec > >(tee -a /var/log/dongle_install.log) 2>&1
echo "=== Starting installation $(date) ==="

# ========================
# 1. Install Dependencies
# ========================
echo "[1/6] Installing dependencies..."
yum install -y \
    gcc make libtool automake autoconf \
    git unzip kernel-devel \
    usb_modeswitch usb_modeswitch-data \
    libusb-devel sqlite sqlite-devel acl

ldconfig

# ========================
# 2. Compile chan_dongle
# ========================
echo "[2/6] Building chan_dongle..."
cd /usr/src

# Using public repository
REPO="https://github.com/wdoekes/asterisk-chan-dongle.git"
if [ -d "asterisk-chan-dongle" ]; then
    echo "Updating existing repository..."
    cd asterisk-chan-dongle
    git pull || { 
        echo "Update failed. Cloning fresh...";
        cd ..
        rm -rf asterisk-chan-dongle
        git clone "$REPO"
    }
else
    git clone "$REPO"
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
echo "[3/6] Getting configs using git..."
CONFIG_REPO="https://github.com/cBadr/Issabel.git"
TMP_CONFIG_DIR="/tmp/issabel_configs"

# Clone or pull config repository
if [ -d "$TMP_CONFIG_DIR" ]; then
    echo "Updating config repository..."
    cd "$TMP_CONFIG_DIR"
    git pull || {
        echo "Failed to update, re-cloning..."
        rm -rf "$TMP_CONFIG_DIR"
        git clone "$CONFIG_REPO" "$TMP_CONFIG_DIR"
    }
else
    git clone "$CONFIG_REPO" "$TMP_CONFIG_DIR"
fi

# Copy config files with backup
echo "Copying configuration files..."
cp -f "$TMP_CONFIG_DIR/dongle.conf" /etc/asterisk/dongle.conf
cp -f "$TMP_CONFIG_DIR/92-huawei-3g.rules" /etc/udev/rules.d/92-huawei.rules

# ========================
# 4. Set Permissions
# ========================
echo "[4/6] Setting permissions..."
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
    echo "=== Error Log ==="
    tail -n 50 /var/log/asterisk/full | grep -i dongle
    exit 1
fi

# Cleanup
rm -rf "$TMP_CONFIG_DIR"
