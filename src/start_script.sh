#!/usr/bin/env bash
set -euo pipefail

# Check if directory exists and remove it or update it
if [ -d "ComfyUI-LTX-0.9.7Template" ]; then
  echo "📂 Directory already exists. Removing it first..."
  rm -rf ComfyUI-LTX-0.9.7Template
fi

echo "📥 Cloning ComfyUI-LTX-0.9.7Template…"
git clone https://github.com/Hearmeman24/ComfyUI-LTX-0.9.7Template.git

echo "📂 Moving start.sh into place…"
mv ComfyUI-LTX-0.9.7Template/src/start.sh /

echo "▶️ Running start.sh"
bash /start.sh