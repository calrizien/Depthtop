#!/bin/bash

# Build Metal binary archive for Depthtop
# This script compiles Metal shaders into a binary archive to avoid runtime compilation

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR"
SHADER_DIR="$PROJECT_DIR/Depthtop"
BUILD_DIR="$PROJECT_DIR/build"

# Create build directory if it doesn't exist
mkdir -p "$BUILD_DIR"

# Compile Metal shaders to AIR (intermediate representation)
echo "Compiling Shaders.metal to AIR..."
xcrun -sdk macosx metal -c \
    "$SHADER_DIR/Shaders.metal" \
    -o "$BUILD_DIR/Shaders.air" \
    -std=metal3.0 \
    -ffast-math

# Link AIR to create metallib
echo "Creating Metal library..."
xcrun -sdk macosx metallib \
    "$BUILD_DIR/Shaders.air" \
    -o "$BUILD_DIR/default-binaryarchive.metallib"

# Copy to project resources
echo "Copying to project resources..."
cp "$BUILD_DIR/default-binaryarchive.metallib" "$PROJECT_DIR/Depthtop/"

echo "Metal binary archive created successfully!"
echo "Add '$PROJECT_DIR/Depthtop/default-binaryarchive.metallib' to your Xcode project's resources."