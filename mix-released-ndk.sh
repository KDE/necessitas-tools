#!/bin/bash

HELP=
VERBOSE=1

set -e

longest_common_prefix () {
  local prefix= n
  ## Truncate the two strings to the minimum of their lengths
  if [[ ${#1} -gt ${#2} ]]; then
    set -- "${1:0:${#2}}" "$2"
  else
    set -- "$1" "${2:0:${#1}}"
  fi
  ## Binary search for the first differing character, accumulating the common prefix
  while [[ ${#1} -gt 1 ]]; do
    n=$(((${#1}+1)/2))
    if [[ ${1:0:$n} == ${2:0:$n} ]]; then
      prefix=$prefix${1:0:$n}
      set -- "${1:$n}" "${2:$n}"
    else
      set -- "${1:0:$n}" "${2:0:$n}"
    fi
  done
  ## Add the one remaining character, if common
  if [[ $1 = $2 ]]; then prefix=$prefix$1; fi
  printf %s "$prefix"
}

longest_common_prefix_n () {
    local _ACCUM=""
    local _PREFIXES="$1"
    for PREFIX in $_PREFIXES
    do
        if [[ -z $_ACCUM ]] ; then
            _ACCUM=$PREFIX
        else
            _ACCUM=$(longest_common_prefix $_ACCUM $PREFIX)
        fi
    done
    printf %s "$_ACCUM"
}

archive_type_for_host() {
    local _HOST=$1
    if [[ -z $_HOST ]] ; then
        HOST=$(uname_bt)
    fi

    if [[ "$HOST" = "Linux" ]] ; then
	echo tar.xz
	return 0
    elif [[ "$HOST" = "Windows" ]] ; then
	echo 7z
	return 0
    else
	echo 7z
	return 0
    fi
}

# $1 == folder(s) to compress (quoted, must all be relative to the working directory)
# $2 == dirname with prefix for filename of output (i.e. without extensions)
# $3 == Either xz, bz2, 7z, Windows, Linux, Darwin or nothing
# Returns the name of the compressed file.
compress_folders() {

    local _FOLDERS="$1"
    local _COMMONPREFIX=""
    local _FOLDERSABS

    set -x
    echo called compress_folders $1 $2 $3

    # Special case: if a single folder is passed in and it ends with a ., then
    # we don't want the actual folder itself to appear in the archive.
    if [[ ${#_FOLDERS[@]} = 1 ]] && [[ $(basename "$1") = . ]] ; then
        pushd $1 > /dev/null
        _COMMONPREFIX=$PWD
        popd > /dev/null
	_RELFOLDERS=$(basename "$_FOLDERSABS")
    else
        for FOLDER in $_FOLDERS
        do
            if [[ ! -d $FOLDER ]] ; then
                echo "Folder $FOLDER doesn't exist"
                return 1
            fi
            pushd $FOLDER > /dev/null
            _FOLDERSABS="$_FOLDERSABS "$PWD
            popd > /dev/null
        done

        local _COMMONPREFIX=$(longest_common_prefix_n "$_FOLDERSABS")
        echo _COMMONPREFIX is $_COMMONPREFIX

        if [[ ${#_FOLDERSABS[@]} = 1 ]] ; then
            _COMMONPREFIX=$(dirname "$_FOLDERSABS")
            _RELFOLDERS=$(basename "$_FOLDERSABS")
        else
            local _RELFOLDERS=
            for FOLDER in $_FOLDERSABS
            do
                _RELFOLDERS="$_RELFOLDERS "${FOLDER#$_COMMONPREFIX}
            done
        fi
    fi

    local _OUTFILE=$2
    if [[ "$(basename $_OUTFILE)" = "$_OUTFILE" ]] ; then
	_OUTFILE=$PWD/$_OUTFILE
    fi

    local _ARCFMT=$3

    if [[ -z "$_ARCFMT" ]] ; then
	_ARCFMT=$(uname_bt)
    fi

    if [[ "$_ARCFMT" = "Windows" ]] ; then
	_ARCFMT="7z"
    elif [[ "$_ARCFMT" = "Darwin" ]] ; then
	# I'd prefer to use xar (but see below) or tar.xz, but can't, because:
	# 1. Neither lzma nor xz are compiled into the Darwin version.
	# 2. It compresses each file individually.
	# 3. xz doesn't exist by default on Darwin - neither does 7z, but I've
	#    put a binary up on http://code.google.com/p/mingw-and-ndk/
	# ..meaning with xar --compression-args=9 -cjf, my Darwin cross
	#   compilers end up being ~71MB compared to ~19MB as a 7z
	#   which is too vast a difference for me to ignore.
	_ARCFMT="7z"
    elif [[ "$_ARCFMT" = "Linux" ]] ; then
	_ARCFMT="xz"
    fi

    pushd $_COMMONPREFIX > /dev/null
#    pushd $1 > /dev/null
    if [[ "$_ARCFMT" == "7z" ]] ; then
        find $_RELFOLDERS -maxdepth 1 -mindepth 0 \( ! -path "*.git*" \) -exec sh -c "exec echo {} " \; > /tmp/$$.txt
    else
        # Usually, sorting by the filename part of the full path yields better compression.
        find $_RELFOLDERS -type f \( ! -path "*.git*" \) -exec sh -c "echo \$(basename {}; echo {} ) " \; | sort | awk '{print $2;}' > /tmp/$$.txt
        tar -c --files-from=/tmp/$$.txt -f /tmp/$(basename $2).tar
    fi

    if [[ "$_ARCFMT" == "xz" ]] ; then
        _ARCEXT=".tar.xz"
    elif [[ "$_ARCFMT" == "bz2" ]] ; then
        _ARCEXT=".tar.bz2"
    else
        _ARCEXT="."$_ARCFMT
    fi

    if [[ -f $_OUTFILE$_ARCEXT ]] ; then
        rm -rf $_OUTFILE$_ARCEXT > /dev/null
    fi

    if [[ "$_ARCFMT" == "xz" ]] ; then
        _ARCEXT=".tar.xz"
        echo $PWD
        echo xz -z -9 -e -c -q /tmp/$(basename $2).tar > $_OUTFILE$_ARCEXT
	xz -z -9 -e -c -q /tmp/$(basename $2).tar > $_OUTFILE$_ARCEXT
    elif [[ "$_ARCFMT" == "bz2" ]] ; then
        _ARCEXT=".tar.bz2"
	bzip2 -z -9 -c -q /tmp/$(basename $2).tar > $_OUTFILE$_ARCEXT
    elif [[ "$_ARCFMT" == "xar" ]] ; then
	# I'd like to use xz or lzma, but xar -caf results in "lzma support not compiled in."
	xar --compression-args=9 -cjf $_OUTFILE$_ARCEXT $(cat /tmp/$$.txt)
    else
	7za a -mx=9 $_OUTFILE$_ARCEXT $(cat /tmp/$$.txt) > /dev/null
    fi
    echo $_OUTFILE$_ARCEXT
    popd > /dev/null
    return 0
}

# This will be reset later.
LOG_FILE=/dev/null

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

run ()
{
    if [ "$VERBOSE" -gt 0 ]; then
        echo "COMMAND: >>>> $@" >> $LOG_FILE
    fi
    if [ "$VERBOSE" -gt 1 ]; then
        echo "COMMAND: >>>> $@"
    fi
    if [ "$VERBOSE" -gt 1 ]; then
        "$@"
    else
        &>>$LOG_FILE "$@"
    fi
}

log ()
{
    if [ "$LOG_FILE" ]; then
        echo "$@" >> $LOG_FILE
    fi
    if [ "$VERBOSE" -gt 0 ]; then
        echo "$@"
    fi
}

download_package ()
{
    # Assume the packages are already downloaded under $ARCHIVE_DIR
    local PKG_URL=$1
    local PKG_NAME=$(basename $PKG_URL)

    case $PKG_NAME in
        *.tar.bz2)
            PKG_BASENAME=${PKG_NAME%%.tar.bz2}
            ;;
        *.tar.gz)
            PKG_BASENAME=${PKG_NAME%%.tar.gz}
            ;;
        *.zip)
            PKG_BASENAME=${PKG_NAME%%.zip}
            ;;
        *)
            panic "Unknown archive type: $PKG_NAME"
    esac

    if [ ! -f "$ARCHIVE_DIR/$PKG_NAME" ]; then
        log "Downloading $PKG_URL..."
        (cd $ARCHIVE_DIR && run curl -L -o "$PKG_NAME" "$PKG_URL")
#        fail_panic "Can't download '$PKG_URL'"
    fi

    if [ ! -d "$SRC_DIR/$PKG_BASENAME" ]; then
        mkdir -p "$SRC_DIR/$PKG_BASENAME"
        log "Uncompressing $PKG_URL into $SRC_DIR"
        case $PKG_NAME in
            *.tar.bz2)
                run tar xjf $ARCHIVE_DIR/$PKG_NAME -C $SRC_DIR/$PKG_BASENAME
                ;;
            *.tar.gz)
                run tar xzf $ARCHIVE_DIR/$PKG_NAME -C $SRC_DIR/$PKG_BASENAME
                ;;
            *.zip)
                run unzip $ARCHIVE_DIR/$PKG_NAME -d $SRC_DIR/$PKG_BASENAME
                ;;
            *)
                panic "Unknown archive type: $PKG_NAME"
                ;;
        esac
        fail_panic "Can't uncompress $ARCHIVE_DIR/$PKG_NAME"
    fi
    eval $2=\"$SRC_DIR/$PKG_BASENAME\"
}

# Returns the name of the NDK archive.
# $1 is system
# $2 is arch (or nothing)
system_name_to_ndk_release_name ()
{
    local _ARCH
    if [ -z "$2"  ] ; then
        _ARCH=
    else
        _ARCH=-$2
    fi
    case $1 in
        linux)
            echo "linux$_ARCH"
        ;;
        darwin)
            echo "darwin$_ARCH"
        ;;
        windows)
            echo "windows$_ARCH"
        ;;
    esac
}

system_name_to_ma_ndk_release_extension ()
{
    case $1 in
        linux)
            echo "tar.xz"
            return
        ;;
        darwin)
            echo "7z"
            return
        ;;
        windows)
            echo "7z"
            return
        ;;
    esac
}

system_name_to_archive_extension ()
{
    case $1 in
        linux)
            echo "tar.bz2"
        ;;
        darwin)
            echo "tar.bz2"
        ;;
        windows)
            echo "zip"
        ;;
    esac
}

# final folder name refers to the folder name in the NDKs released
# by Google.
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

# Generally nothing, but for gdb it's "toolchains/"
package_name_to_final_folder_suffix_name ()
{
    case $(basename "$1") in
        python*)
            echo ""
            ;;

        gdb*)
            echo "toolchains/"
            ;;
        *)
        ;;
    esac
}

TEMP_DIR=/tmp/mix-ndk-$USER
ARCHIVE_DIR=$TEMP_DIR/archive
SRC_DIR=$TEMP_DIR/src

mkdir -p $ARCHIVE_DIR
rm -rf $SRC_DIR
mkdir -p $SRC_DIR

BUILD_DIR=/tmp/necessitas
NDK="$BUILD_DIR"/android-qt-ndk/ndk

SYSTEMS="linux windows darwin"

# Must be some of "default", "x86", "x86_64" or "both"
#HOST_ARCHES="default"
HOST_ARCHES="both"
# x86 is currently broken (prefix is i686-linux-android instead of i686-android-linux)
TARG_ARCHES="x86 mips arm"
# TARG_ARCHES="arm mips"
# TARG_ARCHES="arm"
SRC_REVISION="r8e"
DATESUFFIX=$(date +%y%m%d)
RELEASE_FOLDER=release-$DATESUFFIX
# Otherwise it mixes them together.
AN_NDK_PER_HOST_ARCH=1
# Form some comma separated lists.
# ARCHIVE_NAME,
#for SYSTEM in $SYSTEMS; do

for SYSTEM in $SYSTEMS; do
    if [ "$HOST_ARCHES" = "default" ] ; then
        HOST_ARCHES="x86"
    elif [ "$HOST_ARCHES" = "both" ] ; then
        HOST_ARCHES="x86 x86_64"
    fi

    for HOST_ARCH in $HOST_ARCHES; do
        NEW_ARCHIVE=android-ndk-${SRC_REVISION}-ma-$(system_name_to_ndk_release_name $SYSTEM $HOST_ARCH).$(system_name_to_ma_ndk_release_extension $SYSTEM)
        if [ ! -f ${RELEASE_FOLDER}/${NEW_ARCHIVE} ]; then
            GOOGLES_ARCHIVE="http://dl.google.com/android/ndk/android-ndk-${SRC_REVISION}-$(system_name_to_ndk_release_name $SYSTEM $HOST_ARCH).$(system_name_to_archive_extension $SYSTEM)"
            download_package $GOOGLES_ARCHIVE DST_FOLDER
            DST_FOLDER=${DST_FOLDER}/android-ndk-${SRC_REVISION}
            cp -rvf $NDK/build/* $DST_FOLDER/build/
            cp -rvf $NDK/*py* $DST_FOLDER/
            if [ "$SYSTEM" = "windows" ] ; then
              WINDOWS_FOLDERS=$(find $DST_FOLDER -name "windows")
              for WINDOWS_FOLDER in $WINDOWS_FOLDERS; do
                mv $WINDOWS_FOLDER $(dirname $WINDOWS_FOLDER)/windows-x86
              done
            fi

            # For comparison.
            # cp -rf $DST_FOLDER/toolchains $DST_FOLDER/toolchains-google
            SYSTEM_FOLDER=${SYSTEM}-${HOST_ARCH}
            # Target arch independent.
            PYTHON_DLLS=
            TAR_BZ2S="          "$(find $PWD/$RELEASE_FOLDER -path "*/python-*-${SYSTEM}-${HOST_ARCH}.tar.bz2")
            TAR_BZ2S="$TAR_BZ2S "$(find $PWD/$RELEASE_FOLDER -path "*/*lib*.tar.bz2")
            for TAR_BZ2 in $TAR_BZ2S; do
                THIS_DST_FOLDER=$DST_FOLDER/$(package_name_to_final_folder_suffix_name $TAR_BZ2)
                mkdir -p $THIS_DST_FOLDER
                tar -xjf "$TAR_BZ2" -C "$THIS_DST_FOLDER"
                PYTHON_DLLS=$(find $THIS_DST_FOLDER -path "$DST_FOLDER/prebuilt/${SYSTEM_FOLDER}/*python*.dll")
                echo PYTHON_DLLS is $PYTHON_DLLS
            done
            # Target arch dependent.
            for TARG_ARCH in $TARG_ARCHES; do
                GDBSERVER_BZ2=$(find $PWD/$RELEASE_FOLDER -path "*/${TARG_ARCH}-gdbserver*.tar.bz2")
                echo GDBSERVER_BZ2 is $GDBSERVER_BZ2
                echo tar -xjf "$GDBSERVER_BZ2" --strip-components=3 -C "$DST_FOLDER/prebuilt/android-$TARG_ARCH/gdbserver/"
                tar -xjf "$GDBSERVER_BZ2" --strip-components=3 -C "$DST_FOLDER/prebuilt/android-$TARG_ARCH/gdbserver/"
                TARG_ARCH_FOLDER_NAME=$(system_name_to_final_folder_name $TARG_ARCH)
                # These bits will end up in the 'right' place - the toolchains themselves.
                TARG_TBZ2=$(system_name_to_final_folder_name $TARG_ARCH)
                TAR_BZ2S=$(find $PWD/$RELEASE_FOLDER -path "*/${TARG_TBZ2}-*-${SYSTEM}-${HOST_ARCH}.tar.bz2")
                echo TAR_BZ2S $TAR_BZ2S
                TOOLCHAIN_FOLDERS=
                for TAR_BZ2 in $TAR_BZ2S; do
                    TEMP=$(basename $TAR_BZ2)
                    SUFFIX=-${SYSTEM}-${HOST_ARCH}.tar.bz2
                    TOOLCHAIN_FOLDERS="$TOOLCHAIN_FOLDERS "${TEMP%%$SUFFIX}
                    THIS_DST_FOLDER=$DST_FOLDER/$(package_name_to_final_folder_suffix_name $TAR_BZ2)
                    mkdir -p $THIS_DST_FOLDER
                    tar -xjf "$TAR_BZ2" -C "$THIS_DST_FOLDER"
                done
                echo TOOLCHAIN_FOLDERS is $TOOLCHAIN_FOLDERS
                # These bits won't, so we extract them for each toolchain, ignoring the top level folder.
                # This means gdb (and gdbserver) are duplicated multiple times.
                GDB_BZ2S=$(find $PWD/$RELEASE_FOLDER -path "*/gdb-$(system_name_to_final_folder_name "${TARG_ARCH}")-*-${SYSTEM}-${HOST_ARCH}.tar.bz2")
                echo GDB_BZ2S is $GDB_BZ2S
                for TOOLCHAIN_FOLDER in $TOOLCHAIN_FOLDERS; do
                    for GDB_BZ2 in $GDB_BZ2S; do
                        THIS_DST_FOLDER=$DST_FOLDER/$(package_name_to_final_folder_suffix_name $GDB_BZ2)
                        echo tar -xjvf "$GDB_BZ2" --strip-components=1 -C "${THIS_DST_FOLDER}${TOOLCHAIN_FOLDER}"
                        tar -xjf "$GDB_BZ2" --strip-components=1 -C "${THIS_DST_FOLDER}${TOOLCHAIN_FOLDER}"
                    done
                    if [ ! -z "$PYTHON_DLLS" ]; then
                        GDB_PATH=$(dirname $(find ${THIS_DST_FOLDER}${TOOLCHAIN_FOLDER}/prebuilt/${SYSTEM_FOLDER} -name "*gdb.exe"))
                        echo GDB_PATH is $GDB_PATH
                        cp $PYTHON_DLLS $GDB_PATH
                    fi
                done
            done

            # Replace symlinks with the files and make the final 7z.
            PACK_TEMP=$PWD/pack_temp
            rm -rf $PACK_TEMP
            mkdir $PACK_TEMP

            # On Windows, we end up with a broken link from ld to ld.bfd (broken due to no .exe, and target file missing anyway)
            #  so just delete any missing links.
            LINKS=$(find $DST_FOLDER -type l)
            for LINK in $LINKS; do
                if [ $(LINKT=$(readlink "$LINK")) ] ; then
                    echo "Deleting non-existant link $LINK to $LINKT"
                    rm $LINK
                fi
            done

            pushd $DST_FOLDER/../
                tar -hcf - android-ndk-${SRC_REVISION} | tar -xf - -C $PACK_TEMP
            popd

            pushd $PACK_TEMP
               OUTPUT=$(compress_folders * android-ndk-${SRC_REVISION}-ma-$(system_name_to_ndk_release_name $SYSTEM $HOST_ARCH))
#               7za a -mx=9 ${NEW_ARCHIVE} * > /dev/null
               mv ${NEW_ARCHIVE} ../${RELEASE_FOLDER}/
               echo Done, see ../${RELEASE_FOLDER}/${NEW_ARCHIVE}
            popd
        fi
    done
done
