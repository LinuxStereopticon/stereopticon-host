#/bin/bash

set -e

SRC_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
cd $SRC_PATH

source common.sh

if [ "$SNAPCRAFT_PART_INSTALL" != "" ]; then
    INSTALL=$SNAPCRAFT_PART_INSTALL/opt/${PROJECT}
else
    INSTALL=/opt/${PROJECT}-${VERSION}
fi

# Internal variables
CLEAN=0
BUILD_DEPS=0

# Platform-specific checking
KERNEL_NAME=$(uname -s)

# Overridable number of build processors
if [ "$NUM_PROCS" == "" ]; then
    if [ "$KERNEL_NAME" == "Linux" ]; then
        NUM_PROCS=$(nproc --all)
    elif [ "$KERNEL_NAME" == "Darwin" ]; then
        NUM_PROCS=$(sysctl -n hw.ncpu)
    else
        # Default to 4 build processors on unknown systems
        NUM_PROCS=4
    fi
fi

# Argument parsing
while [[ $# -gt 0 ]]; do
    arg="$1"
    case $arg in
        -c|--clean)
            CLEAN=1
            shift
        ;;
        -d|--deps)
            BUILD_DEPS=1
            shift
        ;;
        *)
            echo "usage: $0 [-d|--deps] [-c|--clean]"
            exit 1
        ;;
    esac
done

function build_cmake {
    if [ "$CLEAN" == "1" ]; then
        if [ -d build ]; then
            rm -rf build
        fi
    fi
    if [ ! -d build ]; then
        mkdir build
    fi
    cd build
    if [ -f /usr/bin/dpkg-architecture ]; then
        MULTIARCH=$(/usr/bin/dpkg-architecture -qDEB_TARGET_MULTIARCH)
    else
        MULTIARCH=""
    fi

    # Environment-specific compiler flags
    ADDITIONAL_C_FLAGS=""
    ADDITIONAL_CXX_FLAGS=""
    if [ "$KERNEL_NAME" == "Linux" ]; then
        ADDITIONAL_C_FLAGS="-Wl,-rpath-link,$INSTALL/lib"
        ADDITIONAL_CXX_FLAGS="-Wl,-rpath-link,$INSTALL/lib"
    fi

    PKG_CONF_SYSTEM=/usr/lib/$MULTIARCH/pkgconfig
    PKG_CONF_INSTALL=$INSTALL/lib/pkgconfig:$INSTALL/lib/$MULTIARCH/pkgconfig
    PKG_CONFIG_PATH=$PKG_CONFIG_PATH:$PKG_CONF_SYSTEM:$PKG_CONF_INSTALL
    env PKG_CONFIG_PATH=$PKG_CONFIG_PATH LDFLAGS="-L$INSTALL/lib" \
    	cmake .. \
        -DCMAKE_INSTALL_PREFIX=$INSTALL \
        -DCMAKE_MODULE_PATH=$INSTALL \
        -DCMAKE_CXX_FLAGS="-isystem $INSTALL/include -L$INSTALL/lib -Wno-deprecated-declarations $ADDITIONAL_CXX_FLAGS" \
        -DCMAKE_C_FLAGS="-isystem $INSTALL/include -L$INSTALL/lib -Wno-deprecated-declarations $ADDITIONAL_C_FLAGS" \
        -DCMAKE_LD_FLAGS="-L$INSTALL/lib" \
        -DCMAKE_LIBRARY_PATH=$INSTALL/lib $@
    make VERBOSE=1 -j$NUM_PROCS
    if [ -f /usr/bin/sudo ]; then
        sudo make install
    else
        make install
    fi
}

function build_3rdparty_cmake {
    echo "Building: $1"
    cd $SRC_PATH
    cd 3rdparty/$1
    build_cmake $2
}

function build_project_host {
    echo "Building project for host"
    cd $SRC_PATH
    cd src/host
    build_cmake $1
}

# Install Linux distro-provided dependencies
if [ "$KERNEL_NAME" == "Linux" ]; then
    if [ -f /usr/bin/apt ] && [ -f /usr/bin/sudo ]; then
        bash 3rdparty/apt.sh
    elif [ -f /usr/bin/dnf ] && [ -f /usr/bin/sudo ]; then
        bash 3rdparty/dnf.sh
    fi
fi

# Build direct dependencies if requested
if [ "$BUILD_DEPS" == "1" ]; then
    build_3rdparty_cmake SDL
fi

# Build main sources for the host
build_project_host
