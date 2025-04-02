#!/bin/bash

# Variables
SOURCEFORGE_USER="belowzeroiq"
SOURCEFORGE_PROJECT="tnf-images"
SOURCEFORGE_PATH="/home/frs/project/$SOURCEFORGE_PROJECT"
PARTITIONS=("boot" "system" "system_ext" "product" "vendor" "odm")
MAKEFILENAME="lineage_topaz"
VARIANT="userdebug"
DEVICE_CODENAME="topaz"
TARGET_FILES="out/target/product/$DEVICE_CODENAME/ota_target_files.zip"
OTA_ZIP="out/target/product/$DEVICE_CODENAME/lineage_${MAKEFILENAME}_${VARIANT}.zip"

# Function to check and download partition images from SourceForge
download_partition() {
  local partition="$1"
  local filename="${partition}.img"
  local image_dir="out/target/product/$DEVICE_CODENAME"

  echo "Checking for existing $filename on SourceForge..."

  LATEST_IMG=$(wget -qO- "https://sourceforge.net/projects/$SOURCEFORGE_PROJECT/files/" | \
    grep -oP "${partition}\.img" | sort | tail -n1)

  if [ -n "$LATEST_IMG" ]; then
    echo "$filename found. Downloading..."
    DOWNLOAD_URL="https://downloads.sourceforge.net/project/$SOURCEFORGE_PROJECT/$filename"
    wget -O "$image_dir/$filename" "$DOWNLOAD_URL"
  else
    echo "$filename not found. It will be built."
  fi
}

# Function to upload files to SourceForge
upload_file() {
  local file_path="$1"
  local file_name=$(basename "$file_path")

  if [ -f "$file_path" ]; then
    echo "Uploading $file_name to SourceForge..."
    if [ -z "$SOURCEFORGE_PASSWORD" ]; then
      echo "Error: SOURCEFORGE_PASSWORD environment variable is not set."
      exit 1
    fi
    sshpass -p "$SOURCEFORGE_PASSWORD" rsync -avz -e "ssh -o StrictHostKeyChecking=no" "$file_path" "$SOURCEFORGE_USER@frs.sourceforge.net:$SOURCEFORGE_PATH/"
    echo "$file_name uploaded successfully."
  else
    echo "Skipping upload. $file_name not found."
  fi
}

# Function to build a partition
build_partition() {
  local partition="$1"
  echo "Building $partition image..."
  source build/envsetup.sh || . build/envsetup.sh
  lunch $MAKEFILENAME-$VARIANT
  m "$partition"image -j$(( $(nproc --all) - 1 ))
  upload_file "out/target/product/$DEVICE_CODENAME/${partition}.img"  # Upload immediately after building
}

# Function to generate `payload.bin` and OTA ZIP
generate_ota_zip() {
  echo "Generating OTA ZIP with payload.bin..."

  # Build the target-files package first
  source build/envsetup.sh
  lunch $MAKEFILENAME-$VARIANT
  m dist

  # Check if the target-files package was generated
  if [ ! -f "$TARGET_FILES" ]; then
    echo "Error: Target files package ($TARGET_FILES) not found."
    exit 1
  fi

  # Use `ota_from_target_files` to create the OTA ZIP (with payload.bin)
  ./build/tools/releasetools/ota_from_target_files -v \
    -p out/host/linux-x86 \
    --block \
    --full \
    "$TARGET_FILES" "$OTA_ZIP"

  # Upload the OTA ZIP after generation
  upload_file "$OTA_ZIP"
}

# Main execution
for partition in "${PARTITIONS[@]}"; do
  download_partition "$partition"
  if [ ! -f "out/target/product/$DEVICE_CODENAME/${partition}.img" ]; then
    build_partition "$partition"
  fi
done

echo "All partitions processed. Generating OTA ZIP..."
generate_ota_zip

echo "ROM build process completed."
