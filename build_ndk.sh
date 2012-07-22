#!/bin/sh

# This script will mostly die eventually. Lots of it exists to patch up
# small problems with new build_host scripts in Google's NDK. The goal
# is that dev-rebuild-ndk.sh would be used once it uses the build_host
# scripts.

PROGNAME=$(basename $0)
PROGDIR=$(dirname $0)
PROGDIR=$(cd $PROGDIR && pwd)

# This will be reset later.
LOG_FILE=/dev/null

HELP=
VERBOSE=1

NDK_VER=r8b
DATESUFFIX=$(date +%y%m%d)
SYSTEMS=linux-x86,windows-x86
BUILD_DIR=/tmp/necessitas
BUILD_DIR_TMP=/tmp/necessitas/ndk-tmp
HOST_TOOLS=$BUILD_DIR/host_compiler_tools
GCC_VER_LINARO=4.6-2012.07
GCC_VER_LINARO_MAJOR=4.6
GCC_VER_LINARO_LOCAL=4.6.3

case $OS in
    linux)
        NUM_CORES=$(grep -c -e '^processor' /proc/cpuinfo)
        ;;
    darwin|freebsd)
        NUM_CORES=`sysctl -n hw.ncpu`
        ;;
    windows|cygwin)
        NUM_CORES=$NUMBER_OF_PROCESSORS
        ;;
    *)
        NUM_CORES=8
        ;;
esac

if [ -z "$JOBS" ] ; then
    JOBS=$NUM_CORES
fi

###############################################################
# Shell script functions essential for processing the options #
###############################################################

log ()
{
    if [ "$LOG_FILE" ]; then
        echo "$@" > $LOG_FILE
    fi
    if [ "$VERBOSE" -gt 0 ]; then
        echo "$@"
    fi
}

info ()
{
    if [ "$LOG_FILE" ]; then
        echo "$@" > $LOG_FILE
    fi
    if [ "$VERBOSE" -gt 1 ]; then
        echo "$@"
    fi
}

panic ()
{
    1>&2 echo "Error: $@"
    exit 1
}

fail_panic ()
{
    if [ $? != 0 ]; then
        panic "$@"
    fi
}

download ()
{
  curl -S -L -O $1
}

for opt; do
    optarg=`expr "x$opt" : 'x[^=]*=\(.*\)'`
    case $opt in
        -h|-?|--help) HELP=true;;
        --verbose) VERBOSE=$(( $VERBOSE + 1 ));;
        --quiet) VERBOSE=$(( $VERBOSE - 1 ));;
        --binprefix=*) HOST_BINPREFIX=$optarg;;
        --systems=*) SYSTEMS=$optarg;;
        --darwinsdk=*) DARWINSDK=$optarg;;
        --targets=*) TARGETS=$optarg;;
        --arches=*) ARCHES=$optarg;;
        --srcdir=*) TC_SRC_DIR=$optarg;;
        --linaro) LINARO=yes;;
        -j*|--jobs=*) JOBS=$optarg;;
        --package-dir=*) PACKAGE_DIR=$optarg;;
        -*) panic "Unknown option '$opt', see --help for list of valid ones.";;
        *) panic "This script doesn't take any parameter, see --help for details.";;
    esac
done

# Translate commas to spaces
# Usage: str=`commas_to_spaces <list>`
commas_to_spaces ()
{
    echo "$@" | tr ',' ' '
}

# Translate spaces to commas
# Usage: list=`spaces_to_commas <string>`
spaces_to_commas ()
{
    echo "$@" | tr ' ' ','
}

# $1 is the string to search for
# $2... is the list to search in
# Returns first, yes or no.
bh_list_contains ()
{
  local SEARCH="$1"
  shift
  # For dash, this has to be split over 2 lines.
  # Seems to be a bug with dash itself:
  # https://bugs.launchpad.net/ubuntu/+source/dash/+bug/141481
  local LIST
  LIST=$@
  local RESULT=first
  # Pull out the host if there
  for ELEMENT in $LIST; do
    if [ "$ELEMENT" = "$SEARCH" ]; then
      echo $RESULT
      return 0
    fi
    RESULT=yes
  done
  echo no
  return 1
}

###################
# Build OS checks #
###################

# For now, only tested on Linux
OS=$(uname -s)
EXEEXT= # executable extension
case $OS in
    Linux) OS=linux;;
    Darwin) OS=darwin;;
    CYGWIN*|*_NT-*) OS=windows;
        if [ "$OSTYPE" = cygwgin ]; then
            OS=cygwin
        fi
        EXEEXT=.exe
        ;;
esac

BUILD_ARCH=$(uname -m)
case $BUILD_ARCH in
    i?86) BUILD_ARCH=x86;;
    amd64) BUILD_ARCH=x86_64;;
esac

if [ "$OS" != "linux" ]; then
    panic "Error: This script only works on Linux."
fi

SYSTEMS=$(commas_to_spaces $SYSTEMS)

#####################
# Darwin SDK checks #
#####################

if [ ! -z "$DARWINSDK" ] ; then
  if [ "$(bh_list_contains "darwin-x86"    $SYSTEMS)" = "no" -a \
       "$(bh_list_contains "darwin-x86_64" $SYSTEMS)" = "no" ] ; then
     log "You specified a --darwinsdk so"
     log " adding darwin-x86 to the SYSTEMS list"
     SYSTEMS="$SYSTEMS "darwin-x86
  fi
else
  if [ ! "$(bh_list_contains "darwin-x86"    $SYSTEMS)" = "no" -a \
     ! ! "$(bh_list_contains "darwin-x86_64" $SYSTEMS)" = "no" ] ; then
     log "You included darwin in the --systems list,"
     log " but didn't provide a --darwinsdk. Assuming:"
     log "  $HOST_TOOLS/darwin/MacOSX10.7.sdk"
     DARWINSDK=$HOST_TOOLS/darwin/MacOSX10.7.sdk
  fi
fi

if [ ! -z "$DARWINSDK" -a ! -d "$DARWINSDK" ] ; then
  log "darwinsdk folder $DARWINSDK doesn't exist,"
  log " It should be e.g. MacOSX10.7.sdk"
  panic " Speak to a friendly Mac owner?"
fi

if [ "$HELP" ] ; then
    echo "Usage: $PROGNAME [options]"
    echo ""
    echo "This program is used to rebuild a mingw64 cross-toolchain from scratch."
    echo ""
    echo "Valid options:"
    echo "  -h|-?|--help                 Print this message."
    echo "  --verbose                    Increase verbosity."
    echo "  --quiet                      Decrease verbosity."
    echo "  --systems=<num>              Comma separated list of host systems [$SYSTEMS]."
    echo "  --jobs=<num>                 Run <num> build tasks in parallel [$JOBS]."
    echo "  -j<num>                      Same as --jobs=<num>."
    echo "  --binprefix=<prefix>         Specify bin prefix for host toolchain."
    echo "  --disable-32bit              Disable 32bit host tools build."
    echo "  --enable-64bit               Enable 64bit host tools build."
    echo "  --target-arch=<arch>         Select default target architecture [$TARGET_ARCH]."
    echo "  --force-all                  Redo everything from scratch."
    echo "  --force-build                Force a rebuild (keep sources)."
    echo "  --cleanup                    Remove all temp files after build."
    echo "  --work-dir=<path>            Specify work/build directory [$TEMP_DIR]."
    echo "  --package-dir=<path>         Package toolchain to directory."
    echo ""
    exit 0
fi

###########################################
# Clone the android-qt-ndk git repository #
###########################################

NDK_TOP="$BUILD_DIR"/android-qt-ndk
mkdir -p "$NDK_TOP"
NDK=$NDK_TOP/ndk
mkdir -p $(dirname "$NDK")
NDK_PLATFORM=$BUILD_DIR/ndk_meta
if [ ! -d $NDK ] ; then
  git clone http://anongit.kde.org/android-qt-ndk.git $NDK
  fail_panic "Couldn't clone android-qt-ndk"
fi

if [ ! -d $NDK_TOP/development ] ; then
    git clone http://android.googlesource.com/platform/development.git $NDK_TOP/development
fi

########################################################
# Get (or build) the required per-host cross compilers #
########################################################

# We don't need Google's special glibc2.7 linux GCCs if we're in BogDan's
# Debian env.
# Otherwise, we use it, assuming that Linux is the only OS worth doing
# this kind of cross compilation task on (IMHO, it is).
DEBIAN_VERSION=
if [ -f /etc/debian_version ] ; then
  DEBIAN_VERSION=$(head -n 1 /etc/debian_version)
fi

# BINPREFIX is needed for building highly compatiable mingw-w64 toolchains.
BINPREFIX=
if [ ! "$DEBIAN_VERSION" = "6.0.5" ] ; then
  (mkdir -p $HOST_TOOLS/linux; cd /tmp; \
   download http://mingw-and-ndk.googlecode.com/files/i686-w64-mingw32-linux-i686-glibc2.7.tar.bz2; z
   tar -xjf i686-w64-mingw32-linux-i686-glibc2.7.tar.bz2 -C $HOST_TOOLS/linux/)
  export PATH=$HOST_TOOLS/linux/i686-linux-glibc2.7-4.4.3/bin:$PATH
  BINPREFIX=--binprefix=i686-linux
fi

# Check MinGW (and possibly build the cross compiler)
if [ ! "$(bh_list_contains "windows-x86"    $SYSTEMS)" = "no" -o \
     ! "$(bh_list_contains "windows-x86_64" $SYSTEMS)" = "no" ] ; then
  if [ ! -d "$HOST_TOOLS/mingw" ] ; then
    $NDK/build/tools/build-mingw64-toolchain.sh --target-arch=i686 --package-dir=i686-w64-mingw32-toolchain $BINPREFIX
    fail_panic "Couldn't build mingw-w64 toolchain"
    mkdir -p $HOST_TOOLS/mingw
    tar -xjf i686-w64-mingw32-toolchain/*.tar.bz2 -C $HOST_TOOLS/mingw
  fi
  export PATH=$HOST_TOOLS/mingw/i686-w64-mingw32/bin:$PATH
fi

# By this point, having anything is DARWINSDK can be taken to mean that
# darwin build(s) are required.
if [ ! -z "$DARWINSDK" ] ; then
  if [ ! -d "$HOST_TOOLS/darwin/apple-osx" ] ; then
    mkdir -p $HOST_TOOLS/darwin
    download http://mingw-and-ndk.googlecode.com/files/multiarch-darwin11-cctools127.2-gcc42-5666.3-llvmgcc42-2336.1-Linux-120531.tar.xz
    tar -xJf multiarch-darwin11-cctools127.2-gcc42-5666.3-llvmgcc42-2336.1-Linux-120531.tar.xz -C $HOST_TOOLS/darwin
  fi
  export PATH=$HOST_TOOLS/darwin/apple-osx/bin:$PATH
  export DARWIN_TOOLCHAIN="i686-apple-darwin11"
  export DARWIN_SYSROOT="$DARWINSDK"
fi

if [ -z "$TC_SRC_DIR" ] ; then
  TC_SRC_DIR=$NDK_TOP/toolchain-source
fi

if [ ! -d "$TC_SRC_DIR" ] ; then
  mkdir -p $TC_SRC_DIR
  # Later, we may want to specify --no-patches here, then download other bits that
  #  we need, and then finally patch by hand (well, via patch-sources.sh).
  # We'll need to do this if we need patches for the other bits we download.
  $NDK/build/tools/download-toolchain-sources.sh $TC_SRC_DIR
  if [ $? != 0 ]; then
    rm -rf $TC_SRC_DIR
    panic "download-toolchain-sources.sh failed?"
  fi

  # Other bits we need - only gmp-5.0.5 at present.
  download http://ftp.gnu.org/gnu/gmp/gmp-5.0.5.tar.bz2
  tar -xjf gmp-5.0.5.tar.bz2 -C $TC_SRC_DIR/gmp/

  # Linaro?
  if [ ! -z "$LINARO" ] ; then
    download http://launchpad.net/gcc-linaro/${GCC_VER_LINARO_MAJOR}/${GCC_VER_LINARO}/+download/gcc-linaro-${GCC_VER_LINARO}.tar.bz2
    tar xjf gcc-linaro-${GCC_VER_LINARO}.tar.bz2 -C $TC_SRC_DIR/gcc/
    # This is so that Necessitas doesn't have to deal with 'weird' gcc-linaro-${GCC_VER_LINARO} version numbers.
    mv $TC_SRC_DIR/gcc/gcc-linaro-${GCC_VER_LINARO} $TC_SRC_DIR/gcc/gcc-${GCC_VER_LINARO_LOCAL}
    echo ${GCC_VER_LINARO_LOCAL} > $TC_SRC_DIR/gcc/gcc-${GCC_VER_LINARO_LOCAL}/gcc/BASE-VER
  fi
fi

if [ ! -f $NDK/platforms/android-9/arch-arm/usr/lib/libdl.so ]; then
  $NDK/build/tools/build-platforms.sh
  # Get the released NDKs and mix the missing bits (libdl.so etc) into our clone of Google's NDK.
  [ ! -f android-ndk-$NDK_VER-linux-x86.tar.bz2 ] && \
    download http://dl.google.com/android/ndk/android-ndk-$NDK_VER-linux-x86.tar.bz2
  [ ! -d android-ndk-$NDK_VER ]  &&        tar -xjf android-ndk-$NDK_VER-linux-x86.tar.bz2
  mkdir -p $NDK/platforms
  cp -rf android-ndk-$NDK_VER/platforms/* $NDK/platforms
  # Check that (one of) the missing bits is now present (libdl.so is needed for building libstdc++)
  if [ ! -f $NDK/platforms/android-9/arch-arm/usr/lib/libdl.so ] ; then
    echo "Failed to find $NDK/platforms/android-9/arch-arm/usr/lib/libdl.so, bailing out"
    exit 1
  fi
fi

# build folder name refers to the folder (and tarball) names
# created by build_host_gcc.
system_name_to_build_folder_name ()
{
    case $1 in
        arm)
            echo "arm-linux-androideabi"
        ;;
        x86)
            echo "x86"
        ;;
        mips)
            echo "mips"
        ;;
    esac
}

# final folder name refers to the folder name in the NDKs released
# by Google, and also the names passed to build-host-gcc.sh
system_name_to_final_folder_name ()
{
    case $1 in
        arm)
            echo "arm-linux-androideabi"
        ;;
        x86)
            echo "x86"
        ;;
        mips)
            echo "mipsel-linux-android"
        ;;
    esac
}

GCC_4_6_VER=4.6
if [ ! -z "$LINARO" ] ; then
  GCC_4_6_VER=4.6.3
fi

GCC_VERSIONS="4.4.3 $GCC_4_6_VER"
for TARCH in $ARCHES ; do
  for GCC_VERSION in $GCC_VERSIONS ; do
    ARCHES_BY_VERSIONS="$ARCHES_BY_VERSIONS "$(system_name_to_final_folder_name $TARCH)-$GCC_VERSION
  done
done

# Building these in separate folders gives better build.log files as they're
#  overwritten otherwise.
GCC_BUILD_DIR=$BUILD_DIR_TMP/buildgcc
PYTHON_BUILD_DIR=$BUILD_DIR_TMP/buildpython
GDB_BUILD_DIR=$BUILD_DIR_TMP/buildgdb

#  --build-dir=$GCC_BUILD_DIR \
$NDK/build/tools/build-host-gcc.sh --toolchain-src-dir=$TC_SRC_DIR \
  --gmp-version=5.0.5 \
  --force-gold-build \
  --default-ld=gold \
  --systems="$SYSTEMS" \
  --package-dir=$PWD/release-$DATESUFFIX \
    $ARCHES_BY_VERSIONS \
   -j$JOBS

if [ "$(bh_list_contains "linux-$BUILD_ARCH" $SYSTEMS)" = "no" ] ; then
  SYSTEMSPY=$SYSTEMS",linux-x86_64"
fi

$NDK/build/tools/build-host-python.sh \
  --systems="$SYSTEMSPY" \
  --build-dir=$PYTHON_BUILD_DIR \
  --package-dir=$PWD/release-$DATESUFFIX \
  --python-version=2.7.3 \
   -j$JOBS

$NDK/build/tools/build-host-gdb.sh --toolchain-src-dir=$TC_SRC_DIR \
  --systems="$SYSTEMS" \
  --build-dir=$GDB_BUILD_DIR \
  --package-dir=$PWD/release-$DATESUFFIX \
  --gdb-version=7.3.x \
  --build-dir=$GDB_BUILD_DIR \
  --arch="arm mips x86" \
  --python-build-dir=$PYTHON_BUILD_DIR \
  --python-version=2.7.3 \
   -j$JOBS

rm -rf /tmp/ndk-$USER/build/gdbserver*
$NDK/build/tools/build-target-prebuilts.sh \
  --ndk-dir=$NDK \
  --arch="arm mips x86" \
  --package-dir=$PWD/release-$DATESUFFIX \
    $TC_SRC_DIR \
  -j$JOBS
