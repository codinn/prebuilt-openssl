#!/bin/bash

# This script builds the iOS and Mac openSSL libraries with Bitcode enabled
# Download openssl http://www.openssl.org/source/ and place the tarball next to this script

# Credits:
# https://github.com/st3fan/ios-openssl
# https://github.com/x2on/OpenSSL-for-iPhone/blob/master/build-libssl.sh
# Peter Steinberger, PSPDFKit GmbH, @steipete.
# Doron Adler, GlideTalk, @Norod78, @yangyubo

# Updated to work with Xcode 7 and iOS 9
# Updated to set OS X minimum deploy target version

set -e

###################################
#      OpenSSL Version
###################################
OPENSSL_VERSION="openssl-1.0.2d"
###################################

###################################
#      OpenSSL Version
###################################
OSX_DIST_OUTPUT="${OPENSSL_VERSION}-osx"
IOS_DIST_OUTPUT="${OPENSSL_VERSION}-ios"
###################################

###################################
#      SDK Version
###################################
IOS_SDK_VERSION=$(xcodebuild -version -sdk iphoneos | grep SDKVersion | cut -f2 -d ':' | tr -d '[[:space:]]')
OSX_SDK_VERSION=$(xcodebuild -version -sdk macosx | grep SDKVersion | cut -f2 -d ':' | tr -d '[[:space:]]')
###################################

################################################
#      Minimum deployment target version
################################################
OSX_DEPLOYMENT_VERSION="10.9"
IOS_DEPLOYMENT_VERSION="7.0"

DEVELOPER=`xcode-select -print-path`

buildMac()
{
   ARCH=$1

   echo "Start Building ${OPENSSL_VERSION} for OS X ${OSX_SDK_VERSION} ${ARCH}"

   TARGET="darwin64-x86_64-cc"
   
   export CC="${BUILD_TOOLS}/usr/bin/clang -mmacosx-version-min=${OSX_DEPLOYMENT_VERSION}"

   pushd . > /dev/null
   cd "${OPENSSL_VERSION}"
   echo "Configure"
   ./Configure ${TARGET} --openssldir="/tmp/${OPENSSL_VERSION}-${ARCH}" &> "/tmp/${OPENSSL_VERSION}-${ARCH}.log"
   make >> "/tmp/${OPENSSL_VERSION}-${ARCH}.log" 2>&1
   echo "make install"
   make install >> "/tmp/${OPENSSL_VERSION}-${ARCH}.log" 2>&1
   echo "make clean"
   make clean >> "/tmp/${OPENSSL_VERSION}-${ARCH}.log" 2>&1
   popd > /dev/null
   
   echo "Done Building ${OPENSSL_VERSION} for OS X ${OSX_SDK_VERSION} ${ARCH}"
}

buildIOS()
{
   ARCH=$1
   
   pushd . > /dev/null
   cd "${OPENSSL_VERSION}"
  
   if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
      PLATFORM="iPhoneSimulator"
   else
      PLATFORM="iPhoneOS"
      sed -ie "s!static volatile sig_atomic_t intr_signal;!static volatile intr_signal;!" "crypto/ui/ui_openssl.c"
   fi
  
   export $PLATFORM
   export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
   export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
   export BUILD_TOOLS="${DEVELOPER}"
   export CC="${BUILD_TOOLS}/usr/bin/gcc -fembed-bitcode -mios-version-min=${IOS_DEPLOYMENT_VERSION} -arch ${ARCH}"

   echo "Start Building ${OPENSSL_VERSION} for ${PLATFORM} ${IOS_SDK_VERSION} ${ARCH}"
   
   echo "Configure"

   if [[ "${ARCH}" == "x86_64" ]]; then
      ./Configure darwin64-x86_64-cc --openssldir="/tmp/${OPENSSL_VERSION}-iOS-${ARCH}" &> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log"
   else
      ./Configure iphoneos-cross --openssldir="/tmp/${OPENSSL_VERSION}-iOS-${ARCH}" &> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log"
   fi
   # add -isysroot to CC=
   sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mios-version-min=${IOS_DEPLOYMENT_VERSION} !" "Makefile"

   echo "make"
   make >> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log" 2>&1
   echo "make install"
   make install >> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log" 2>&1
   echo "make clean"
   make clean  >> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log" 2>&1
   popd > /dev/null
   
   echo "Done Building ${OPENSSL_VERSION} for ${PLATFORM} ${IOS_SDK_VERSION} ${ARCH}"
}

echo "Cleaning up"
rm -rf ${IOS_DIST_OUTPUT}/* ${OSX_DIST_OUTPUT}/*

mkdir -p ${IOS_DIST_OUTPUT}/lib
mkdir -p ${IOS_DIST_OUTPUT}/include/openssl/

mkdir -p ${OSX_DIST_OUTPUT}/lib
mkdir -p ${OSX_DIST_OUTPUT}/include/openssl/

rm -rf "/tmp/${OPENSSL_VERSION}-*"
rm -rf "/tmp/${OPENSSL_VERSION}-*.log"

rm -rf "${OPENSSL_VERSION}"

if [ ! -e ${OPENSSL_VERSION}.tar.gz ]; then
   echo "Downloading ${OPENSSL_VERSION}.tar.gz"
   curl -O https://www.openssl.org/source/${OPENSSL_VERSION}.tar.gz
else
   echo "Using ${OPENSSL_VERSION}.tar.gz"
fi

echo "Unpacking openssl"
tar xfz "${OPENSSL_VERSION}.tar.gz"

echo "----------------------------------------"
echo "OpenSSL version: ${OPENSSL_VERSION}"
echo "OSX SDK version: ${OSX_SDK_VERSION}"
echo "OSX deployment target: ${OSX_DEPLOYMENT_VERSION}"
echo "----------------------------------------"
echo " "

buildMac "x86_64"

echo "Copying OSX headers"
cp /tmp/${OPENSSL_VERSION}-x86_64/include/openssl/* ${OSX_DIST_OUTPUT}/include/openssl/

echo "Copying OSX libraries"
cp /tmp/${OPENSSL_VERSION}-x86_64/lib/libcrypto.a ${OSX_DIST_OUTPUT}/lib/libcrypto.a
cp /tmp/${OPENSSL_VERSION}-x86_64/lib/libssl.a ${OSX_DIST_OUTPUT}/lib/libssl.a

echo "----------------------------------------"
echo "OpenSSL version: ${OPENSSL_VERSION}"
echo "iOS SDK version: ${IOS_SDK_VERSION}"
echo "iOS deployment target: ${IOS_DEPLOYMENT_VERSION}"
echo "----------------------------------------"
echo " "

buildIOS "armv7"
buildIOS "arm64"
buildIOS "x86_64"
buildIOS "i386"

echo "Copying iOS headers"
cp /tmp/${OPENSSL_VERSION}-iOS-arm64/include/openssl/* ${IOS_DIST_OUTPUT}/include/openssl/

echo "Building iOS libraries"
lipo \
   "/tmp/${OPENSSL_VERSION}-iOS-armv7/lib/libcrypto.a" \
   "/tmp/${OPENSSL_VERSION}-iOS-arm64/lib/libcrypto.a" \
   "/tmp/${OPENSSL_VERSION}-iOS-i386/lib/libcrypto.a" \
   "/tmp/${OPENSSL_VERSION}-iOS-x86_64/lib/libcrypto.a" \
   -create -output ${IOS_DIST_OUTPUT}/lib/libcrypto.a

lipo \
   "/tmp/${OPENSSL_VERSION}-iOS-armv7/lib/libssl.a" \
   "/tmp/${OPENSSL_VERSION}-iOS-arm64/lib/libssl.a" \
   "/tmp/${OPENSSL_VERSION}-iOS-i386/lib/libssl.a" \
   "/tmp/${OPENSSL_VERSION}-iOS-x86_64/lib/libssl.a" \
   -create -output ${IOS_DIST_OUTPUT}/lib/libssl.a

echo "Cleaning up"
rm -rf /tmp/${OPENSSL_VERSION}-*
rm -rf ${OPENSSL_VERSION}

echo "Done"
