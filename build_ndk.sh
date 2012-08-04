#!/bin/bash

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
BUILD_DIR=$HOME/necessitas-tmp
BUILD_DIR_TMP=$BUILD_DIR/ndk-tmp
HOST_TOOLS=$BUILD_DIR/host_compiler_tools
GCC_VER_LINARO=4.6-2012.07
GCC_VER_LINARO_MAJOR=4.6
GCC_VER_LINARO_LOCAL=4.6.3
ARCHES="arm,mips,x86"
#ARCHES="arm"
OSTYPE_MAJOR=${OSTYPE//[0-9.]/}

# We need a newer MSYS expr.exe and we need it early in this process.
# I made one from coreutils-8.17.
# If you used BootstrapMinGW64.vbs to create your mingw-w64
#  environment then that will have copied this expr into the bin folder
#  already, but in-case you didn't...
if [ "$OSTYPE" = "msys" ] ; then
  echo "Testing expr.exe"
  EXPR_RESULT=`expr -- "--test=<value>" : '--[^=]*=\(<.*>\)' 2>&1 > /dev/null`
  if [ ! "$EXPR_RESULT" = "<value>" ] ; then
    echo "Downloading more modern MSYS expr"
    if [ ! -f $PWD/expr.exe ] ; then
      curl -S -L -O http://mingw-and-ndk.googlecode.com/files/expr.exe
    fi
    export PATH=$PWD:$PATH
  fi
fi

case $OSTYPE_MAJOR in
    linux*)
        SYSTEMS=linux-x86,windows-x86,darwin-x86
        NUM_CORES=$(grep -c -e '^processor' /proc/cpuinfo)
        BUILD_OS="linux"
        ;;
    darwin|freebsd)
#       SYSTEMS=darwin-x86,windows-x86
        SYSTEMS=darwin-x86
        NUM_CORES=`sysctl -n hw.ncpu`
        BUILD_OS="darwin"
        ;;
    windows|msys|cygwin)
        export PATH=$BUILD_DIR/bin:$PATH
        SYSTEMS=darwin-x86,windows-x86
        NUM_CORES=$NUMBER_OF_PROCESSORS
        BUILD_OS="windows"
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

# $1 is the string to remove (all instances of)
# $2... is the list to search in
# Prints new list
bh_list_remove ()
{
  local SEARCH="$1"
  shift
  # For dash, this has to be split over 2 lines.
  # Seems to be a bug with dash itself:
  # https://bugs.launchpad.net/ubuntu/+source/dash/+bug/141481
  local LIST
  LIST=$@
  local RESULT
  # Pull out the host if there
  RETCODE=1
  for ELEMENT in $LIST; do
    if [ ! "$ELEMENT" = "$SEARCH" ]; then
      RESULT=$RESULT" $ELEMENT"
    else
      RETCODE=0
    fi
  done
  echo $RESULT
  return $RETCODE
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
        if [ "$OSTYPE" = cygwin ]; then
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

LIST_SYSTEMS=$(commas_to_spaces $SYSTEMS)
LIST_ARCHES=$(commas_to_spaces $ARCHES)

#####################
# Darwin SDK checks #
#####################

if [ ! -z "$DARWINSDK" ] ; then
  if [ "$(bh_list_contains "darwin-x86"    $LIST_SYSTEMS)" = "no" -a \
       "$(bh_list_contains "darwin-x86_64" $LIST_SYSTEMS)" = "no" ] ; then
     log "You specified a --darwinsdk so"
     log " adding darwin-x86 to the --systems list"
     SYSTEMS="$SYSTEMS "darwin-x86
  fi
else
  if [ ! "$(bh_list_contains "darwin-x86"    $LIST_SYSTEMS)" = "no" -a \
     ! ! "$(bh_list_contains "darwin-x86_64" $LIST_SYSTEMS)" = "no" ] ; then
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

###########################
# Make some Windows tools #
###########################

build_windows_programs ()
{
  local BUILDDIR=$1
  local PREFIX=$2
  local PATCHES=$3

  if [ "$OSTYPE" = "msys" ] ; then
    if [ -z $(which file) ] ; then
    (cd $BUILDDIR;
      if ! $(curl -S -L -O http://kent.dl.sourceforge.net/project/mingw/Other/UserContributed/regex/mingw-regex-2.5.1/mingw-libgnurx-2.5.1-src.tar.gz); then
        error "Failed to get and extract mingw-regex-2.5.1 Check errors."
      fi
      tar -xf mingw-libgnurx-2.5.1-src.tar.gz
      pushd mingw-libgnurx-2.5.1
      patch --backup -p0 < ${PATCHES}/mingw-libgnurx-2.5.1-static.patch
      ./configure --prefix=$PREFIX --enable-static --disable-shared
      if ! make  -j$JOBS; then
        error "Failed to make mingw-libgnurx-2.5.1"
        popd
        exit 1
      fi
      make -j$JOBS install
      popd

      curl -S -L -O ftp://ftp.astron.com/pub/file/file-5.11.tar.gz
      tar -xvf file-5.11.tar.gz
      (cd file-5.11
       CFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib" ./configure --prefix=$PREFIX
       make -j$JOBS
       make install
      )
      if [ ! $? = 0 ]; then
        echo "Failed to build file"
        exit 1
      fi
     )
    fi
  fi
}

export PATH=$BUILD_DIR/bin:$PATH
build_windows_programs "$BUILD_DIR_TMP" "$BUILD_DIR" "$PWD/misc-patches"

###########################################
# Clone the android-qt-ndk git repository #
###########################################

NDK_TOP="$BUILD_DIR"/android-qt-ndk
NDK=$NDK_TOP/ndk
if [ ! -d $NDK ] ; then
#  git clone http://anongit.kde.org/android-qt-ndk.git $NDK
#  (cd $NDK; git checkout -b ndk-r8b-fixes -t origin/ndk-r8b-fixes)
  git clone https://android.googlesource.com/platform/ndk.git $NDK
  (cd $NDK; git checkout -b ndk-r8b-fixes)
  fail_panic "Couldn't clone ndk"
fi
if [ ! -d $NDK_TOP/development ] ; then
    git clone http://android.googlesource.com/platform/development.git $NDK_TOP/development
    PLATFORMS_SRC=$NDK_TOP/development
fi

########################################################
# Get (or build) the required per-host cross compilers #
########################################################

# We don't need Google's special glibc2.7 linux GCCs if we're in BogDan's
# Debian env.
# Otherwise, we use it, assuming that Linux is the only OS worth doing
# this kind of cross compilation task on (IMHO, it is).
if [ "$OSTYPE" = "linux-gnu" ] ; then
  DEBIAN_VERSION=
  if [ -f /etc/debian_version ] ; then
    DEBIAN_VERSION=$(head -n 1 /etc/debian_version)
  fi

  # BINPREFIX is needed for building highly compatiable mingw-w64 toolchains.
  BINPREFIX=
  if [ ! "$DEBIAN_VERSION" = "6.0.5" -a ] ; then
    if [ ! -d $HOST_TOOLS/linux ] ; then
      (mkdir -p $HOST_TOOLS/linux; cd /tmp; \
       download http://mingw-and-ndk.googlecode.com/files/i686-linux-glibc2.7-4.4.3.tar.bz2; \
       tar -xjf i686-linux-glibc2.7-4.4.3.tar.bz2 -C $HOST_TOOLS/linux/)
    fi
    export PATH=$HOST_TOOLS/linux/i686-linux-glibc2.7-4.4.3/bin:$PATH
    BINPREFIX=--binprefix=i686-linux
  fi
fi

# Check MinGW (and possibly build the cross compiler)
if [ ! "$(bh_list_contains "windows-x86"    $LIST_SYSTEMS)" = "no" -o \
     ! "$(bh_list_contains "windows-x86_64" $LIST_SYSTEMS)" = "no" ] ; then
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
    if [ $OSTYPE_MAJOR = "linux-gnu" ] ; then
        download http://mingw-and-ndk.googlecode.com/files/multiarch-darwin11-cctools127.2-gcc42-5666.3-llvmgcc42-2336.1-Linux-120724.tar.xz
        tar -xJf multiarch-darwin11-cctools127.2-gcc42-5666.3-llvmgcc42-2336.1-Linux-120724.tar.xz -C $HOST_TOOLS/darwin
    elif [ $OSTYPE_MAJOR = "windows" ] ; then
        download http://mingw-and-ndk.googlecode.com/files/multiarch-darwin11-cctools127.2-gcc42-5666.3-llvmgcc42-2336.1-Windows-120614.7z
        7za x multiarch-darwin11-cctools127.2-gcc42-5666.3-llvmgcc42-2336.1-Windows-120614.7z -o$HOST_TOOLS/darwin
    else
        download http://mingw-and-ndk.googlecode.com/files/multiarch-darwin11-cctools127.2-gcc42-5666.3-llvmgcc42-2336.1-Darwin-120615.7z
        7za x multiarch-darwin11-cctools127.2-gcc42-5666.3-llvmgcc42-2336.1-Darwin-120615.7z -o$HOST_TOOLS/darwin
    fi
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
for TARCH in $LIST_ARCHES ; do
  for GCC_VERSION in $GCC_VERSIONS ; do
    ARCHES_BY_VERSIONS="$ARCHES_BY_VERSIONS "$(system_name_to_final_folder_name $TARCH)-$GCC_VERSION
  done
done

# Building these in separate folders gives better build.log files as they're
#  overwritten otherwise.
GCC_BUILD_DIR=$BUILD_DIR_TMP/build/host-gcc
PYTHON_BUILD_DIR=$BUILD_DIR_TMP/build/host-python
GDB_BUILD_DIR=$BUILD_DIR_TMP/build/host-gdb
TARGET_BUILD_DIR=$BUILD_DIR_TMP/build/target
PACKAGE_DIR=$PWD/release-$DATESUFFIX

mkdir -p $PACKAGE_DIR

if [ "0" = "1" ] ; then
$NDK/build/tools/build-host-gcc.sh --toolchain-src-dir=$TC_SRC_DIR \
  --gmp-version=5.0.5 \
  --force-gold-build \
  --default-ld=gold \
  --systems="$SYSTEMS" \
  --build-dir=$GCC_BUILD_DIR \
  --package-dir=$PACKAGE_DIR \
    $ARCHES_BY_VERSIONS \
   -j$JOBS

SYSTEMSLIST=$(commas_to_spaces $SYSTEMS)
if [ "$(bh_list_contains $BUILD_OS-$BUILD_ARCH $SYSTEMSLIST)" = "no" ] ; then
  log "Adding $BUILD_OS-$BUILD_ARCH for Python build"
  SYSTEMSPY=$SYSTEMS",$BUILD_OS-$BUILD_ARCH"
else
  SYSTEMSPY=$SYSTEMS
fi

$NDK/build/tools/build-host-python.sh --toolchain-src-dir=$TC_SRC_DIR \
  --systems="$SYSTEMSPY" \
  --build-dir=$PYTHON_BUILD_DIR \
  --package-dir=$PACKAGE_DIR \
  --python-version=2.7.3 \
   -j$JOBS

fail_panic "build-host-python.sh failed"
fi

$NDK/build/tools/build-host-gdb.sh --toolchain-src-dir=$TC_SRC_DIR \
  --systems="$SYSTEMS" \
  --build-dir=$GDB_BUILD_DIR \
  --package-dir=$PACKAGE_DIR \
  --gdb-version=7.3.x \
  --build-dir=$GDB_BUILD_DIR \
  --arch=$ARCHES \
  --python-build-dir=$PYTHON_BUILD_DIR \
  --python-version=2.7.3 \
   -j$JOBS

rm -rf /tmp/ndk-$USER/build/gdbserver*

# CAN'T CURRENTLY BUILD MIPS LIBS OR GDBSERVER!
#ARCHES_WITHOUT_MIPS=$(bh_list_remove mips $LIST_ARCHES)
#if [ "$LIST_ARCHES" != "$ARCHES_WITHOUT_MIPS" ]; then
#    echo "WARNING :: Removed mips from build-target-prebuilts.sh"
#    echo "        :: to avoid error:"
#    echo "        ::  collect2: cannot find 'ld'"
#fi
#ARCHES_WITHOUT_MIPS=$(spaces_to_commas $ARCHES_WITHOUT_MIPS)
ARCHES_WITHOUT_MIPS=$ARCHES

$NDK/build/tools/build-target-prebuilts.sh \
  --ndk-dir=$NDK \
  --arch="$ARCHES_WITHOUT_MIPS" \
  --build-dir=$TARGET_BUILD_DIR \
  --package-dir=$PWD/release-$DATESUFFIX \
    $TC_SRC_DIR \
  -j$JOBS
