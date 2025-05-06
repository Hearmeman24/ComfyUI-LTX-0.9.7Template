#!/usr/bin/env bash

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# This is in case there's any special installs or overrides that needs to occur when starting the machine before starting ComfyUI
if [ -f "/workspace/additional_params.sh" ]; then
    chmod +x /workspace/additional_params.sh
    echo "Executing additional_params.sh..."
    /workspace/additional_params.sh
else
    echo "additional_params.sh not found in /workspace. Skipping..."
fi

# Set the network volume path
NETWORK_VOLUME="/workspace"

# Check if NETWORK_VOLUME exists; if not, use root directory instead
if [ ! -d "$NETWORK_VOLUME" ]; then
    echo "NETWORK_VOLUME directory '$NETWORK_VOLUME' does not exist. You are NOT using a network volume. Setting NETWORK_VOLUME to '/' (root directory)."
    NETWORK_VOLUME="/"
    echo "NETWORK_VOLUME directory doesn't exist. Starting JupyterLab on root directory..."
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/ &
else
    echo "NETWORK_VOLUME directory exists. Starting JupyterLab..."
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/workspace &
fi

COMFYUI_DIR="$NETWORK_VOLUME/ComfyUI"
WORKFLOW_DIR="$NETWORK_VOLUME/ComfyUI/user/default/workflows"

# Set the target directory
CUSTOM_NODES_DIR="$NETWORK_VOLUME/ComfyUI/custom_nodes"

if [ ! -d "$COMFYUI_DIR" ]; then
    mv /ComfyUI "$COMFYUI_DIR"
else
    echo "Directory already exists, skipping move."
fi

echo "Downloading CivitAI download script to /usr/local/bin"
git clone "https://github.com/Hearmeman24/CivitAI_Downloader.git" || { echo "Git clone failed"; exit 1; }
mv CivitAI_Downloader/download.py "/usr/local/bin/" || { echo "Move failed"; exit 1; }
chmod +x "/usr/local/bin/download.py" || { echo "Chmod failed"; exit 1; }
rm -rf CivitAI_Downloader  # Clean up the cloned repo

# Change to the directory
cd "$CUSTOM_NODES_DIR" || exit 1

# Function to download a model using huggingface-cli
download_model() {
  local destination_dir="$1"
  local destination_file="$2"
  local repo_id="$3"
  local file_path="$4"

  mkdir -p "$destination_dir"

  if [ ! -f "$destination_dir/$destination_file" ]; then
    echo "Downloading $destination_file..."

    # First, download to a temporary directory
    local temp_dir=$(mktemp -d)
    huggingface-cli download "$repo_id" "$file_path" --local-dir "$temp_dir" --resume-download

    # Find the downloaded file in the temp directory (may be in subdirectories)
    local downloaded_file=$(find "$temp_dir" -type f -name "$(basename "$file_path")")

    # Move it to the destination directory with the correct name
    if [ -n "$downloaded_file" ]; then
      mv "$downloaded_file" "$destination_dir/$destination_file"
      echo "Successfully downloaded to $destination_dir/$destination_file"
    else
      echo "Error: File not found after download"
    fi

    # Clean up temporary directory
    rm -rf "$temp_dir"
  else
    echo "$destination_file already exists, skipping download."
  fi
}

# Define base paths
CHECKPOINT_DIR="$NETWORK_VOLUME/ComfyUI/models/checkpoints"
TEXT_ENCODERS_DIR="$NETWORK_VOLUME/ComfyUI/models/text_encoders"
UPSCALE_DIR="$NETWORK_VOLUME/ComfyUI/models/upscale_models"

if [ "$download_full_model" == "true" ]; then
  echo "Downloading full LTX models..."

  download_model "$CHECKPOINT_DIR" "ltxv-13b-0.9.7-dev.safetensors" \
  "Lightricks/LTX-Video" "ltxv-13b-0.9.7-dev.safetensors"
fi

if [ "$download_quantized_model" == "true" ]; then
  echo "Downloading quantized LTX models..."

  download_model "$CHECKPOINT_DIR" "ltxv-13b-0.9.7-dev-fp8.safetensors" \
  "Lightricks/LTX-Video" "ltxv-13b-0.9.7-dev-fp8.safetensors"

  echo "Installing Q8 Kernels"
  cd "ComfyUI-LTX-0.9.7Template" || { echo "Error: Directory ComfyUI-LTX-0.9.7Template not found"; exit 1; }

  # Check if wheel exists
  if [ ! -f "q8_kernels-0.0.4-cp312-cp312-linux_x86_64.whl" ]; then
      echo "Error: Q8 Kernels wheel file not found"
      exit 1
  fi

  # Check Python version compatibility
  PYTHON_VERSION=$(python --version | cut -d' ' -f2 | cut -d'.' -f1,2)
  if [[ "$PYTHON_VERSION" != "3.12" ]]; then
      echo "Warning: Q8 Kernels wheel is built for Python 3.12, but current Python is $PYTHON_VERSION"
      echo "Attempting to install a compatible version instead..."

      # Try to find a compatible wheel file
      COMPATIBLE_WHEEL=$(find . -name "q8_kernels*.whl" -not -name "*cp312*" | grep -i $(python -c "import platform; print(platform.machine())") | head -1)

      if [ -n "$COMPATIBLE_WHEEL" ]; then
          echo "Found compatible wheel: $COMPATIBLE_WHEEL"
          pip install "$COMPATIBLE_WHEEL" || echo "Warning: Installation failed, continuing anyway"
      else
          echo "No compatible wheel found. Skipping Q8 Kernels installation."
      fi
  else
      # Install the specified wheel
      pip install q8_kernels-0.0.4-cp312-cp312-linux_x86_64.whl || echo "Warning: Installation failed, continuing anyway"
  fi

  echo "Q8 Kernels installation step completed"
fi

# Download text encoders
echo "Downloading text encoders..."

download_model "$TEXT_ENCODERS_DIR" "t5xxl_fp16.safetensors" \
  "comfyanonymous/flux_text_encoders" "t5xxl_fp16.safetensors"

# Download upscale model
echo "Downloading upscale models"
download_model "$UPSCALE_DIR" "ltxv-spatial-upscaler-0.9.7.safetensors" \
  "Lightricks/LTX-Video" "ltxv-spatial-upscaler-0.9.7.safetensors"

download_model "$UPSCALE_DIR" "ltxv-temporal-upscaler-0.9.7.safetensors" \
  "Lightricks/LTX-Video" "ltxv-temporal-upscaler-0.9.7.safetensors"

echo "Finished downloading models!"

echo "Checking and copying workflow..."
mkdir -p "$WORKFLOW_DIR"

# Ensure the file exists in the current directory before moving it
cd /

SOURCE_DIR="/ComfyUI-LTX-0.9.7Template/workflows"

# Ensure destination directory exists
mkdir -p "$WORKFLOW_DIR"

# Loop over each file in the source directory
for file in "$SOURCE_DIR"/*; do
    # Skip if it's not a file
    [[ -f "$file" ]] || continue

    dest_file="$WORKFLOW_DIR/$(basename "$file")"

    if [[ -e "$dest_file" ]]; then
        echo "File already exists in destination. Deleting: $file"
        rm -f "$file"
    else
        echo "Moving: $file to $WORKFLOW_DIR"
        mv "$file" "$WORKFLOW_DIR"
    fi
done

declare -A MODEL_CATEGORIES=(
    ["$NETWORK_VOLUME/ComfyUI/models/checkpoints"]="CHECKPOINT_IDS_TO_DOWNLOAD"
    ["$NETWORK_VOLUME/ComfyUI/models/loras"]="LORAS_IDS_TO_DOWNLOAD"
)

# Ensure directories exist and download models
for TARGET_DIR in "${!MODEL_CATEGORIES[@]}"; do
    ENV_VAR_NAME="${MODEL_CATEGORIES[$TARGET_DIR]}"
    MODEL_IDS_STRING="${!ENV_VAR_NAME}"  # Get the value of the environment variable

    # Skip if the environment variable is set to "ids_here"
    if [ "$MODEL_IDS_STRING" == "replace_with_ids" ]; then
        echo "Skipping downloads for $TARGET_DIR ($ENV_VAR_NAME is 'ids_here')"
        continue
    fi

    mkdir -p "$TARGET_DIR"
    IFS=',' read -ra MODEL_IDS <<< "$MODEL_IDS_STRING"

    for MODEL_ID in "${MODEL_IDS[@]}"; do
        echo "Downloading model: $MODEL_ID to $TARGET_DIR"
        (cd "$TARGET_DIR" && download.py --model "$MODEL_ID")
    done
done

# Workspace as main working directory
echo "cd $NETWORK_VOLUME" >> ~/.bashrc

# Start ComfyUI
echo "Starting ComfyUI"
python "$NETWORK_VOLUME/ComfyUI/main.py" --listen --use-sage-attention --preview-method auto
    if [ $? -ne 0 ]; then
        echo "ComfyUI failed with --use-sage-attention. Retrying without it..."
        python "$NETWORK_VOLUME/ComfyUI/main.py" --listen --preview-method auto
    fi
