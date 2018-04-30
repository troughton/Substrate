#!/bin/bash

# Version Numbers
WINDOWS_KIT_VERSION="10.0.16299.0"
MSVC_VERSION="14.13.26128"
VULKAN_SDK_VERSION="1.1.70.0"

# Detect project root 
PROJECT_ROOT="${BASH_SOURCE%/*}"
if [[ ! -d "$PROJECT_ROOT" ]]; then DIR="$PWD"; fi
cd $PROJECT_ROOT


# Load in config values
source "$PROJECT_ROOT/Config/windows_build.config"


# Set paths to dependencies
WINDOWS_KIT_INCLUDE="$WINDOWS_KIT/Include/$WINDOWS_KIT_VERSION"
WINDOWS_KIT_LIB="$WINDOWS_KIT/Lib/$WINDOWS_KIT_VERSION"
MSVC_INCLUDE="${MSVC}/${MSVC_VERSION}/include"
MSVC_LIB="${MSVC}/${MSVC_VERSION}/lib"
VULKAN_SDK_PATH="${VULKAN_SDK}/${VULKAN_SDK_VERSION}"

SHOULD_EXIT=false
if [ ! -d "$WINDOWS_KIT_INCLUDE" ]; then
    echo "Error: Windows Kit include directory not found at ${WINDOWS_KIT_INCLUDE}. Make sure its version is ${WINDOWS_KIT_VERSION}."
    SHOULD_EXIT=true
fi
if [ ! -d "$WINDOWS_KIT_LIB" ]; then
    echo "Error: Windows Kit lib directory not found at ${WINDOWS_KIT_LIB}. Make sure its version is ${WINDOWS_KIT_VERSION}."
    SHOULD_EXIT=true
fi
if [ ! -d "$MSVC_INCLUDE" ]; then
    echo "Error: MSVC include directory not found at ${MSVC_INCLUDE}. Make sure its version is ${MSVC_VERSION}."
    SHOULD_EXIT=true
fi
if [ ! -d "$MSVC_LIB" ]; then
    echo "Error: MSVC include directory not found at ${MSVC_LIB}. Make sure its version is ${MSVC_VERSION}."
    SHOULD_EXIT=true
fi
if [ ! -d "$VULKAN_SDK_PATH" ]; then
    echo "Error: Vulkan SDK not found at ${MSVC_LIB}. Make sure its version is ${VULKAN_SDK_VERSION}."
    SHOULD_EXIT=true
fi
if [ $SHOULD_EXIT == true ]; then
    exit -1
fi

TEMPLATE_DIRECTORY="$PROJECT_ROOT/Config/Templates/"


export LIB="${MSVC_LIB}/x64;${WINDOWS_KIT_LIB}/ucrt/x64;${WINDOWS_KIT_LIB}/um/x64"


# Handle command line arguments
FIRST_RUN=false
DEBUG=true
while test $# -gt 0
do
    case "$1" in
        --first-run) 
            FIRST_RUN=true
        ;;
        --release)
            DEBUG=false
        ;;
    esac

    shift
done


# Configure for debug or release mode
if [ $DEBUG == true ]; then
    BUILD_CONFIGURATION="debug"
    BUILD_CONFIGURATION_WINDOWS_DEST=$(<$TEMPLATE_DIRECTORY/WindowsDestDebug.template)
else
    BUILD_CONFIGURATION="release"
    BUILD_CONFIGURATION_WINDOWS_DEST=$(<$TEMPLATE_DIRECTORY/WindowsDestRelease.template)
fi


echo "=== Building Interdimensional Llama ($BUILD_CONFIGURATION) ==="
# Check for first run flag
if [ $FIRST_RUN == true ]; then
echo "(First Run)"

CLANG_INCLUDE=""
cp "${TEMPLATE_DIRECTORY}/visualc.modulemap" "${MSVC_INCLUDE}/module.modulemap"
cp "${TEMPLATE_DIRECTORY}/ucrt.modulemap" "${WINDOWS_KIT_INCLUDE}/ucrt/module.modulemap"
else
CLANG_INCLUDE="-Xcc -IClangInclude"
fi

echo ""


#  Compile the shaders
echo "Compiling shaders."
pushd Resources/Engine/Shaders/Vulkan >/dev/null 2>&1
./compile_shaders.sh
popd >/dev/null 2>&1
echo ""


mkdir -p ".build"

# Generate WindowsDest.template
WINDOWS_DEST_PATH=.build/WindowsDest.json
cp "$TEMPLATE_DIRECTORY/WindowsDest.template" $WINDOWS_DEST_PATH
sed -i "s@%{BUILD_CONFIGURATION}@${BUILD_CONFIGURATION_WINDOWS_DEST}@g" $WINDOWS_DEST_PATH
sed -i "s@%{TOOLCHAIN_BIN_DIR}@$TOOLCHAIN_BIN_DIR@g" $WINDOWS_DEST_PATH
sed -i "s@%{VULKAN_SDK_PATH}@$VULKAN_SDK_PATH@g" $WINDOWS_DEST_PATH 


# Generate windows-sdk-vfs-overlay.yaml
WINDOWS_SDK_VFS_OVERLAY_PATH=.build/windows-sdk-vfs-overlay.yaml
cp "$TEMPLATE_DIRECTORY/windows-sdk-vfs-overlay.template" $WINDOWS_SDK_VFS_OVERLAY_PATH
sed -i "s@%{WINDOWS_KIT_INCLUDE}@${WINDOWS_KIT_INCLUDE}@g" $WINDOWS_SDK_VFS_OVERLAY_PATH


# Build the project
swift build --destination ${WINDOWS_DEST_PATH} \
--configuration ${BUILD_CONFIGURATION} \
${CLANG_INCLUDE} \
-Xcc -I"$WINDOWS_KIT_INCLUDE/ucrt" \
-Xcc -I"${MSVC_INCLUDE}" \
-Xcc -I"$WINDOWS_KIT_INCLUDE/um" \
-Xcc -I"$WINDOWS_KIT_INCLUDE/shared" \
-Xcc -ivfsoverlay \
-Xcc ${WINDOWS_SDK_VFS_OVERLAY_PATH} \
-Xcc -I"${VULKAN_SDK_PATH}/Include"