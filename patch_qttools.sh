#!/bin/bash

# This script is a quick replacement for qpatch. Really, using qpatch again would've maybe as good
# an option, if not better! However, this is only used so I can verify that the Windows Qt Tools
# are working when I change them and want to test them in Qt Creator.

TMP_DIR=/tmp
PATCHES=$PWD/patches

build_binmay() {
    if [[ -z $(which binmay) ]] ; then
        local _PATCH=$PATCHES/binmay-add-padding.patch
        curl -S -L -O http://www.filewut.com/spages/pages/software/binmay/files/binmay-110615.tar.gz
        [[ ! -d ${TMP_DIR}/binmay-110615 ]] && mkdir -p ${TMP_DIR}/binmay-110615
        tar -xf binmay-110615.tar.gz -C ${TMP_DIR}/
        pushd ${TMP_DIR}/binmay-110615
        patch -p0 < $_PATCH
        make binmay.exe #&>make-binmay.log
        cp binmay.exe /usr/local/bin
        popd
        echo "binmay built."
    fi
}

patch_binary() {
    local _BINARY="$1"
    local _SEARCH="$2"
    local _REPLACE="$3"
    build_binmay
#    echo "patch_binary $_BINARY, looking for $_SEARCH, replacing with $_REPLACE"
    local _TMPFILE=${TMP_DIR}/binmay.tmp
    cp $_BINARY $_TMPFILE
    binmay -a -i $_TMPFILE -s "t:$_SEARCH" -r "t:$_REPLACE" -o ${_BINARY}
}

patch_binary_hex() {
    local _BINARY="$1"
    local _SEARCH="$2"
    local _REPLACE="$3"
    build_binmay
#    echo "patch_binary_hex $_BINARY, looking for $_SEARCH, replacing with $_REPLACE"
    local _TMPFILE=${TMP_DIR}/binmay.tmp
    cp $_BINARY $_TMPFILE
    binmay -a -i $_TMPFILE -s "h:$_SEARCH" -r "h:$_REPLACE" -o ${_BINARY}
}

# $1 is the full path to the archive, $2 is top level folder, $3 is arch string (armeabi, armeabi-v7a or armeabi-android_4?) saves to $1.patched.7z!
patch_qttools_archive() {
    local ARCHIVE=$1
    local TOPFOLDER=$2
    local ARCHNAME=$3
    pushd /tmp
    rm -rf $PWD/$TOPFOLDER
    7za x $ARCHIVE
    local EXES=$(find $PWD/$TOPFOLDER -name "*.exe")
    for EXE in $EXES
    do
        for FOLDER in doc include lib bin plugins imports translations examples demos
        do
            patch_binary $EXE /tmp/necessitas/alpha4/Android/Qt/482/build-$ARCHNAME/install/$FOLDER C:\\Users\\nonesush\\necessitas\\Android\\Qt\\482\\${ARCHNAME}\\${FOLDER}
        done
        patch_binary $EXE /tmp/necessitas/alpha4/Android/Qt/482/build-$ARCHNAME/install C:\\Users\\nonesush\\necessitas\\Android\\Qt\\482\\${ARCHNAME}
    done
    7za a -mx=9 $(dirname $ARCHIVE)/patched-$(basename $ARCHIVE) $PWD/$TOPFOLDER
    echo "Done, see $(dirname $ARCHIVE)/patched-$(basename $ARCHIVE)"
    popd
}

patch_qttools_archive C:/org.kde.necessitas.android.qt.armeabi_android_4/data/qt-tools-windows.7z Android armeabi-android-4
patch_qttools_archive C:/org.kde.necessitas.android.qt.armeabi/data/qt-tools-windows.7z Android armeabi
patch_qttools_archive C:/org.kde.necessitas.android.qt.armeabi_v7a/data/qt-tools-windows.7z Android armeabi-v7a
