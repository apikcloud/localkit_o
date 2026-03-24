#!/bin/bash
set -e

# Create config directory and link odoo config
mkdir -p /mnt/extra-addons/.config
ln -sf /etc/odoo /mnt/extra-addons/.config/

# Install Python dependencies if requirements.txt exists in the addons
REQ_FILE=$(find /mnt/extra-addons -maxdepth 2 -name "requirements.txt" | head -1)
if [ -n "$REQ_FILE" ]; then
    pip install --upgrade pip
    pip install -r "$REQ_FILE"
fi

# Gitnexus Analysis
if [ -d "/mnt/extra-addons/.git" ]; then
    echo "Running Gitnexus analysis..."
    gitnexus analyze /mnt/extra-addons --output-format json --output-file /gitnexus_report.json
else
    echo "No .git directory found in /mnt/extra-addons. Skipping Gitnexus analysis."
fi


