#!/bin/bash

# Compile shaders for macOS using glslangValidator
# Requires Vulkan SDK to be installed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIRV_DIR="$SCRIPT_DIR/spirv"
TMP_SPV="$SPIRV_DIR/data.spv"

# Find glslangValidator
GLSLANG=""
if command -v glslangValidator &> /dev/null; then
    GLSLANG="glslangValidator"
elif [ -f "/opt/homebrew/bin/glslangValidator" ]; then
    GLSLANG="/opt/homebrew/bin/glslangValidator"
elif [ -f "/usr/local/bin/glslangValidator" ]; then
    GLSLANG="/usr/local/bin/glslangValidator"
elif [ -n "$VULKAN_SDK" ] && [ -f "$VULKAN_SDK/bin/glslangValidator" ]; then
    GLSLANG="$VULKAN_SDK/bin/glslangValidator"
else
    echo "ERROR: glslangValidator not found!"
    echo "Please install Vulkan SDK:"
    echo "  brew install vulkan-headers vulkan-loader"
    echo "  Or download from https://vulkan.lunarg.com/"
    exit 1
fi

echo "Using glslangValidator: $GLSLANG"

# Create spirv directory
mkdir -p "$SPIRV_DIR"

# Find bin2hex (should be in same directory)
BIN2HEX="$SCRIPT_DIR/bin2hex"
if [ ! -f "$BIN2HEX" ]; then
    # Try to compile bin2hex if source exists
    if [ -f "$SCRIPT_DIR/bin2hex.c" ]; then
        echo "Compiling bin2hex..."
        cc -o "$BIN2HEX" "$SCRIPT_DIR/bin2hex.c"
    else
        echo "ERROR: bin2hex not found and cannot compile!"
        exit 1
    fi
fi

# Compile gamma.frag
echo "Compiling gamma.frag..."
"$GLSLANG" -S frag -V -o "$TMP_SPV" "$SCRIPT_DIR/gamma.frag"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to compile gamma.frag"
    exit 1
fi

"$BIN2HEX" "$TMP_SPV" "$SPIRV_DIR/shader_data.c" gamma_frag_spv
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to convert gamma.frag to hex"
    exit 1
fi

rm -f "$TMP_SPV"

echo "Successfully compiled gamma.frag"
echo "Note: You may need to manually merge shader_data.c with existing shaders"

