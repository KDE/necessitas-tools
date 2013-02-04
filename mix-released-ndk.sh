#!/bin/bash

HELP=
VERBOSE=1

set -e

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

# Returns
# $1 is system
# $2 is arch (or nothing)
system_name_to_ndk_release_name ()
{
    local _ARCH
    if [ ! -z "$2" -a ! "$2" = "default" ] ; then
        _ARCH = -$2
    else
        case $1 in
            linux)
            _ARCH=-x86
            ;;
            darwin)
            _ARCH=-x86
            ;;
            *)
            ;;
        esac
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
SRC_REVISION="r8d"
DATESUFFIX=$(date +%y%m%d)
RELEASE_FOLDER=release-$DATESUFFIX
# Otherwise it mixes them together.
AN_NDK_PER_HOST_ARCH=1
# Form some comma separated lists.
# ARCHIVE_NAME,
#for SYSTEM in $SYSTEMS; do

for SYSTEM in $SYSTEMS; do
    NEW_ARCHIVE=android-ndk-${SRC_REVISION}-ma-$(system_name_to_ndk_release_name $SYSTEM).7z
    if [ ! -f ${RELEASE_FOLDER}/${NEW_ARCHIVE} ]; then
        GOOGLES_ARCHIVE="http://dl.google.com/android/ndk/android-ndk-${SRC_REVISION}-$(system_name_to_ndk_release_name $SYSTEM).$(system_name_to_archive_extension $SYSTEM)"
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

        if [ "$HOST_ARCHES" = "default" ] ; then
            HOST_ARCHES="x86"
        elif [ "$HOST_ARCHES" = "both" ] ; then
            HOST_ARCHES="x86 x86_64"
        fi
        for HOST_ARCH in $HOST_ARCHES; do
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
        done

        # Rename windows-x86 back to windows.
        if [ "$SYSTEM" = "windows" ] ; then
          WINDOWS_FOLDERS=$(find $DST_FOLDER -name "windows-x86")
          for WINDOWS_FOLDER in $WINDOWS_FOLDERS; do
            mv $WINDOWS_FOLDER $(dirname $WINDOWS_FOLDER)/windows
          done
        fi

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
           7za a -mx=9 ${NEW_ARCHIVE} * > /dev/null
           mv ${NEW_ARCHIVE} ../${RELEASE_FOLDER}/
           echo Done, see ../${RELEASE_FOLDER}/${NEW_ARCHIVE}
        popd
    fi
done
