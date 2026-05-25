#!/bin/sh

function realpath { echo $(cd $(dirname "$1"); pwd)/$(basename "$1"); }
__FILE__=`realpath "$0"`
__DIR__=`dirname "${__FILE__}"`

BASEDIR_PATH="$1"
VERSION=${G729_VERSION:-"1.1.1"}
TARGET_URL="https://github.com/BelledonneCommunications/bcg729/archive/refs/tags/${VERSION}.zip"
TARGET_PATH="${BASEDIR_PATH}/src"
ARCHS="arm64;x86_64"

# download
function download() {
    "${__DIR__}/download.sh" "$1" "$2" #--no-cache
}

# build
function build() {
    PREFIX="${BASEDIR_PATH}"
    LOG="${PREFIX}/build.log"

    pushd . > /dev/null
    cd "${TARGET_PATH}"

    echo "Builing for ${ARCHS}..."

    cmake . -DCMAKE_INSTALL_PREFIX=$PREFIX \
      -DCMAKE_SYSTEM_NAME=iOS \
      -DCMAKE_OSX_ARCHITECTURES=$ARCHS \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=15 \
      -DCMAKE_IOS_INSTALL_COMBINED=YES \
      -DENABLE_SHARED=NO
    
    make >> "${LOG}"
    make install >> "${LOG}"
    make clean >> "${LOG}"

    popd > /dev/null
}

download ${TARGET_URL} ${TARGET_PATH}
build 
