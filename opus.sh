#!/bin/bash
#  Builds libopus for all three current iPhone targets: iPhoneSimulator-i386,
#  iPhoneOS-armv6, iPhoneOS-armv7.
#
#  Copyright 2012 Mike Tigas <mike@tig.as>
#
#  Based on work by Felix Schulze on 16.12.10.
#  Copyright 2010 Felix Schulze. All rights reserved.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
###########################################################################
#  Choose your libopus version and your currently-installed iOS SDK version:
#
VERSION=${OPUS_VERSION:-"1.6.1"}
SDKVERSION=$(xcrun -sdk iphoneos --show-sdk-version)
MINIOSVERSION=${IOS_MIN_SDK_VERSION:-"15.0"}

###########################################################################
#
# Don't change anything under this line!
#
###########################################################################

# by default, we won't build for debugging purposes
if [ "${DEBUG}" == "true" ]; then
    echo "Compiling for debugging ..."
    OPT_CFLAGS="-O0 -fno-inline -g"
    OPT_LDFLAGS=""
    OPT_CONFIG_ARGS="--enable-assertions --disable-asm"
else
    OPT_CFLAGS="-O3 -ffast-math -flto -g"
    OPT_LDFLAGS="-flto"
    OPT_CONFIG_ARGS=""
fi


ARCHS="arm64 x86_64"

DEVELOPER=`xcode-select -print-path`

REPOROOT=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1")

OUTPUTDIR="${REPOROOT}/dependencies"
mkdir -p "${OUTPUTDIR}/include"
mkdir -p "${OUTPUTDIR}/lib"

BUILDDIR="${REPOROOT}/build"
SRCDIR="${BUILDDIR}/src"
mkdir -p $SRCDIR
INTERDIR="${BUILDDIR}/built"
mkdir -p $INTERDIR

########################################

cd $SRCDIR

set -e

if [ ! -e "${SRCDIR}/opus-${VERSION}.tar.gz" ]; then
	echo "Downloading opus-${VERSION}.tar.gz"
	curl -fL --retry 3 --show-error "https://downloads.xiph.org/releases/opus/opus-${VERSION}.tar.gz" -o "opus-${VERSION}.tar.gz"
fi
echo "Using opus-${VERSION}.tar.gz"

tar zxf opus-${VERSION}.tar.gz
cd "${SRCDIR}/opus-${VERSION}"

for ARCH in ${ARCHS}
do
	echo "** Compiling ${ARCH}"
    if [ "${ARCH}" == "x86_64" ]; then
        PLATFORM="iPhoneSimulator"
        HOST="x86_64-apple-darwin"
    else
        PLATFORM="iPhoneOS"
        HOST="aarch64-apple-darwin"
    fi

    SDK_PATH="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer/SDKs/${PLATFORM}${SDKVERSION}.sdk"
    CC=$(xcrun -sdk $(echo ${PLATFORM} | tr '[:upper:]' '[:lower:]') -find clang)

	mkdir -p "${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk"

	./configure \
		--enable-float-approx --disable-shared --enable-static \
		--with-pic --disable-extra-programs --disable-doc \
		--host="${HOST}" \
		--prefix="${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk" \
		CC="${CC}" \
		LDFLAGS="${OPT_LDFLAGS} -fPIE -miphoneos-version-min=${MINIOSVERSION} -L${OUTPUTDIR}/lib" \
		CFLAGS="-arch ${ARCH} ${OPT_CFLAGS} -fPIE -miphoneos-version-min=${MINIOSVERSION} -I${OUTPUTDIR}/include -isysroot ${SDK_PATH}"

	make -j8
	make install
	make clean
done

########################################

echo "Build library..."

# These are the libs that comprise libopus.
OUTPUT_LIBS="libopus.a"
for OUTPUT_LIB in ${OUTPUT_LIBS}; do
	INPUT_LIBS=""
	for ARCH in ${ARCHS}; do
		if [ "${ARCH}" == "x86_64" ]; then
			PLATFORM="iPhoneSimulator"
		else
			PLATFORM="iPhoneOS"
		fi
		INPUT_ARCH_LIB="${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk/lib/${OUTPUT_LIB}"
		if [ -e $INPUT_ARCH_LIB ]; then
			INPUT_LIBS="${INPUT_LIBS} ${INPUT_ARCH_LIB}"
		fi
	done
	# Combine the three architectures into a universal library.
	if [ -n "$INPUT_LIBS"  ]; then
		echo "** lipo libs"
		lipo -create $INPUT_LIBS \
		-output "${OUTPUTDIR}/lib/${OUTPUT_LIB}"
	else
		echo "$OUTPUT_LIB does not exist, skipping (are the dependencies installed?)"
	fi
done

for ARCH in ${ARCHS}; do
	if [ "${ARCH}" == "x86_64" ]; then
		PLATFORM="iPhoneSimulator"
	else
		PLATFORM="iPhoneOS"
	fi
	cp -R ${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk/include/* ${OUTPUTDIR}/include/
	if [ $? == "0" ]; then
		break
	fi
done


####################

echo "Building done."
echo "Cleaning up..."
rm -fr ${INTERDIR}
rm -fr "${SRCDIR}/opus-${VERSION}"
echo "Done."
