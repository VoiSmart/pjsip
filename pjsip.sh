#!/bin/bash

HAS_VIDEO=1 # set to zero to disable video

# see http://stackoverflow.com/a/3915420/318790
function realpath { echo $(cd $(dirname "$1"); pwd)/$(basename "$1"); }
__FILE__=`realpath "$0"`
__DIR__=`dirname "${__FILE__}"`

# clone pjproject at the given tag, reset cleanly if already present
function clone_pjsip() {
    DIR=$1
    TAG=$2
    if [ ! -d "${DIR}/.git" ]; then
        if [ -d "${DIR}" ]; then
            rm -rf "${DIR}"
        fi
        echo "Cloning pjproject ${TAG}..."
        git clone https://github.com/pjsip/pjproject.git "${DIR}"
    else
        echo "Using existing pjproject clone, resetting to ${TAG}..."
        git -C "${DIR}" fetch --tags
    fi
    git -C "${DIR}" reset --hard
    git -C "${DIR}" checkout "${TAG}"
}

DEVELOPER=$(xcode-select --print-path)

IPHONEOS_DEPLOYMENT_VERSION=${IOS_MIN_SDK_VERSION:-"15.0"}
IPHONEOS_PLATFORM=$(xcrun --sdk iphoneos --show-sdk-platform-path)
IPHONEOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)

IPHONESIMULATOR_PLATFORM=$(xcrun --sdk iphonesimulator --show-sdk-platform-path)
IPHONESIMULATOR_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)

OSX_DEPLOYMENT_VERSION=${MACOS_MIN_SDK_VERSION:-"10.12"}
OSX_PLATFORM=$(xcrun --sdk macosx --show-sdk-platform-path)
OSX_SDK=$(xcrun --sdk macosx --show-sdk-path)
BASE_DIR="$1"
PJSIP_DIR="$1/src"
LIB_PATHS=("pjlib/lib" \
           "pjlib-util/lib" \
           "pjmedia/lib" \
           "pjnath/lib" \
           "pjsip/lib" \
           "third_party/lib")

OPENSSL_PREFIX=
OPUS_PREFIX=
G729_PREFIX=
while [ "$#" -gt 0 ]; do
    case $1 in
        --with-openssl)
            if [ "$#" -gt 1 ]; then
                OPENSSL_PREFIX=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$2")
                shift 2
                continue
            else
                echo 'ERROR: Must specify a non-empty "--with-openssl PREFIX" argument.' >&2
                exit 1
            fi
            ;;
        --with-opus)
            if [ "$#" -gt 1 ]; then
                OPUS_PREFIX=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$2")
                shift 2
                continue
            else
                echo 'ERROR: Must specify a non-empty "--with-opus PREFIX" argument.' >&2
                exit 1
            fi
            ;;
        --with-g729)
						if [ "$#" -gt 1 ]; then
                G729_PREFIX=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$2")
                shift 2
                continue
            else
                echo 'ERROR: Must specify a non-empty "--with-g729 PREFIX" argument.' >&2
                exit 1
            fi
						;;
    esac

    shift
done

function configure() {
	TYPE=$1
	ARCH=$2
	LOG=$3

	PJSIP_CONFIG_PATH="${PJSIP_DIR}/pjlib/include/pj/config_site.h"
	CONFIGURE=

	echo "Configuring for ${TYPE} ${ARCH}"

	if [ -f "${PJSIP_CONFIG_PATH}" ]; then
		rm "${PJSIP_CONFIG_PATH}"
	fi


	if [ "$TYPE" == "macos" ]; then
		# macOS
		# Disable SDL (default: not disabled), not available on every platform
		# Disable ffmpeg (default: not disabled), using VideoToolbox
		CONFIGURE="./configure --disable-ffmpeg --disable-sdl"
	elif [ "$TYPE" == "ios" ]; then
		# iOS
		CONFIGURE="./configure-iphone"
		echo "#define PJ_CONFIG_IPHONE 1" >> "${PJSIP_CONFIG_PATH}"
		echo "#undef PJ_IPHONE_OS_HAS_MULTITASKING_SUPPORT" >> "${PJSIP_CONFIG_PATH}"
		echo "#define PJ_IPHONE_OS_HAS_MULTITASKING_SUPPORT 0" >> "${PJSIP_CONFIG_PATH}" # for iOS 9+
		echo "#define PJSIP_MAX_PKT_LEN 6000" >> "${PJSIP_CONFIG_PATH}"
		echo "#define PJSIP_TRANSPORT_IDLE_TIME 600" >> "${PJSIP_CONFIG_PATH}"
		if [[ ${HAS_VIDEO} ]]; then
			echo "#define PJMEDIA_VIDEO_DEV_HAS_OPENGL 1" >> "${PJSIP_CONFIG_PATH}"
			echo "#define PJMEDIA_VIDEO_DEV_HAS_OPENGL_ES 1" >> "${PJSIP_CONFIG_PATH}"
			echo "#define PJMEDIA_VIDEO_DEV_HAS_IOS_OPENGL 1" >> "${PJSIP_CONFIG_PATH}"
			echo "#include <OpenGLES/ES3/glext.h>" >> "${PJSIP_CONFIG_PATH}"
		fi
	fi

	if [[ ${HAS_VIDEO} ]]; then
		echo "#define PJMEDIA_HAS_VIDEO 1" >> "${PJSIP_CONFIG_PATH}"
		echo "#define PJMEDIA_HAS_VID_TOOLBOX_CODEC 1" >> "${PJSIP_CONFIG_PATH}"
	fi

	echo "#define PJ_HAS_IPV6 1" >> "${PJSIP_CONFIG_PATH}" # Enable IPV6
	echo "#include <pj/config_site_sample.h>" >> "${PJSIP_CONFIG_PATH}" # Include example config

	# flags
	unset DEVPATH
	unset MIN_IOS
	unset CFLAGS
	unset LDFLAGS
	if [ "$TYPE" == "macos" ]; then
		# OSX
		export DEVPATH="${OSX_PLATFORM}/Developer"
	elif [ "$TYPE" == "ios" ]; then
		# iOS
		if [ "$ARCH" == "x86_64" ]; then
			export DEVPATH="${IPHONESIMULATOR_PLATFORM}/Developer"
			export CFLAGS="${CFLAGS} -O2 -mios-simulator-version-min=${IPHONEOS_DEPLOYMENT_VERSION}"
			export LDFLAGS="${LDFLAGS} -O2 -mios-simulator-version-min=${IPHONEOS_DEPLOYMENT_VERSION}"
		else
			export MIN_IOS="-miphoneos-version-min=${IPHONEOS_DEPLOYMENT_VERSION}"
			export DEVPATH="${IPHONEOS_PLATFORM}/Developer"
			export CFLAGS="${CFLAGS}"
			export LDFLAGS="${LDFLAGS}"
		fi
	fi


	if [[ ${OPENSSL_PREFIX} ]]; then
		CONFIGURE="${CONFIGURE} --with-ssl=${OPENSSL_PREFIX}"
	fi
	if [[ ${OPUS_PREFIX} ]]; then
		CONFIGURE="${CONFIGURE} --with-opus=${OPUS_PREFIX}"
	fi
    if [[ ${G729_PREFIX} ]]; then
		CONFIGURE="${CONFIGURE} --with-bcg729=${G729_PREFIX}"
	fi

	# flags
	if [[ ! ${CFLAGS} ]]; then
		export CFLAGS=
	fi
	if [[ ! ${LDFLAGS} ]]; then
		export LDFLAGS=
	fi
	if [[ ${OPENSSL_PREFIX} ]]; then
		export CFLAGS="${CFLAGS} -I${OPENSSL_PREFIX}/include"
		if [ "$TYPE" == "ios" ]; then
			export LDFLAGS="${LDFLAGS} -L${OPENSSL_PREFIX}/lib/ios"
		elif [ "$TYPE" == "macos" ]; then
			export LDFLAGS="${LDFLAGS} -L${OPENSSL_PREFIX}/lib/macos"
		fi
	fi
	export LDFLAGS="${LDFLAGS} -lstdc++"
	export CFLAGS="${CFLAGS} -g"

	# log
	if [ -f "${LOG}" ]; then
		rm ${LOG}
		touch ${LOG}
	fi

	clean_libs ${ARCH} ${TYPE}
	make distclean >> ${LOG} 2>&1
	ARCH="-arch ${ARCH}" ${CONFIGURE} >> ${LOG} 2>&1
}

function patch_pjsip() {
    SRC_DIR=$1
    ROOT_DIR=$2
    cd "${SRC_DIR}"
    for PATCH in $(ls "${ROOT_DIR}/patches"/patch-*.patch | sort); do
        echo "Applying ${PATCH}..."
        git apply "${PATCH}"
    done
    cd "${ROOT_DIR}"
    echo "Patch done."
}

function clean_libs () {
    ARCH=${1}
	TYPE=${2}

    for SRC_DIR in ${LIB_PATHS[*]}; do
        DIR="${PJSIP_DIR}/${SRC_DIR}"
        if [ -d "${DIR}" ]; then
            rm -rf "${DIR}"/*
        fi

        DIR="${PJSIP_DIR}/${SRC_DIR}-${TYPE}-${ARCH}"
        if [ -d "${DIR}" ]; then
            rm -rf "${DIR}"
        fi
    done
}

function copy_libs () {
	ARCH=${1}
	TYPE=${2}

	for SRC_DIR in ${LIB_PATHS[*]}; do
		SRC_DIR="${PJSIP_DIR}/${SRC_DIR}"
		DST_DIR="${SRC_DIR}-${TYPE}-${ARCH}"
		if [ -d "${DST_DIR}" ]; then
				rm -rf "${DST_DIR}"
		fi
		cp -R "${SRC_DIR}" "${DST_DIR}"
		rm -rf "${SRC_DIR}"/* # delete files because this directory will be used for the final lipo output
	done
}

function build_arch () {
	ARCH=$1
	SDK=$2
	TYPE=$3

	pushd . > /dev/null
	cd ${PJSIP_DIR}

	LOG=${BASE_DIR}/${TYPE}-${ARCH}.log

	configure $TYPE $ARCH $LOG

	echo "Building for ${TYPE} ${ARCH}..."
	make dep >> ${LOG} 2>&1
	make clean >> ${LOG}
	make lib >> ${LOG} 2>&1

	copy_libs ${ARCH} ${TYPE}

	popd > /dev/null
}

# Map architecture identifier to the name used in compiled library filenames.
# arm64 compilers produce "aarch64" in the filename; everything else matches.
function lib_arch_name() {
	case $1 in
		arm64) echo "aarch64" ;;
		*) echo "$1" ;;
	esac
}

function do_lipo() {
	TYPE=$1
	shift
	TMP=`mktemp -t lipo`
	echo "Lipo libs... (${TMP})"

	FIRST_ARCH=$1
	FIRST_LIB_ARCH=$(lib_arch_name ${FIRST_ARCH})

	for LIB_DIR in ${LIB_PATHS[*]}; do # loop over libs
		DST_DIR="${PJSIP_DIR}/${LIB_DIR}"

		# use the first architecture to find all libraries
		PATTERN_DIR="${DST_DIR}-${TYPE}-${FIRST_ARCH}"
		for PATTERN_FILE in `ls -l1 "${PATTERN_DIR}"`; do
			OPTIONS=""

			# loop over all architectures and collect the current library
			for ARCH in "$@"; do
				LIB_ARCH=$(lib_arch_name ${ARCH})
				FILE="${DST_DIR}-${TYPE}-${ARCH}/${PATTERN_FILE/-${FIRST_LIB_ARCH}-/-${LIB_ARCH}-}"
				if [ -e "${FILE}" ]; then
					OPTIONS="$OPTIONS -arch ${ARCH} ${FILE}"
				fi
			done

			if [ "$OPTIONS" != "" ]; then
				OUTPUT_PREFIX=$(dirname "${DST_DIR}")
				OUTPUT="${OUTPUT_PREFIX}/lib/${PATTERN_FILE/-${FIRST_LIB_ARCH}-/-}"

				OPTIONS="${OPTIONS} -create -output ${OUTPUT}"
				echo "$OPTIONS" >> "${TMP}"
			fi
		done
	done

	while read LINE; do
		lipo ${LINE}
	done < "${TMP}"
}

clone_pjsip "${PJSIP_DIR}" "${PJSIP_VERSION}"

patch_pjsip "${PJSIP_DIR}" "${__DIR__}"

build_arch "x86_64" "${IPHONESIMULATOR_SDK}" "ios"
build_arch "arm64" "${IPHONEOS_SDK}" "ios"

do_lipo "ios" "x86_64" "arm64"
