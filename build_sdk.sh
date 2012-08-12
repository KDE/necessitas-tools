#!/bin/bash -x

# Copyright (c) 2011, BogDan Vatra <bog_dan_ro@yahoo.com>
# Copyright (c) 2011, Ray Donnelly <mingw.android@gmail.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License or (at your option) version 3 or any later version
# accepted by the membership of KDE e.V. (or its successor approved
# by the membership of KDE e.V.), which shall act as a proxy
# defined in Section 14 of version 3 of the license.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

. sdk_vars.sh

function help
{
    echo "Help"
}

while getopts "h:c:" arg; do
case $arg in
    h)
        help
        exit 0
        ;;
    c)
        CHECKOUT_BRANCH=$OPTARG
        ;;
    ?)
        help
        exit 0
        ;;
esac
done

REPO_SRC_PATH=$PWD
TODAY=`date +%Y-%m-%d`

# This must be the same as BUILD_DIR in build_ndk.sh
if [ "$OSTYPE_MAJOR" = "msys" ] ; then
    TEMP_PATH=/usr/nec
else
    TEMP_PATH=/tmp/necessitas
fi

if [ "$OSTYPE_MAJOR" = "darwin" ]; then
    # On Mac OS X, user accounts don't have write perms for /var, same is true for Ubuntu.
    sudo mkdir -p $TEMP_PATH
    sudo chmod 777 $TEMP_PATH
    sudo mkdir -p $TEMP_PATH/out/necessitas
    sudo chmod 777 $TEMP_PATH/out/necessitas
    STRIP="strip -S"
    CPRL="cp -RL"
else
    mkdir -p $TEMP_PATH/out/necessitas
    STRIP="strip -s"
    CPRL="cp -rL"
fi

. sdk_cleanup.sh

export PATH=$PATH:${TEMP_PATH}/host_compiler_tools/mingw/i686-w64-mingw32/bin

# Global just because 2 functions use them, only acceptable values for GDB_VER are 7.2 and 7.3
GDB_VER=7.3
#GDB_VER=7.2

pushd $TEMP_PATH

MINISTRO_REPO_PATH=$TEMP_PATH/out/ministro
REPO_PATH=$TEMP_PATH/out/necessitas/sdk
if [ ! -d $TEMP_PATH/out/necessitas/sdk_src/org.kde.necessitas ]
then
    mkdir -p $TEMP_PATH/out/necessitas/sdk_src
    cp -a $REPO_SRC_PATH/packages/* $TEMP_PATH/out/necessitas/sdk_src/
    preparePackages
fi
REPO_PATH_PACKAGES=$TEMP_PATH/out/necessitas/sdk_src
STATIC_QT_PATH=""
SHARED_QT_PATH=""
SDK_TOOLS_PATH=""
ANDROID_STRIP_BINARY=""
ANDROID_READELF_BINARY=""
#QPATCH_PATH=""
EXE_EXT=""

function get_build_qtplatform
{
    if [ "$OSTYPE_MAJOR" = "msys" ] ; then
       echo win32-g++-4.6
    elif [ "$OSTYPE_MAJOR" = "darwin" ] ; then
       echo macx-g++
    else
       echo linux-g++
    fi
}

# Call this once initially with $OSTYPE_MAJOR
# then with msys or darwin before building each
# cross host's qt, installer-framework or qtcreator
function Set_HOST_OSTYPE
{
    HOST_OSTYPE_MAJOR=$1
    HOST_STRIP=strip
    HOST_EXE_EXT=
    if [ "$HOST_OSTYPE_MAJOR" = "msys" ] ; then
        HOST_QT_GIT_URL=git://anongit.kde.org/android-qt.git
        HOST_QT_BRANCH="remotes/origin/ports-win"
        HOST_CFG_OPTIONS=" -reduce-exports -ms-bitfields -no-freetype -no-fontconfig -prefix . -little-endian -host-little-endian -fast " # "-little-endian -host-little-endian -fast" came from BogDan's cross.diff email.
        if [ $OSTYPE_MAJOR = "msys" ] ; then
            HOST_CFG_PLATFORM="win32-g++"
        else
            HOST_CFG_PLATFORM="win32-g++-cross"
            HOST_CFG_OPTIONS=$HOST_CFG_OPTIONS" -arch windows"
            HOST_STRIP="i686-w64-mingw32-strip"
            export PATH=${TEMP_PATH}/host_compiler_tools/mingw/i686-w64-mingw32/bin:$PATH
        fi
        HOST_QM_CFG_OPTIONS="CONFIG+=ms_bitfields CONFIG+=static_gcclibs"
        HOST_TAG=windows
        HOST_TAG_NDK=windows
        SHLIB_EXT=.dll
        SCRIPT_EXT=.bat
        HOST_EXE_EXT=.exe
    elif [ "$HOST_OSTYPE_MAJOR" = "darwin" ] ; then
        HOST_QT_GIT_URL=git://anongit.kde.org/android-qt.git
        HOST_QT_BRANCH="remotes/origin/ports"
        if [ $OSTYPE_MAJOR = "darwin" ] ; then
            HOST_CFG_PLATFORM="macx-g++"
            HOST_CFG_OPTIONS=" -little-endian -sdk /Developer/SDKs/MacOSX10.6.sdk -arch i386 -arch x86_64 -cocoa -prefix . "
        else
            HOST_CFG_PLATFORM="macx-g++-cross"
            export PATH=${TEMP_PATH}/host_compiler_tools/darwin/apple-osx/bin:$PATH
            HOST_CFG_OPTIONS=" -little-endian -sdk $HOME/MacOSX10.7.sdk -arch i386 -arch x86_64 -cocoa -prefix . "
            HOST_STRIP="i686-apple-darwin11-strip"
        fi
        HOST_QM_CFG_OPTIONS="CONFIG+=x86 CONFIG+=x86_64"
        # -reduce-exports doesn't work for static Mac OS X i386 build.
        # (ld: bad codegen, pointer diff in fulltextsearch::clucene::QHelpSearchIndexReaderClucene::run()     to global weak symbol vtable for QtSharedPointer::ExternalRefCountDatafor architecture i386)
        HOST_CFG_OPTIONS_STATIC=" -no-reduce-exports "
        HOST_TAG=darwin-x86
        HOST_TAG_NDK=darwin-x86
        SHLIB_EXT=.dylib
        if [ ! $OSTYPE_MAJOR = "darwin" ] ; then
            HOST_STRIP="i686-apple-darwin11-strip"
        fi
    else
        HOST_QT_GIT_URL=git://anongit.kde.org/android-qt.git
        HOST_QT_BRANCH="remotes/upstream/tags/v4.7.4"
        HOST_CFG_OPTIONS="-arch i386"
        HOST_CFG_PLATFORM="linux-g++"
        # HOST_CFG_OPTIONS="-arch x86_64"
        # HOST_CFG_PLATFORM="linux-g++-64"
        HOST_TAG=linux-x86
        HOST_TAG_NDK=linux-x86
        SHLIB_EXT=.so
    fi
}

function error_msg
{
    echo $1 >&2
    exit 1
}

function createArchive # params $1 folder, $2 archive name, $3 extra params
{
    if [ $EXTERNAL_7Z != "" ]
    then
        EXTRA_PARAMS=""
        if [ $HOST_TAG = "windows" ]
        then
            EXTRA_PARAMS=$EXTERNAL_7Z_A_PARAMS_WIN
        fi
        $EXTERNAL_7Z $EXTERNAL_7Z_A_PARAMS $EXTRA_PARAMS $3 $2 "$1" || error_msg "Can't create archive $EXTERNAL_7Z $EXTERNAL_7Z_A_PARAMS $EXTRA_PARAMS $3 $2 $1"
    else
        $SDK_TOOLS_PATH/archivegen "$1" $2
    fi
}

function removeAndExit
{
    rm -fr $1 && error_msg "Can't download $1"
}


function downloadIfNotExists
{
    if [ ! -f $1 ]
    then
    if [ "$OSTYPE_MAJOR" = "darwin" ] ; then
            curl --insecure -S -L -O $2 || removeAndExit $1
        else
            wget --no-check-certificate -c $2 || removeAndExit $1
        fi
    fi
}

function doMake
{
    MAKEPROG=make
    if [ "$OSTYPE" = "msys" -o  "$OSTYPE_MAJOR" = "darwin" ] ; then
        if [ "$OSTYPE" = "msys" ] ; then
            MAKEDIR=`pwd -W`
            MAKEFOREVER=1
            if [ ! -z $3 ] ; then
                MAKEPROG=$3
            fi
        else
            MAKEDIR=`pwd`
            MAKEFOREVER=0
        fi
        MAKEFILE=$MAKEDIR/Makefile
        $MAKEPROG -f $MAKEFILE -j$JOBS
        while [ "$?" != "0" -a "$MAKEFOREVER" = "1" ]
        do
            if [ -f /usr/break-make ]; then
                echo "Detected break-make"
                rm -f /usr/break-make
                error_msg $1
            fi
            $MAKEPROG -f $MAKEFILE -j$JOBS
        done
        echo $2>all_done
    else
        make -j$JOBS $4|| error_msg $1
        echo $2>all_done
    fi
}

function doMakeInstall
{
    MAKEPROG=make
    if [ "$OSTYPE" = "msys" -o  "$OSTYPE_MAJOR" = "darwin" ] ; then
        if [ "$OSTYPE" = "msys" ] ; then
            MAKEDIR=`pwd -W`
            MAKEFOREVER=1
            if [ ! -z $2 ] ; then
                MAKEPROG=$2
            fi
        else
            MAKEDIR=`pwd`
            MAKEFOREVER=0
        fi
        MAKEFILE=$MAKEDIR/Makefile
        $MAKEPROG -f $MAKEFILE install
        while [ "$?" != "0" -a "$MAKEFOREVER" = "1" ]
        do
            if [ -f /usr/break-make ]; then
                echo "Detected break-make"
                rm -f /usr/break-make
                error_msg $1
            fi
            $MAKEPROG -f $MAKEFILE install
        done
        echo $2>all_done
    else
        make install || error_msg $1
        echo $2>all_done
    fi
}


function doSed
{
    if [ "$OSTYPE_MAJOR" = "darwin" ]
    then
        sed -i '.bak' "$1" $2
        rm ${2}.bak
    else
        sed "$1" -i $2
    fi
}


function cloneCheckoutKDEGitRepo #params $1 repo name, $2 branch
{
    pushd qt-src
        git checkout $2
        git pull
    popd
}

# $1 is either -d (debug build) or nothing.
function prepareHostQt
{
    # download, compile & install qt, it is used to compile the installer
    HOST_QT_CONFIG=$1

    THIS_QT_BRANCH=$HOST_QT_BRANCH
    THIS_QT_BRANCH_NAME=$(basename $THIS_QT_BRANCH)
    export QT_SRCDIR=$PWD/qt-src-${THIS_QT_BRANCH_NAME}

    if [ ! -d $(basename $QT_SRCDIR) ]
    then
        git clone ${HOST_QT_GIT_URL} $(basename $QT_SRCDIR) || error_msg "Can't clone ${1}"
        pushd $(basename $QT_SRCDIR)
        git config --add remote.origin.fetch +refs/upstream/*:refs/remotes/upstream/*
        git fetch
        popd
    fi

    if [ "$HOST_QT_CONFIG" = "-d" ] ; then
        if [ "$HOST_OSTYPE_MAJOR" = "msys" ] ; then
            OPTS_CFG=" -debug "
            HOST_QT_CFG="CONFIG+=debug QT+=network"
        elif [ "$HOST_OSTYPE_MAJOR" = "darwin" ] ; then
            OPTS_CFG=" -debug-and-release "
            HOST_QT_CFG="CONFIG+=debug QT+=network"
        fi
    else
        OPTS_CFG=" -release "
        HOST_QT_CFG="CONFIG+=release QT+=network"
    fi

    STATIC_PREFIX=static-build-${THIS_QT_BRANCH_NAME}
    SHARED_PREFIX=shared-build-${THIS_QT_BRANCH_NAME}
    if [ ! "$HOST_OSTYPE_MAJOR" = "$OSTYPE_MAJOR" ] ; then
        STATIC_PREFIX=$STATIC_PREFIX-$HOST_OSTYPE_MAJOR
        SHARED_PREFIX=$SHARED_PREFIX-$HOST_OSTYPE_MAJOR
        HOST_CFG_OPTIONS="-xplatform $HOST_CFG_PLATFORM -platform $(get_build_qtplatform) "$HOST_CFG_OPTIONS
        if [ "$HOST_OSTYPE_MAJOR" = "msys" ] ; then
            export PATH=${TEMP_PATH}/host_compiler_tools/mingw/i686-w64-mingw32/bin:$PATH
        else
            export PATH=${TEMP_PATH}/host_compiler_tools/darwin/apple-osx/bin:$PATH
        fi
    else
        HOST_CFG_OPTIONS=$HOST_CFG_OPTIONS" -platform $HOST_CFG_PLATFORM"
    fi

    mkdir ${STATIC_PREFIX}${HOST_QT_CONFIG}
    pushd ${STATIC_PREFIX}${HOST_QT_CONFIG}
    STATIC_QT_PATH=$PWD
    if [ ! -f all_done ]
    then
        pushd $QT_SRCDIR
        git checkout -b $THIS_QT_BRANCH_NAME $THIS_QT_BRANCH
        git pull
        popd
        rm -fr *
        $QT_SRCDIR/configure -fast -nomake examples -nomake demos -nomake tests -qt-zlib -no-gif -qt-libtiff -qt-libpng -qt-libmng -qt-libjpeg -opensource -static -no-webkit -no-phonon -no-dbus -no-opengl -no-qt3support -no-xmlpatterns -no-svg -confirm-license $HOST_CFG_OPTIONS $HOST_CFG_OPTIONS_STATIC $OPTS_CFG -host-little-endian --prefix=$PWD || error_msg "Can't configure $HOST_QT_VERSION"
        doMake "Can't compile static $HOST_QT_VERSION" "all done" ma-make
        if [ "$HOST_OSTYPE_MAJOR" = "msys" ]; then
            # Horrible; need to fix this properly.
            cp -f mkspecs/win32-g++/qplatformdefs.h mkspecs/default/
        fi
    fi
    popd

    #build qt shared, needed by QtCreator
    mkdir ${SHARED_PREFIX}${HOST_QT_CONFIG}
    pushd ${SHARED_PREFIX}${HOST_QT_CONFIG}
    SHARED_QT_PATH=$PWD
    if [ ! -f all_done ]
    then
        pushd $QT_SRCDIR
        git checkout -b $THIS_QT_BRANCH_NAME $THIS_QT_BRANCH
        git pull
        popd
        rm -fr *
        $QT_SRCDIR/configure $HOST_CFG_OPTIONS -fast -nomake examples -nomake demos -nomake tests -system-zlib -qt-libtiff -qt-libpng -qt-libmng -qt-libjpeg -opensource -shared -webkit -no-phonon -qt-sql-sqlite -plugin-sql-sqlite -no-qt3support -confirm-license $HOST_CFG_OPTIONS $OPTS_CFG -host-little-endian --prefix=$PWD || error_msg "Can't configure $HOST_QT_VERSION"
        doMake "Can't compile shared $HOST_QT_VERSION" "all done" ma-make
        if [ "$HOST_OSTYPE_MAJOR" = "msys" ]; then
            # Horrible; need to fix this properly.
            cp -f mkspecs/win32-g++/qplatformdefs.h mkspecs/default/
        fi
    fi
    popd
}

function prepareSdkInstallerTools
{
    # get installer source code
    if [ "$HOST_OSTYPE_MAJOR" = "$HOST_OSTYPE" ] ; then
        QTINST_PATH=necessitas-installer-framework
    else
        QTINST_PATH=necessitas-installer-framework-${HOST_TAG}${HOST_QT_CONFIG}
    fi

    SDK_TOOLS_PATH=${PWD}/${QTINST_PATH}/installerbuilder/bin

    if [ ! -d $QTINST_PATH ]
    then
        git clone git://anongit.kde.org/necessitas-installer-framework.git $QTINST_PATH || error_msg "Can't clone necessitas-installer-framework"
    fi

    pushd $QTINST_PATH/installerbuilder
    git checkout $CHECKOUT_BRANCH
    git pull
    if [ ! -f all_done ]
    then
        $STATIC_QT_PATH/bin/qmake CONFIG+=static $HOST_QT_CFG $HOST_QM_CFG_OPTIONS QMAKE_CXXFLAGS=-fpermissive -r || error_msg "Can't configure $QTINST_PATH"
        doMake "Can't compile $QTINST_PATH" "all done" ma-make
    fi
    popd
    pushd ${PWD}/${QTINST_PATH}/installerbuilder/bin
    if [ -z $HOST_QT_CONFIG ] ; then
        $HOST_STRIP *
    fi
    popd
}


function prepareNecessitasQtCreator
{
    # Clone to different paths for each host as build is done in-place.
    if [ "$HOST_OSTYPE_MAJOR" = "msys" -o "$HOST_OSTYPE_MAJOR" = "darwin" ] ; then
        QTC_PATH=android-qt-creator-${HOST_TAG}${HOST_QT_CONFIG}
    else
        QTC_PATH=android-qt-creator${HOST_QT_CONFIG}
    fi

    if [ ! -d $QTC_PATH ]
    then
        git clone git://anongit.kde.org/android-qt-creator.git $QTC_PATH || error_msg "Can't clone android-qt-creator"
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.tools.qtcreator/data/qtcreator-${HOST_TAG}${HOST_QT_CONFIG}.7z ]
    then
        pushd $QTC_PATH
        if [ "$OSTYPE_MAJOR" = "darwin" ] ; then
            # This is only used for make docs on Mac.
            QTC_INST_DIRNAME=Qt\ Creator.app
            QTC_INST_PATH="$PWD/bin/$QTC_INST_DIRNAME"
        else
            QTC_INST_DIRNAME=QtCreator$HOST_QT_CONFIG
            QTC_INST_PATH=$PWD/$QTC_INST_DIRNAME
        fi
        if [ ! -f all_done ] ; then
            git checkout unstable
            git pull
            export UPDATEINFO_DISABLE=false
            # DEFINES+=IDE_SETTINGSVARIANT=Necessitas
            $SHARED_QT_PATH/bin/qmake CONFIG+=shared $HOST_QT_CFG $HOST_QM_CFG_OPTIONS -r || error_msg "Can't configure android-qt-creator"
            doMake "Can't compile $QTC_PATH" "all done" ma-make
        fi
        if [ "$HOST_OSTYPE_MAJOR" = "darwin" ] ; then
            # Mac doesn't use INSTALL_ROOT (except docs/translations where it'd be incorrect)
            mkdir -p $INSTALL_ROOT/bin
            export INSTALL_ROOT="$QTC_INST_PATH"
            make docs && PATH=$SHARED_QT_PATH/bin:$PATH make deployqt
        else
            export INSTALL_ROOT=$QTC_INST_PATH
            make docs install
        fi

        if [ "$HOST_OSTYPE_MAJOR" = "msys" ]; then
            mkdir -p $QTC_INST_PATH/bin
            cp -rf lib/qtcreator/* $QTC_INST_PATH/bin/
            cp -a /mingw/bin/libgcc_s_sjlj-1.dll $QTC_INST_PATH/bin/
            cp -a /mingw/bin/libstdc++-6.dll $QTC_INST_PATH/bin/
            QT_LIB_DEST=$QTC_INST_PATH/bin/
            cp -a $SHARED_QT_PATH/lib/*.dll $QT_LIB_DEST
            cp -a bin/necessitas.bat $QTC_INST_PATH/bin/
# Want to re-enable this, but libintl-8.dll is getting used.
#            git clone git://gitorious.org/mingw-android-various/mingw-android-various.git android-various
#            mkdir -p android-various/make-3.82-build
#            pushd android-various/make-3.82-build
#            ../make-3.82/build-mingw.sh
#            popd
#            cp android-various/make-3.82-build/make.exe $QTC_INST_PATH/bin/
            pushd $QTC_INST_PATH/bin/
            downloadIfNotExists make.exe http://mingw-and-ndk.googlecode.com/files/make.exe
            mv make.exe ma-make.exe
            popd
        elif [ "$HOST_OSTYPE_MAJOR" = "linux-gnu" ]; then
            mkdir -p $QTC_INST_PATH/Qt/imports
            mkdir -p $QTC_INST_PATH/Qt/plugins
            mkdir -p $QTC_INST_PATH/Qt/lib
            QT_LIB_DEST=$QTC_INST_PATH/Qt/lib/
            cp -a $SHARED_QT_PATH/lib/* $QT_LIB_DEST
            rm -fr $QT_LIB_DEST/pkgconfig
            find . $QT_LIB_DEST -name *.la | xargs rm -fr
            find . $QT_LIB_DEST -name *.prl | xargs rm -fr
            cp -a $SHARED_QT_PATH/imports/* ${QT_LIB_DEST}../imports
            cp -a $SHARED_QT_PATH/plugins/* ${QT_LIB_DEST}../plugins
            cp -a bin/necessitas $QTC_INST_PATH/bin/
        fi
        mkdir "$QTC_INST_PATH/images"
        cp -a bin/necessitas*.png "$QTC_INST_PATH/images/"
        pushd "$QTC_INST_PATH"
        if [ -z $HOST_QT_CONFIG ] ; then
            find . -name "*$SHLIB_EXT" | xargs $HOST_STRIP
        fi
        find . -name "*.a" | xargs rm -fr
        find . -name "*.prl" | xargs rm -fr
        rm -fr bin/pkgconfig
        popd
        pushd $(dirname "$QTC_INST_PATH")
        createArchive "$QTC_INST_DIRNAME" qtcreator-${HOST_TAG}${HOST_QT_CONFIG}.7z
        mkdir -p $REPO_PATH_PACKAGES/org.kde.necessitas.tools.qtcreator/data
        mv qtcreator-${HOST_TAG}${HOST_QT_CONFIG}.7z $REPO_PATH_PACKAGES/org.kde.necessitas.tools.qtcreator/data/qtcreator-${HOST_TAG}${HOST_QT_CONFIG}.7z
        popd
        popd
    fi
}

# This installs the libs directly into the mingw-w64 installation folders
# as determined by ${HOST_CC_PREFIX}gcc --print-search-dirs. This is the
# cleanest way I think.
function makeInstallMinGWLibs
{
    if [ ! $"OSTYPE_MAJOR" = "msys" ] ; then
        HOST_CC_PREFIX="i686-w64-mingw32-"
        HOST_CONFIG="--host=i686-w64-mingw32"
        export PATH=${TEMP_PATH}/host_compiler_tools/mingw/i686-w64-mingw32/bin:$PATH
    else
        HOST_CC_PREFIX=
        HOST_CONFIG=
    fi

    # Calculate the gcc install prefix from the install location of mingw gcc. Makes a few
    # assumptions about the output format of --print-search-dirs but better than any
    # alternative I can come up with.
    MINGW_PREFIX=$(${HOST_CC_PREFIX}gcc --print-search-dirs | head -1 | cut -d' ' -f 2)
    MINGW_PREFIX=$(echo $MINGW_PREFIX | sed 's/\\/\//g')
    MINGW_PREFIX=$(cd $MINGW_PREFIX; echo $PWD)
    MINGW_PREFIX=$(dirname $MINGW_PREFIX)
    MINGW_TOPLEV=$(basename $MINGW_PREFIX)
    MINGW_PREFIX=$(dirname $(dirname $(dirname $MINGW_PREFIX)))
    MINGW_PREFIX=$MINGW_PREFIX/$MINGW_TOPLEV

    if [ -d mingw-w64-libs-build ] ; then
        return
    fi

    mkdir -p ${MINGW_PREFIX}/bin
    mkdir -p ${MINGW_PREFIX}/share

    mkdir mingw-w64-libs-build
    pushd mingw-w64-libs-build

#    mkdir texinfo
#    pushd texinfo
#    downloadIfNotExists texinfo-4.13a-2-msys-1.0.13-bin.tar.lzma http://heanet.dl.sourceforge.net/project/mingw/MSYS/texinfo/texinfo-4.13a-2/texinfo-4.13a-2-msys-1.0.13-bin.tar.lzma
#    rm -rf texinfo-4.13a-2-msys-1.0.13-bin.tar
#    7za x texinfo-4.13a-2-msys-1.0.13-bin.tar.lzma
#    tar -xvf texinfo-4.13a-2-msys-1.0.13-bin.tar
#    mv bin/* /usr/local/bin
#    mv share/* /usr/local/share
#    popd

    if [ ! -f ${MINGW_PREFIX}/lib/libcurses.a ] ; then
        downloadIfNotExists PDCurses-3.4.tar.gz http://downloads.sourceforge.net/pdcurses/pdcurses/3.4/PDCurses-3.4.tar.gz
        rm -rf PDCurses-3.4
        tar -xvzf PDCurses-3.4.tar.gz
        pushd PDCurses-3.4/win32
        # I should really make and submit a patch for this instead.
        doSed $"90s/-copy/-cp/" mingwin32.mak
        doSed $"s/CC		= gcc/CC		= gcc\nAR		= ar\nRANLIB		= ranlib/" mingwin32.mak
        doSed $"s/	\$(LIBEXE) \$(LIBFLAGS) \$@ \$?/	\$(LIBEXE) \$(LIBFLAGS) \$@ \$?\n	\$(RANLIB) \$@/" mingwin32.mak
        doSed $"s/LIBEXE = gcc \$(DEFFILE)/LIBEXE = \$(CC) \$(DEFFILE)/" mingwin32.mak
        doSed $"s/LINK		= gcc/LINK		= \$(CC)/" mingwin32.mak
        make -f mingwin32.mak WIDE=Y UTF8=Y DLL=N CC=${HOST_CC_PREFIX}gcc AR=${HOST_CC_PREFIX}ar RANLIB=${HOST_CC_PREFIX}ranlib
        cp pdcurses.a ${MINGW_PREFIX}/lib/libcurses.a
        cp pdcurses.a ${MINGW_PREFIX}/lib/libncurses.a
        cp pdcurses.a ${MINGW_PREFIX}/lib/libpdcurses.a
        cp panel.a ${MINGW_PREFIX}/lib/libpanel.a
        cp ../curses.h ${MINGW_PREFIX}/include
        cp ../panel.h ${MINGW_PREFIX}/include
        popd
    fi

    # download, compile & install zlib to /usr
    if [ ! -f ${MINGW_PREFIX}/lib/libz.a ] ; then
        downloadIfNotExists zlib-1.2.7.tar.gz http://downloads.sourceforge.net/libpng/zlib/1.2.7/zlib-1.2.7.tar.gz
        tar -xvzf zlib-1.2.7.tar.gz
        pushd zlib-1.2.7
        doSed $"s#/usr/local#${MINGW_PREFIX}#" win32/Makefile.gcc
        make -f win32/Makefile.gcc CC=${HOST_CC_PREFIX}gcc PREFIX=${HOST_CC_PREFIX}
        export INCLUDE_PATH=${MINGW_PREFIX}/include
        export LIBRARY_PATH=${MINGW_PREFIX}/lib
        export BINARY_PATH=${MINGW_PREFIX}/bin
        make -f win32/Makefile.gcc install PREFIX=${HOST_CC_PREFIX}
        rm -rf zlib-1.2.7
        popd
    fi

    # This make can't build gdb or python (it doesn't re-interpret MSYS mounts), but includes jobserver patch from
    # Troy Runkel: http://article.gmane.org/gmane.comp.gnu.make.windows/3223/match=
    # which fixes the longstanding make.exe -jN process hang, allowing un-attended builds of all Qt things.
    if [ "$OSTYPE_MAJOR" = "msys" ] ; then
        downloadIfNotExists make.exe http://mingw-and-ndk.googlecode.com/files/make.exe
        mv make.exe /usr/local/bin/ma-make.exe
    fi

    if [ ! -f ${MINGW_PREFIX}/lib/libiconv.a ] ; then
        downloadIfNotExists libiconv-1.14.tar.gz http://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.14.tar.gz
        rm -rf libiconv-1.14
        tar -xvzf libiconv-1.14.tar.gz
        pushd libiconv-1.14
        ./configure ${HOST_CONFIG} --enable-static --disable-shared --with-curses=$install_dir --enable-multibyte --prefix=${MINGW_PREFIX}  CFLAGS=-O3 CC=${HOST_CC_PREFIX}gcc
        make
        # Without a /mingw folder, this fails, but only after copying libiconv.a to the right place.
        make install
        doSed $"s/iconv_t cd,  char\* \* inbuf/iconv_t cd,  const char\* \* inbuf/g" include/iconv.h
        cp include/iconv.h ${MINGW_PREFIX}/include
        popd
    fi

    popd
}

function makeInstallMinGWLibsOld
{
    mkdir mingw-bits
    pushd mingw-bits

    install_dir=$1

    downloadIfNotExists readline-6.2.tar.gz http://ftp.gnu.org/pub/gnu/readline/readline-6.2.tar.gz
    rm -rf readline-6.2
    tar -xvzf readline-6.2.tar.gz
    pushd readline-6.2
    CFLAGS=-O2 && ./configure --enable-static --disable-shared --with-curses=$install_dir --enable-multibyte --prefix=  CFLAGS=-O2
    make && make DESTDIR=$install_dir install
    popd

    popd
}

function prepareNDKs
{
    # repack official windows NDK
    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.${ANDROID_NDK_VERSION}/data/android-ndk-${ANDROID_NDK_VERSION}-windows.7z ]
    then
        downloadIfNotExists android-ndk-${ANDROID_NDK_VERSION}-windows.zip http://dl.google.com/android/ndk/android-ndk-${ANDROID_NDK_VERSION}-windows.zip
        rm -fr android-ndk-${ANDROID_NDK_VERSION}
        unzip android-ndk-${ANDROID_NDK_VERSION}-windows.zip
        createArchive android-ndk-${ANDROID_NDK_VERSION} android-ndk-${ANDROID_NDK_VERSION}-windows.7z
        mkdir -p $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.${ANDROID_NDK_VERSION}/data
        mv android-ndk-${ANDROID_NDK_VERSION}-windows.7z $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.${ANDROID_NDK_VERSION}/data/android-ndk-${ANDROID_NDK_VERSION}-windows.7z
        rm -fr android-ndk
    fi

    # repack official mac NDK
    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.${ANDROID_NDK_VERSION}/data/android-ndk-${ANDROID_NDK_VERSION}-darwin-x86.7z ]
    then
        downloadIfNotExists android-ndk-${ANDROID_NDK_VERSION}-darwin-x86.tar.bz2 http://dl.google.com/android/ndk/android-ndk-${ANDROID_NDK_VERSION}-darwin-x86.tar.bz2
        rm -fr android-ndk-${ANDROID_NDK_VERSION}
        tar xjvf android-ndk-${ANDROID_NDK_VERSION}-darwin-x86.tar.bz2
        createArchive android-ndk-${ANDROID_NDK_VERSION} android-ndk-${ANDROID_NDK_VERSION}-darwin-x86.7z
        mkdir -p $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.${ANDROID_NDK_VERSION}/data
        mv android-ndk-${ANDROID_NDK_VERSION}-darwin-x86.7z $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.${ANDROID_NDK_VERSION}/data/android-ndk-${ANDROID_NDK_VERSION}-darwin-x86.7z
        rm -fr android-ndk
    fi

    # repack official linux-x86 NDK
    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.${ANDROID_NDK_VERSION}/data/android-ndk-${ANDROID_NDK_VERSION}-linux-x86.7z ]
    then
        downloadIfNotExists android-ndk-${ANDROID_NDK_VERSION}-linux-x86.tar.bz2 http://dl.google.com/android/ndk/android-ndk-${ANDROID_NDK_VERSION}-linux-x86.tar.bz2
        rm -fr android-ndk-${ANDROID_NDK_VERSION}
        tar xjvf android-ndk-${ANDROID_NDK_VERSION}-linux-x86.tar.bz2
        createArchive android-ndk-${ANDROID_NDK_VERSION} android-ndk-${ANDROID_NDK_VERSION}-linux-x86.7z
        mkdir -p $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.${ANDROID_NDK_VERSION}/data
        mv android-ndk-${ANDROID_NDK_VERSION}-linux-x86.7z $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.${ANDROID_NDK_VERSION}/data/android-ndk-${ANDROID_NDK_VERSION}-linux-x86.7z
        rm -fr android-ndk
    fi

    # repack mingw android windows NDK
    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.ma/data/android-ndk-${ANDROID_NDK_VERSION}-ma-windows.7z ]
    then
        downloadIfNotExists android-ndk-${ANDROID_NDK_VERSION}-ma-windows.7z http://mingw-and-ndk.googlecode.com/files/android-ndk-${ANDROID_NDK_VERSION}-ma-windows.7z
        rm -fr android-ndk-${ANDROID_NDK_VERSION}
        rm -fr android-ndk
        $EXTERNAL_7Z $EXTERNAL_7Z_X_PARAMS android-ndk-${ANDROID_NDK_VERSION}-ma-windows.7z
        mv android-ndk-${ANDROID_NDK_VERSION} android-ndk
        mkdir -p $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.ma/data
        createArchive android-ndk $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.ma/data/android-ndk-${ANDROID_NDK_VERSION}-ma-windows.7z
        rm -fr android-ndk
    fi

    # repack mingw android mac NDK
    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.ma/data/android-ndk-${ANDROID_NDK_VERSION}-ma-darwin-x86.7z ]
    then
        downloadIfNotExists android-ndk-${ANDROID_NDK_VERSION}-ma-darwin-x86.7z http://mingw-and-ndk.googlecode.com/files/android-ndk-${ANDROID_NDK_VERSION}-ma-darwin-x86.7z
        rm -fr android-ndk-${ANDROID_NDK_VERSION}
        rm -fr android-ndk
        $EXTERNAL_7Z $EXTERNAL_7Z_X_PARAMS android-ndk-${ANDROID_NDK_VERSION}-ma-darwin-x86.7z
        mv android-ndk-${ANDROID_NDK_VERSION} android-ndk
        mkdir -p $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.ma/data
        createArchive android-ndk $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.ma/data/android-ndk-${ANDROID_NDK_VERSION}-ma-darwin-x86.7z
        rm -fr android-ndk
    fi

    # repack mingw android linux-x86 NDK
    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.ma/data/android-ndk-${ANDROID_NDK_VERSION}-ma-linux-x86.7z ]
    then
        downloadIfNotExists android-ndk-${ANDROID_NDK_VERSION}-ma-linux-x86.7z http://mingw-and-ndk.googlecode.com/files/android-ndk-${ANDROID_NDK_VERSION}-ma-linux-x86.7z
        rm -fr android-ndk-${ANDROID_NDK_VERSION}
        rm -fr android-ndk
        $EXTERNAL_7Z $EXTERNAL_7Z_X_PARAMS android-ndk-${ANDROID_NDK_VERSION}-ma-linux-x86.7z
        mv android-ndk-${ANDROID_NDK_VERSION} android-ndk
        mkdir -p $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.ma/data
        createArchive android-ndk $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.ma/data/android-ndk-${ANDROID_NDK_VERSION}-ma-linux-x86.7z
        rm -fr android-ndk
    fi

    if [ ! -d android-ndk ]; then
        if [ "$USE_MA_NDK" = "0" ]; then
            if [ "$OSTYPE" = "msys" ]; then
                downloadIfNotExists android-ndk-${ANDROID_NDK_VERSION}-windows.zip http://dl.google.com/android/ndk/android-ndk-${ANDROID_NDK_VERSION}-windows.zip
                unzip android-ndk-${ANDROID_NDK_VERSION}-windows.zip
            fi

            if [ "$OSTYPE_MAJOR" = "darwin" ]; then
                downloadIfNotExists android-ndk-${ANDROID_NDK_VERSION}-darwin-x86.tar.bz2 http://dl.google.com/android/ndk/android-ndk-${ANDROID_NDK_VERSION}-darwin-x86.tar.bz2
                tar xjvf android-ndk-${ANDROID_NDK_VERSION}-darwin-x86.tar.bz2
            fi

            if [ "$OSTYPE" = "linux-gnu" ]; then
                downloadIfNotExists android-ndk-${ANDROID_NDK_VERSION}-linux-x86.tar.bz2 http://dl.google.com/android/ndk/android-ndk-${ANDROID_NDK_VERSION}-linux-x86.tar.bz2
                tar xjvf android-ndk-${ANDROID_NDK_VERSION}-linux-x86.tar.bz2
            fi
        else
            if [ "$OSTYPE" = "msys" ]; then
                downloadIfNotExists android-ndk-${ANDROID_NDK_VERSION}-ma-windows.7z http://mingw-and-ndk.googlecode.com/files/android-ndk-${ANDROID_NDK_VERSION}-ma-windows.7z
                $EXTERNAL_7Z $EXTERNAL_7Z_X_PARAMS android-ndk-${ANDROID_NDK_VERSION}-ma-windows.7z
            fi

            if [ "$OSTYPE_MAJOR" = "darwin" ]; then
                downloadIfNotExists android-ndk-${ANDROID_NDK_VERSION}-ma-darwin-x86.7z http://mingw-and-ndk.googlecode.com/files/android-ndk-${ANDROID_NDK_VERSION}-ma-darwin-x86.7z
                $EXTERNAL_7Z $EXTERNAL_7Z_X_PARAMS android-ndk-${ANDROID_NDK_VERSION}-ma-darwin-x86.7z
            fi

            if [ "$OSTYPE" = "linux-gnu" ]; then
                downloadIfNotExists android-ndk-${ANDROID_NDK_VERSION}-ma-linux-x86.7z http://mingw-and-ndk.googlecode.com/files/android-ndk-${ANDROID_NDK_VERSION}-ma-linux-x86.7z
                $EXTERNAL_7Z $EXTERNAL_7Z_X_PARAMS android-ndk-${ANDROID_NDK_VERSION}-ma-linux-x86.7z
            fi
        fi
    fi
    mv android-ndk-${ANDROID_NDK_VERSION} android-ndk
    export ANDROID_NDK_ROOT=$PWD/android-ndk
    export ANDROID_NDK_TOOLCHAIN_PREFIX=arm-linux-androideabi
    ANDROID_STRIP_BINARY=$ANDROID_NDK_ROOT/toolchains/arm-linux-androideabi-4.6/prebuilt/$HOST_TAG_NDK/bin/arm-linux-androideabi-strip$EXE_EXT
    ANDROID_READELF_BINARY=$ANDROID_NDK_ROOT/toolchains/arm-linux-androideabi-4.6/prebuilt/$HOST_TAG_NDK/bin/arm-linux-androideabi-readelf$EXE_EXT
}

function prepareGDB
{
    package_name_ver=${GDB_VER//./_} # replace . with _
    if [ -z $GDB_TARG_HOST_TAG ] ; then
        GDB_PKG_NAME=gdb-$GDB_VER-$HOST_TAG
        GDB_FLDR_NAME=gdb-$GDB_VER
        package_path=$REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.gdb_$package_name_ver/data
    else
        GDB_PKG_NAME=gdb_$GDB_TARG_HOST_TAG-$GDB_VER
        GDB_FLDR_NAME=$GDB_PKG_NAME
        package_path=$REPO_PATH_PACKAGES/org.kde.necessitas.misc.host_gdb_$package_name_ver/data
    fi
    #This function depends on prepareNDKs
    if [ -f $package_path/$GDB_PKG_NAME.7z ]
    then
        return
    fi

    mkdir gdb-build
    pushd gdb-build
    pyversion=2.7
    pyfullversion=2.7.1
    install_dir=$PWD/install
    target_dir=$PWD/$GDB_FLDR_NAME
    mkdir -p $target_dir

    OLDPATH=$PATH
    if [ "$OSTYPE" = "linux-gnu" ] ; then
        HOST=i386-linux-gnu
        CC32="gcc -m32"
        CXX32="g++ -m32"
        PYCFGDIR=$install_dir/lib/python$pyversion/config
    else
        if [ "$OSTYPE" = "msys" ] ; then
            SUFFIX=.exe
            HOST=i686-pc-mingw32
            PYCFGDIR=$install_dir/bin/Lib/config
            export PATH=.:$PATH
            CC32=gcc.exe
            CXX32=g++.exe
            PYCCFG="--enable-shared"
         else
            # On some OS X installs (case insensitive filesystem), the dir "Python" clashes with the executable "python"
            # --with-suffix can be used to get around this.
            SUFFIX=Mac
            export PATH=.:$PATH
            CC32="gcc -m32"
            CXX32="g++ -m32"
        fi
    fi

    OLDCC=$CC
    OLDCXX=$CXX
    OLDCFLAGS=$CFLAGS

    downloadIfNotExists expat-2.0.1.tar.gz http://downloads.sourceforge.net/sourceforge/expat/expat-2.0.1.tar.gz || error_msg "Can't download expat library"
    if [ ! -d expat-2.0.1 ]
    then
        tar xzvf expat-2.0.1.tar.gz
        pushd expat-2.0.1
            CC=$CC32 CXX=$CXX32 ./configure --disable-shared --enable-static -prefix=/
            doMake "Can't compile expat" "all done"
            make DESTDIR=$install_dir install || error_msg "Can't install expat library"
        popd
    fi
    # Again, what a terrible failure.
    unset PYTHONHOME
    if [ ! -f Python-$pyfullversion/all_done ]
    then
        if [ "$OSTYPE" = "linux-gnu" ]; then
            downloadIfNotExists Python-$pyfullversion.tar.bz2 http://www.python.org/ftp/python/$pyfullversion/Python-$pyfullversion.tar.bz2 || error_msg "Can't download python library"
            tar xjvf Python-$pyfullversion.tar.bz2
            USINGMAPYTHON=0
        else
            if [ "$OSTYPE" = "msys" ]; then
                makeInstallMinGWLibs $install_dir
            fi
            rm -rf Python-$pyfullversion
            git clone git://gitorious.org/mingw-python/mingw-python.git Python-$pyfullversion || error_msg "Can't clone MinGW Python"
            USINGMAPYTHON=1
        fi

        pushd Python-$pyfullversion
        if [ "$OSTYPE" = "msys" ] ; then
            # Hack for MSI.
            cp /c/strawberry/c/i686-w64-mingw32/include/fci.h fci.h
        fi
        if [ "$USINGMAPYTHON" = "1" ] ; then
            autoconf
            touch Include/Python-ast.h
            touch Include/Python-ast.c
        fi

        CC=$CC32 CXX=$CXX32 ./configure $PYCCFG --host=$HOST --prefix=$install_dir --with-suffix=$SUFFIX || error_msg "Can't configure Python"
        doMake "Can't compile Python" "all done"
        if [ "$OSTYPE" = "msys" ] ; then
            pushd pywin32-216
            # TODO :: Fix this, builds ok but then tries to copy pywintypes27.lib instead of libpywintypes27.a and pywintypes27.dll.
            ../python$EXE_EXT setup.py build
            popd
        fi
        make install

        if [ "$OSTYPE" = "msys" ] ; then
            mkdir -p $PYCFGDIR
            cp Modules/makesetup $PYCFGDIR
            cp Modules/config.c.in $PYCFGDIR
            cp Modules/config.c $PYCFGDIR
            cp libpython$pyversion.a $PYCFGDIR
            cp Makefile $PYCFGDIR
            cp Modules/python.o $PYCFGDIR
            cp Modules/Setup.local $PYCFGDIR
            cp install-sh  $PYCFGDIR
            cp Modules/Setup $PYCFGDIR
            cp Modules/Setup.config $PYCFGDIR
            mkdir $install_dir/lib/python$pyversion
            cp libpython$pyversion.a $install_dir/lib/python$pyversion/
            cp libpython$pyversion.dll $install_dir/lib/python$pyversion/
        fi

        if [ "$OSTYPE_MAJOR" = "darwin" ] ; then
            doSed $"s/python2\.7Mac/python2\.7/g" $install_dir/bin/2to3
            doSed $"s/python2\.7Mac/python2\.7/g" $install_dir/bin/idle
            doSed $"s/python2\.7Mac/python2\.7/g" $install_dir/bin/pydoc
            doSed $"s/python2\.7Mac/python2\.7/g" $install_dir/bin/python-config
            doSed $"s/python2\.7Mac/python2\.7/g" $install_dir/bin/python2.7-config
            doSed $"s/python2\.7Mac/python2\.7/g" $install_dir/bin/smtpd.py
        fi

        popd
    fi

    pushd Python-$pyfullversion
    mkdir -p $target_dir/python/lib
    cp LICENSE $target_dir/PYTHON-LICENSE
    cp libpython$pyversion$SHLIB_EXT $target_dir/
    popd
    export PATH=$OLDPATH
    cp -a $install_dir/lib/python$pyversion $target_dir/python/lib/
    mkdir -p $target_dir/python/include/python$pyversion
    mkdir -p $target_dir/python/bin
    cp $install_dir/include/python$pyversion/pyconfig.h $target_dir/python/include/python$pyversion/
    # Remove the $SUFFIX if present (OS X)
    if [ "$OSTYPE_MAJOR" = "darwin" ]; then
        mv $install_dir/bin/python$pyversion$SUFFIX $install_dir/bin/python$pyversion
        mv $install_dir/bin/python$SUFFIX $install_dir/bin/python
    fi
    cp -a $install_dir/bin/python$pyversion* $target_dir/python/bin/
    if [ "$OSTYPE" = "msys" ] ; then
        cp -fr $install_dir/bin/Lib $target_dir/
        cp -f $install_dir/bin/libpython$pyversion.dll $target_dir/python/bin/
    fi
    $STRIP $target_dir/python/bin/python$pyversion$EXE_EXT

    # Something is setting PYTHONHOME as an Env. Var for Windows and I'm not sure what... installer? NQTC? Python build process?
    # TODOMA :: Fix the real problem.
    unset PYTHONHOME
    unset PYTHONPATH

    if [ ! -d gdb-src ]
    then
        git clone git://gitorious.org/toolchain-mingw-android/mingw-android-toolchain-gdb.git gdb-src || error_msg "Can't clone gdb"
    fi
    pushd gdb-src
    git checkout $GDB_BRANCH
#    git reset --hard
    popd

    if [ ! -d gdb-src/build-$GDB_PKG_NAME ]
    then
        mkdir -p gdb-src/build-$GDB_PKG_NAME
        pushd gdb-src/build-$GDB_PKG_NAME
        OLDPATH=$PATH
        export PATH=$install_dir/bin/:$PATH
        if [ -z $GDB_TARG_HOST_TAG ] ; then
            CC=$CC32 CXX=$CXX32 CFLAGS="-O0 -g" $GDB_ROOT_PATH/configure --enable-initfini-array --enable-gdbserver=no --enable-tui=yes --with-sysroot=$TEMP_PATH/android-ndk/platforms/android-9/arch-arm --with-python=$install_dir --with-expat=yes --with-libexpat-prefix=$install_dir --prefix=$target_dir --target=arm-elf-linux --host=$HOST --build=$HOST --disable-nls
        else
            CC=$CC32 CXX=$CXX32 $GDB_ROOT_PATH/configure --enable-initfini-array --enable-gdbserver=no --enable-tui=yes --with-python=$install_dir --with-expat=yes --with-libexpat-prefix=$install_dir --prefix=$target_dir --target=$HOST --host=$HOST --build=$HOST --disable-nls
        fi
        doMake "Can't compile android gdb $GDB_VER" "all done"
        cp -a gdb/gdb$EXE_EXT $target_dir/
#        cp -a gdb/gdbtui$EXE_EXT $target_dir/
        $STRIP $target_dir/gdb$EXE_EXT # .. Just while I fix native host GDB (can't debug the installer exe) and thumb-2 issues.
#        $STRIP $target_dir/gdbtui$EXE_EXT # .. Just while I fix native host GDB (can't debug the installer exe) and thumb-2 issues.
        export PATH=$OLDPATH
        popd
    fi

    CC=$OLDCC
    CXX=$OLDCXX
    CFLAGS=$OLDCFLAGS

    pushd $target_dir
    find . -name *.py[co] | xargs rm -f
    find . -name test | xargs rm -fr
    find . -name tests | xargs rm -fr
    popd

    createArchive $GDB_FLDR_NAME $GDB_PKG_NAME.7z
    mkdir -p $package_path

    mv $GDB_PKG_NAME.7z $package_path/

    popd #gdb-build
}

function prepareGDBServer
{
    package_name_ver=${GDB_VER//./_} # replace - with _
    package_path=$REPO_PATH_PACKAGES/org.kde.necessitas.misc.ndk.gdb_$package_name_ver/data

    if [ -f $package_path/gdbserver-$GDB_VER.7z ]
    then
        return
    fi

    export NDK_DIR=$TEMP_PATH/android-ndk

    mkdir gdb-build
    pushd gdb-build

    if [ ! -d gdb-src ]
    then
        git clone git://gitorious.org/toolchain-mingw-android/mingw-android-toolchain-gdb.git gdb-src || error_msg "Can't clone gdb"
        pushd gdb-src
        git checkout $GDB_BRANCH
        popd
    fi

    mkdir -p gdb-src/build-gdbserver-$GDB_VER
    pushd gdb-src/build-gdbserver-$GDB_VER

    mkdir android-sysroot
    $CPRL $TEMP_PATH/android-ndk/platforms/android-9/arch-arm/* android-sysroot/ || error_msg "Can't copy android sysroot"
    rm -f android-sysroot/usr/lib/libthread_db*
    rm -f android-sysroot/usr/include/thread_db.h

    TOOLCHAIN_PREFIX=$TEMP_PATH/android-ndk/toolchains/arm-linux-androideabi-4.4.3/prebuilt/$HOST_TAG_NDK/bin/arm-linux-androideabi

    OLD_CC="$CC"
    OLD_CFLAGS="$CFLAGS"
    OLD_LDFLAGS="$LDFLAGS"

    export CC="$TOOLCHAIN_PREFIX-gcc --sysroot=$PWD/android-sysroot"
    if [ "$MAKE_DEBUG_GDBSERVER" = "1" ] ; then
        export CFLAGS="-O0 -g -nostdlib -D__ANDROID__ -DANDROID -DSTDC_HEADERS -I$TEMP_PATH/android-ndk/toolchains/arm-linux-androideabi-4.4.3/prebuilt/linux-x86/lib/gcc/arm-linux-androideabi/4.4.3/include -I$PWD/android-sysroot/usr/include -fno-short-enums"
        export LDFLAGS="-static -Wl,-z,nocopyreloc -Wl,--no-undefined $PWD/android-sysroot/usr/lib/crtbegin_static.o -lc -lm -lgcc -lc $PWD/android-sysroot/usr/lib/crtend_android.o"
    else
        export CFLAGS="-O2 -nostdlib -D__ANDROID__ -DANDROID -DSTDC_HEADERS -I$TEMP_PATH/android-ndk/toolchains/arm-linux-androideabi-4.4.3/prebuilt/linux-x86/lib/gcc/arm-linux-androideabi/4.4.3/include -I$PWD/android-sysroot/usr/include -fno-short-enums"
        export LDFLAGS="-static -Wl,-z,nocopyreloc -Wl,--no-undefined $PWD/android-sysroot/usr/lib/crtbegin_static.o -lc -lm -lgcc -lc $PWD/android-sysroot/usr/lib/crtend_android.o"
    fi

    LIBTHREAD_DB_DIR=$TEMP_PATH/android-ndk/sources/android/libthread_db/gdb-7.1.x
    cp $LIBTHREAD_DB_DIR/thread_db.h android-sysroot/usr/include/
    $TOOLCHAIN_PREFIX-gcc$EXE_EXT --sysroot=$PWD/android-sysroot -o $PWD/android-sysroot/usr/lib/libthread_db.a -c $LIBTHREAD_DB_DIR/libthread_db.c || error_msg "Can't compile android threaddb"
    $GDB_ROOT_PATH/gdb/gdbserver/configure --host=arm-eabi-linux --with-libthread-db=$PWD/android-sysroot/usr/lib/libthread_db.a || error_msg "Can't configure gdbserver"
    doMake "Can't compile gdbserver" "all done"

    export CC="$OLD_CC"
    export CFLAGS="$OLD_CFLAGS"
    export LDFLAGS="$OLD_LDFLAGS"

    mkdir gdbserver-$GDB_VER
    if [ "$MAKE_DEBUG_GDBSERVER" = "0" ] ; then
        $TOOLCHAIN_PREFIX-objcopy --strip-unneeded gdbserver $PWD/gdbserver-$GDB_VER/gdbserver
    else
        cp gdbserver $PWD/gdbserver-$GDB_VER/gdbserver
    fi

    createArchive gdbserver-$GDB_VER gdbserver-$GDB_VER.7z
    mkdir -p $package_path
    mv gdbserver-$GDB_VER.7z $package_path/

    popd #gdb-src/build-gdbserver-$GDB_VER

    popd #gdb-build
}

function prepareGDBVersion
{
    GDB_VER=$1
    GDB_TARG_HOST_TAG=$2 # windows, linux-x86, darwin-x86 or nothing for android.
    if [ "$GDB_VER" = "7.3" ]; then
        GDB_ROOT_PATH=..
        GDB_BRANCH=integration_7_3
    else
        if [ "$GDB_VER" = "head" ]; then
            GDB_ROOT_PATH=..
            GDB_BRANCH=fsf_head
        else
           GDB_ROOT_PATH=../gdb
           GDB_BRANCH=master
        fi
    fi
    prepareGDB
    if [ -z $GDB_TARG_HOST_TAG ] ; then
        prepareGDBServer
    fi
}

function repackSDK
{
    package_name=${4//-/_} # replace - with _
    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.misc.sdk.$package_name/data/$2.7z ]
    then
        downloadIfNotExists $1.zip http://dl.google.com/android/repository/$1.zip
        rm -fr temp_repack
        mkdir temp_repack
        pushd temp_repack
        unzip ../$1.zip
        mv * temp_name
        mkdir -p $3
        mv temp_name $3/$4
        createArchive $3 $2.7z
        mkdir -p $REPO_PATH_PACKAGES/org.kde.necessitas.misc.sdk.$package_name/data
        mv $2.7z $REPO_PATH_PACKAGES/org.kde.necessitas.misc.sdk.$package_name/data/$2.7z
        popd
        rm -fr temp_repack
    fi
}

function repackSDKPlatform-tools
{
    package_name=${4//-/_} # replace - with _
    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.misc.sdk.$package_name/data/$2.7z ]
    then
        downloadIfNotExists $1.zip http://dl.google.com/android/repository/$1.zip
        rm -fr android-sdk
        unzip $1.zip
        mkdir -p $3
        mv $4 $3/$4
        createArchive $3 $2.7z
        mkdir -p $REPO_PATH_PACKAGES/org.kde.necessitas.misc.sdk.$package_name/data
        mv $2.7z $REPO_PATH_PACKAGES/org.kde.necessitas.misc.sdk.$package_name/data/$2.7z
        rm -fr $3
    fi
}

function repackSDKtools
{
    package_name=${5//-/_} # replace - with _
    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.misc.sdk.$package_name/data/$2.7z ]
    then
        downloadIfNotExists $1.zip http://dl.google.com/android/repository/$1.zip
        rm -fr android-sdk
        unzip $1.zip
        mkdir -p $3
        mv $4 $3/$4
        createArchive $3 $2.7z
        mkdir -p $REPO_PATH_PACKAGES/org.kde.necessitas.misc.sdk.$package_name/data
        mv $2.7z $REPO_PATH_PACKAGES/org.kde.necessitas.misc.sdk.$package_name/data/$2.7z
        rm -fr $3
    fi
}


function prepareSDKs
{
    echo "prepare SDKs"
    repackSDKtools tools_${ANDROID_SDK_VERSION}-linux android-sdk-linux android-sdk tools base
    repackSDKtools tools_${ANDROID_SDK_VERSION}-macosx android-sdk-macosx android-sdk tools base
    repackSDKtools tools_${ANDROID_SDK_VERSION}-windows android-sdk-windows android-sdk tools base

    if [ "$OSTYPE" = "msys" ]
    then
        if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.misc.sdk.platform_tools/data/android-sdk-windows-tools-mingw-android.7z ]
        then
            git clone git://gitorious.org/mingw-android-various/mingw-android-various.git android-various || error_msg "Can't clone android-various"
            pushd android-various/android-sdk
            gcc -Wl,-subsystem,windows -Wno-write-strings android.cpp -static-libgcc -s -O2 -o android.exe
            popd
            mkdir -p android-sdk-windows/tools/
            cp android-various/android-sdk/android.exe android-sdk-windows/tools/
            createArchive android-sdk-windows android-sdk-windows-tools-mingw-android.7z
            mv android-sdk-windows-tools-mingw-android.7z $REPO_PATH_PACKAGES/org.kde.necessitas.misc.sdk.platform_tools/data/android-sdk-windows-tools-mingw-android.7z
            rm -rf android-various
        fi
    fi

    # repack platform-tools
    repackSDKPlatform-tools platform-tools_${ANDROID_PLATFORM_TOOLS_VERSION}-linux platform-tools_${ANDROID_PLATFORM_TOOLS_VERSION}-linux android-sdk platform-tools
    repackSDKPlatform-tools platform-tools_${ANDROID_PLATFORM_TOOLS_VERSION}-macosx platform-tools_${ANDROID_PLATFORM_TOOLS_VERSION}-macosx android-sdk platform-tools
    repackSDKPlatform-tools platform-tools_${ANDROID_PLATFORM_TOOLS_VERSION}-windows platform-tools_${ANDROID_PLATFORM_TOOLS_VERSION}-windows android-sdk platform-tools

    # repack api-4
    repackSDK android-${ANDROID_API_4_VERSION}-linux android-${ANDROID_API_4_VERSION}-linux android-sdk/platforms android-4
    repackSDK android-${ANDROID_API_4_VERSION}-macosx android-${ANDROID_API_4_VERSION}-macosx android-sdk/platforms android-4
    repackSDK android-${ANDROID_API_4_VERSION}-windows android-${ANDROID_API_4_VERSION}-windows android-sdk/platforms android-4

    # repack api-5
    repackSDK android-${ANDROID_API_5_VERSION}-linux android-${ANDROID_API_5_VERSION}-linux android-sdk/platforms android-5
    repackSDK android-${ANDROID_API_5_VERSION}-macosx android-${ANDROID_API_5_VERSION}-macosx android-sdk/platforms android-5
    repackSDK android-${ANDROID_API_5_VERSION}-windows android-${ANDROID_API_5_VERSION}-windows android-sdk/platforms android-5

    # repack api-6
    repackSDK android-${ANDROID_API_6_VERSION}-linux  android-${ANDROID_API_6_VERSION}-linux  android-sdk/platforms android-6
    repackSDK android-${ANDROID_API_6_VERSION}-macosx android-${ANDROID_API_6_VERSION}-macosx android-sdk/platforms android-6
    repackSDK android-${ANDROID_API_6_VERSION}-windows android-${ANDROID_API_6_VERSION}-windows android-sdk/platforms android-6

    # repack api-7
    repackSDK android-${ANDROID_API_7_VERSION}-linux android-${ANDROID_API_7_VERSION} android-sdk/platforms android-7

    # repack api-8
    repackSDK android-${ANDROID_API_8_VERSION}-linux android-${ANDROID_API_8_VERSION} android-sdk/platforms android-8

    # repack api-9
    repackSDK android-${ANDROID_API_9_VERSION}-linux android-${ANDROID_API_9_VERSION} android-sdk/platforms android-9

    # repack api-10
    repackSDK android-${ANDROID_API_10_VERSION}-linux android-${ANDROID_API_10_VERSION} android-sdk/platforms android-10

    # repack api-11
    repackSDK android-${ANDROID_API_11_VERSION}-linux android-${ANDROID_API_11_VERSION} android-sdk/platforms android-11

    # repack api-12
    repackSDK android-${ANDROID_API_12_VERSION}-linux android-${ANDROID_API_12_VERSION} android-sdk/platforms android-12

    # repack api-13
    repackSDK android-${ANDROID_API_13_VERSION}-linux android-${ANDROID_API_13_VERSION} android-sdk/platforms android-13

    # repack api-14
    repackSDK android-${ANDROID_API_14_VERSION} android-${ANDROID_API_14_VERSION} android-sdk/platforms android-14

    # repack api-15
    repackSDK android-${ANDROID_API_15_VERSION} android-${ANDROID_API_15_VERSION} android-sdk/platforms android-15

    # repack api-16
    repackSDK android-${ANDROID_API_16_VERSION} android-${ANDROID_API_16_VERSION} android-sdk/platforms android-16
}

function patchQtFiles
{
    echo "bin/qmake$EXE_EXT" >files_to_patch
    echo "bin/lrelease$EXE_EXT" >>files_to_patch
    echo "%%" >>files_to_patch
    find . -name *.pc >>files_to_patch
    find . -name *.la >>files_to_patch
    find . -name *.prl >>files_to_patch
    find . -name *.prf >>files_to_patch
    if [ "$OSTYPE" = "msys" ] ; then
        cp -a $SHARED_QT_PATH/bin/*.dll ../qt-src/
    fi
    echo files_to_patch > qpatch.cmdline
    echo /data/data/org.kde.necessitas.ministro/files/qt >> qpatch.cmdline
    echo $PWD >> qpatch.cmdline
    echo . >> qpatch.cmdline
#    $QPATCH_PATH @qpatch.cmdline
}

function packSource
{
    package_name=${1//-/.} # replace - with .
    rm -fr $TEMP_PATH/source_temp_path
    mkdir -p $TEMP_PATH/source_temp_path/Android/Qt/$NECESSITAS_QT_VERSION_SHORT
    mv $1/.git .
#    if [ $1 = "qt-src" ]
#    then
#        mv $1/src/3rdparty/webkit .
#        mv $1/tests .
#    fi

    if [ $1 = "qtwebkit-src" ]
    then
        mv $1/LayoutTests .
    fi
    echo cp -rf $1 $TEMP_PATH/source_temp_path/Android/Qt/$NECESSITAS_QT_VERSION_SHORT/
    cp -rf $1 $TEMP_PATH/source_temp_path/Android/Qt/$NECESSITAS_QT_VERSION_SHORT/
    pushd $TEMP_PATH/source_temp_path
    createArchive Android $1.7z $EXTERNAL_7Z_A_PARAMS_WIN
    mkdir -p $REPO_PATH_PACKAGES/org.kde.necessitas.android.$package_name/data
    mv $1.7z $REPO_PATH_PACKAGES/org.kde.necessitas.android.$package_name/data/$1.7z
    popd
    #mv $TEMP_PATH/source_temp_path/Android/Qt/$NECESSITAS_QT_VERSION_SHORT/$1 .
    mv .git $1/
#    if [ $1 = "qt-src" ]
#    then
#        mv webkit $1/src/3rdparty/
#        mv tests $1/
#    fi
    if [ $1 = "qtwebkit-src" ]
    then
        mv LayoutTests $1/
    fi
    rm -fr $TEMP_PATH/source_temp_path
}


function compileNecessitasQt #params $1 architecture, $2 package path, $3 NDK_TARGET, $4 android architecture
{
    package_name=${1//-/_} # replace - with _
    NDK_TARGET=$3
    ANDROID_ARCH=$1
    if [ ! -z $4 ] ; then
        ANDROID_ARCH=$4
    fi
    # NQT_INSTALL_DIR=/data/data/org.kde.necessitas.ministro/files/qt
    NQT_INSTALL_DIR=$PWD/install

    if [ "$OSTYPE" = "linux-gnu" ] ; then
        if [ ! -d android-sdk-linux/platform-tools ]
        then
            rm -fr android-sdk-linux
            $EXTERNAL_7Z $EXTERNAL_7Z_X_PARAMS $REPO_PATH_PACKAGES/org.kde.necessitas.misc.sdk.base/data/android-sdk-linux.7z
            $EXTERNAL_7Z $EXTERNAL_7Z_X_PARAMS $REPO_PATH_PACKAGES/org.kde.necessitas.misc.sdk.platform_tools/data/platform-tools_${ANDROID_PLATFORM_TOOLS_VERSION}-linux.7z
            $EXTERNAL_7Z $EXTERNAL_7Z_X_PARAMS $REPO_PATH_PACKAGES/org.kde.necessitas.misc.sdk.android_14/data/android-${ANDROID_API_14_VERSION}.7z
            $EXTERNAL_7Z $EXTERNAL_7Z_X_PARAMS $REPO_PATH_PACKAGES/org.kde.necessitas.misc.sdk.android_8/data/android-${ANDROID_API_8_VERSION}.7z
            $EXTERNAL_7Z $EXTERNAL_7Z_X_PARAMS $REPO_PATH_PACKAGES/org.kde.necessitas.misc.sdk.android_7/data/android-${ANDROID_API_7_VERSION}.7z
            $EXTERNAL_7Z $EXTERNAL_7Z_X_PARAMS $REPO_PATH_PACKAGES/org.kde.necessitas.misc.sdk.android_4/data/android-${ANDROID_API_4_VERSION}-linux.7z
        fi
        export ANDROID_SDK_TOOLS_PATH=$PWD/android-sdk/tools/
        export ANDROID_SDK_PLATFORM_TOOLS_PATH=$PWD/android-sdk/platform-tools/
    fi

    if [ ! -f all_done ]
    then
         pushd ../qt-src
         git checkout -f mkspecs
         popd
        ../qt-src/android/androidconfigbuild.sh -l $NDK_TARGET -c 1 -q 1 -n $TEMP_PATH/android-ndk -a $ANDROID_ARCH -k 0 -i $NQT_INSTALL_DIR || error_msg "Can't configure android-qt"
        echo "all done">all_done
    fi

    rm -fr install
    rm -fr Android
    unset INSTALL_ROOT
    make QtJar
    ../qt-src/android/androidconfigbuild.sh -l $NDK_TARGET -c 0 -q 0 -n $TEMP_PATH/android-ndk -a $ANDROID_ARCH -b 0 -k 1 -i $NQT_INSTALL_DIR || error_msg "Can't install android-qt"

    mkdir -p $2/$1
    cp -rf $NQT_INSTALL_DIR/bin $2/$1
    createArchive Android qt-tools-${HOST_TAG}.7z
    rm -fr $2/$1/bin
    mkdir -p $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.$package_name/data
    mv qt-tools-${HOST_TAG}.7z $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.$package_name/data/qt-tools-${HOST_TAG}.7z
    cp -rf $NQT_INSTALL_DIR/* $2/$1
    cp -rf ../qt-src/lib/*.xml $2/$1/lib/
    cp -rf jar $2/$1/
    rm -fr $2/$1/bin

    doSed $"s/= android-5/= android-${NDK_TARGET}/g" $2/$1/mkspecs/android-g++/qmake.conf
    doSed $"s/= android-5/= android-${NDK_TARGET}/g" $2/$1/mkspecs/default/qmake.conf
    doSed $"s/# QMAKE_STRIP/QMAKE_STRIP/g" $2/$1/mkspecs/android-g++/qmake.conf
    doSed $"s/# QMAKE_STRIP/QMAKE_STRIP/g" $2/$1/mkspecs/default/qmake.conf
    if [ $ANDROID_ARCH = "armeabi-v7a" ]
    then
        doSed $"s/= armeabi/= armeabi-v7a/g" $2/$1/mkspecs/android-g++/qmake.conf
        doSed $"s/= armeabi/= armeabi-v7a/g" $2/$1/mkspecs/default/qmake.conf
    else
        if [ $ANDROID_ARCH = "x86" ]
        then
            doSed $"s/= armeabi/= x86/g" $2/$1/mkspecs/android-g++/qmake.conf
            doSed $"s/= armeabi/= x86/g" $2/$1/mkspecs/default/qmake.conf
        fi
    fi

    createArchive Android qt-framework.7z
    mv qt-framework.7z $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.$package_name/data/qt-framework.7z
#    rm -fr ../install-$1
    mkdir -p ../install-$1
    cp -a install/* ../install-$1/
    cp -a jar ../install-$1/
    packforWindows $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.$package_name/data/ qt-framework
#    patchQtFiles
}

function compileNecessitasHostQtTools #params $1 architecture, $2 package path, $3 NDK_TARGET, $4 android architecture
{
    package_name=${1//-/_} # replace - with _
    NDK_TARGET=$3
    ANDROID_ARCH=$1
    if [ ! -z $4 ] ; then
        ANDROID_ARCH=$4
    fi

    if [ ! $(which qmake) ] ; then
        (pushd /tmp ; $EXTERNAL_7Z $EXTERNAL_7Z_X_PARAMS $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.armeabi/data/qt-tools-linux-x86.7z)
        export PATH=/tmp/Android/Qt/${NECESSITAS_QT_VERSION_SHORT}/armeabi/bin:$PATH
    fi
    if [ ! $(which qmake) ] ; then
        echo "No build qmake found?"
        exit 1
    fi

    # the install path should be the same with the one where the libs were built
    NQT_INSTALL_DIR=$TEMP_PATH/$CHECKOUT_BRANCH/Android/Qt/$NECESSITAS_QT_VERSION_SHORT/build-$1/install
    OLD_PATH=$PATH
    export PATH=$NQT_INSTALL_DIR/bin:$PATH
    if [ ! -f all_done ]
    then
         pushd ../qt-src
         git checkout -f mkspecs
         popd
        ../qt-src/configure -opensource -confirm-license -v -platform linux-mingw-w64-32-g++ -no-webkit -no-script -no-declarative -no-qt3support -no-xmlpatterns -no-phonon -no-svg -no-scripttools -nomake demos -no-multimedia -nomake examples -little-endian -host-little-endian -fast -cross-qmake qmake --prefix=$NQT_INSTALL_DIR --enable-BUILD_ON_MSYS || error_msg "Can't configure android-qt"
        echo "all done">all_done
    fi

    rm -fr install
    rm -fr Android

    export INSTALL_ROOT=$PWD/install
    make sub-qmake-install sub-tools-bootstrap sub-moc-install_subtargets sub-rcc-install_subtargets sub-uic-install_subtargets sub-tools-install_subtargets || error_msg "Can't install android-qt"

    mkdir -p $2/$1
    cp -rf $INSTALL_ROOT/$NQT_INSTALL_DIR/bin $2/$1
    createArchive Android qt-tools-${XHOST_TAG}.7z
    rm -fr $2/$1/bin

    mkdir -p $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.$package_name/data
    mv qt-tools-${XHOST_TAG}.7z $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.$package_name/data/qt-tools-${XHOST_TAG}.7z
    export PATH=$OLD_PATH
}

function prepareNecessitasQt
{
    mkdir -p Android/Qt/$NECESSITAS_QT_VERSION_SHORT
    pushd Android/Qt/$NECESSITAS_QT_VERSION_SHORT

    if [ ! -d qt-src ]
    then
        git clone git://anongit.kde.org/android-qt.git qt-src|| error_msg "Can't clone ${1}"
    fi

    cloneCheckoutKDEGitRepo android-qt $CHECKOUT_BRANCH

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.armeabi/data/qt-tools-${HOST_TAG}.7z ]
    then
        mkdir build-armeabi
        pushd build-armeabi
        compileNecessitasQt armeabi Android/Qt/$NECESSITAS_QT_VERSION_SHORT 5
        popd #build-armeabi
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.armeabi_v7a/data/qt-tools-${HOST_TAG}.7z ]
    then
        mkdir build-armeabi-v7a
        pushd build-armeabi-v7a
        compileNecessitasQt armeabi-v7a Android/Qt/$NECESSITAS_QT_VERSION_SHORT 5
        popd #build-armeabi-v7a
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.armeabi_android_4/data/qt-tools-${HOST_TAG}.7z ]
    then
        mkdir build-armeabi-android-4
        pushd build-armeabi-android-4
        compileNecessitasQt armeabi-android-4 Android/Qt/$NECESSITAS_QT_VERSION_SHORT 4 armeabi
        popd #build-armeabi_android_4
    fi

# Enable it when QtCreator is ready
#     if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.x86/data/qt-tools-${HOST_TAG}.7z ]
#     then
#         mkdir build-x86
#         pushd build-x86
#         compileNecessitasQt x86 Android/Qt/$NECESSITAS_QT_VERSION_SHORT 9
#         popd #build-x86
#     fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.src/data/qt-src.7z ]
    then
        packSource qt-src
    fi

    popd #Android/Qt/$NECESSITAS_QT_VERSION_SHORT
}

function prepareNecessitasQtTools
{
    XHOST_TAG=$1
    mkdir -p Android/Qt/$NECESSITAS_QT_VERSION_SHORT
    pushd Android/Qt/$NECESSITAS_QT_VERSION_SHORT

    if [ ! -d qt-src ]
    then
        git clone git://anongit.kde.org/android-qt.git qt-src|| error_msg "Can't clone ${1}"
    fi

    cloneCheckoutKDEGitRepo android-qt $CHECKOUT_BRANCH

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.armeabi/data/qt-tools-${XHOST_TAG}.7z ]
    then
        mkdir build-armeabi-${XHOST_TAG}
        pushd build-armeabi-${XHOST_TAG}
        compileNecessitasHostQtTools armeabi Android/Qt/$NECESSITAS_QT_VERSION_SHORT 5
        popd #build-armeabi-${XHOST_TAG}
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.armeabi_v7a/data/qt-tools-${XHOST_TAG}.7z ]
    then
        mkdir build-armeabi-v7a-${XHOST_TAG}
        pushd build-armeabi-v7a-${XHOST_TAG}
        compileNecessitasHostQtTools armeabi-v7a Android/Qt/$NECESSITAS_QT_VERSION_SHORT 5
        popd #build-armeabi-v7a-${XHOST_TAG}
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.armeabi_android_4/data/qt-tools-${XHOST_TAG}.7z ]
    then
        mkdir build-armeabi-android-4-${XHOST_TAG}
        pushd build-armeabi-android-4-${XHOST_TAG}
        compileNecessitasHostQtTools armeabi-android-4 Android/Qt/$NECESSITAS_QT_VERSION_SHORT 4 armeabi
        popd #build-armeabi_android_4-${XHOST_TAG}
    fi
    popd
}

function compileNecessitasQtMobility
{
    if [ ! -f all_done ]
    then
        pushd ../qtmobility-src
        git checkout $CHECKOUT_BRANCH
        git pull
        popd
        ../qtmobility-src/configure -prefix $PWD/install -staticconfig android -qmake-exec $TEMP_PATH/$CHECKOUT_BRANCH/Android/Qt/$NECESSITAS_QT_VERSION_SHORT/build-$1/install/bin/qmake$EXE_EXT -modules "bearer location contacts versit messaging systeminfo serviceframework sensors gallery organizer feedback connectivity" || error_msg "Can't configure android-qtmobility"
        doMake "Can't compile android-qtmobility" "all done" ma-make
    fi
    package_name=${1//-/_} # replace - with _
    rm -fr data
    rm -fr $2
    unset INSTALL_ROOT
    make install
    mkdir -p $2/$1
    mkdir -p $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtmobility.$package_name/data
    mv $PWD/install/* $2/$1
    createArchive Android qtmobility.7z
    mv qtmobility.7z $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtmobility.$package_name/data/qtmobility.7z
    cp -a $2/$1/* ../install-$1 # copy files to ministro repository
    packforWindows $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtmobility.$package_name/data/ qtmobility
#    pushd ../build-$1
#    patchQtFiles
#    popd
}

function prepareNecessitasQtMobility
{
    mkdir -p Android/Qt/$NECESSITAS_QT_VERSION_SHORT
    pushd Android/Qt/$NECESSITAS_QT_VERSION_SHORT
    if [ ! -d qtmobility-src ]
    then
        git clone git://anongit.kde.org/android-qt-mobility.git qtmobility-src || error_msg "Can't clone android-qt-mobility"
        pushd qtmobility-src
        git checkout $CHECKOUT_BRANCH
        git pull
        popd
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtmobility.armeabi/data/qtmobility.7z ]
    then
        mkdir build-mobility-armeabi
        pushd build-mobility-armeabi
        compileNecessitasQtMobility armeabi Android/Qt/$NECESSITAS_QT_VERSION_SHORT
        popd #build-mobility-armeabi
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtmobility.armeabi_v7a/data/qtmobility.7z ]
    then
        mkdir build-mobility-armeabi-v7a
        pushd build-mobility-armeabi-v7a
        compileNecessitasQtMobility armeabi-v7a Android/Qt/$NECESSITAS_QT_VERSION_SHORT
        popd #build-mobility-armeabi-v7a
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtmobility.armeabi_android_4/data/qtmobility.7z ]
    then
        mkdir build-mobility-armeabi-android-4
        pushd build-mobility-armeabi-android-4
        compileNecessitasQtMobility armeabi-android-4 Android/Qt/$NECESSITAS_QT_VERSION_SHORT
        popd #build-mobility-armeabi-android-4
    fi

#     if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtmobility.x86/data/qtmobility.7z ]
#     then
#         mkdir build-mobility-x86
#         pushd build-mobility-x86
#         compileNecessitasQtMobility x86 Android/Qt/$NECESSITAS_QT_VERSION_SHORT
#         popd #build-mobility-x86
#     fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtmobility.src/data/qtmobility-src.7z ]
    then
        packSource qtmobility-src
    fi
    popd #Android/Qt/$NECESSITAS_QT_VERSION_SHORT
}

function compileNecessitasQtWebkit
{
    export SQLITE3SRCDIR=$TEMP_PATH/$CHECKOUT_BRANCH/Android/Qt/$NECESSITAS_QT_VERSION_SHORT/qt-src/src/3rdparty/sqlite
    if [ ! -f all_done ]
    then
        if [ "$OSTYPE_MAJOR" = "msys" ] ; then
            which gperf && GPERF=1
            if [ ! "$GPERF" = "1" ] ; then
                downloadIfNotExists gperf-3.0.4.tar.gz http://ftp.gnu.org/pub/gnu/gperf/gperf-3.0.4.tar.gz
                rm -rf gperf-3.0.4
                tar -xzvf gperf-3.0.4.tar.gz
                pushd gperf-3.0.4
                CFLAGS=-O2 LDFLAGS="-enable-auto-import" && ./configure --enable-static --disable-shared --prefix=/usr CFLAGS=-O2 LDFLAGS="-enable-auto-import"
                make && make install
                popd
            fi
            downloadIfNotExists strawberry-perl-5.12.2.0.msi http://strawberryperl.com/download/5.12.2.0/strawberry-perl-5.12.2.0.msi
            if [ ! -f /${SYSTEMDRIVE:0:1}/strawberry/perl/bin/perl.exe ]; then
                msiexec //i strawberry-perl-5.12.2.0.msi //q
            fi
            if [ "`which perl`" != "/${SYSTEMDRIVE:0:1}/strawberry/perl/bin/perl.exe" ]; then
                export PATH=/${SYSTEMDRIVE:0:1}/strawberry/perl/bin:$PATH
            fi
            if [ "`which perl`" != "/${SYSTEMDRIVE:0:1}/strawberry/perl/bin/perl.exe" ]; then
                error_msg "Not using the correct perl"
            fi
        fi
        export WEBKITOUTPUTDIR=$PWD
        echo "doing perl"
        ../qtwebkit-src/Tools/Scripts/build-webkit --qt --makeargs="-j$JOBS" --qmake=$TEMP_PATH/$CHECKOUT_BRANCH/Android/Qt/$NECESSITAS_QT_VERSION_SHORT/build-$1/install/bin/qmake$EXE_EXT --no-video --no-xslt || error_msg "Can't configure android-qtwebkit"
        echo "all done">all_done
    fi
    package_name=${1//-/_} # replace - with _
    rm -fr $PWD/$TEMP_PATH
    pushd Release
    export INSTALL_ROOT=$PWD/../
    make install
    popd
    rm -fr $2
    mkdir -p $2/$1
    mkdir -p $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtwebkit.$package_name/data
    mv $PWD/$TEMP_PATH/$CHECKOUT_BRANCH/Android/Qt/$NECESSITAS_QT_VERSION_SHORT/build-$1/install/* $2/$1
    pushd $2/$1
    qt_build_path=$TEMP_PATH/$CHECKOUT_BRANCH/Android/Qt/$NECESSITAS_QT_VERSION_SHORT/build-$1/install
    qt_build_path=${qt_build_path//\//\\\/}
    sed_cmd="s/$qt_build_path/\/data\/data\/org.kde.necessitas.ministro\/files\/qt/g"
    if [ "$OSTYPE_MAJOR" = "darwin" ]; then
        find . -name *.pc | xargs sed -i '.bak' $sed_cmd
        find . -name *.pc.bak | xargs rm -f
    else
        find . -name *.pc | xargs sed $sed_cmd -i
    fi
    popd
    rm -fr $PWD/$TEMP_PATH
    createArchive Android qtwebkit.7z
    mv qtwebkit.7z $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtwebkit.$package_name/data/qtwebkit.7z
    cp -a $2/$1/* ../install-$1/
    packforWindows $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtwebkit.$package_name/data/ qtwebkit
#    pushd ../build-$1
#    patchQtFiles
#    popd
}

function prepareNecessitasQtWebkit
{
    mkdir -p Android/Qt/$NECESSITAS_QT_VERSION_SHORT
    pushd Android/Qt/$NECESSITAS_QT_VERSION_SHORT
    if [ ! -d qtwebkit-src ]
    then
        git clone git://gitorious.org/~taipan/webkit/android-qtwebkit.git qtwebkit-src || error_msg "Can't clone android-qtwebkit"
        pushd qtwebkit-src
        git checkout $CHECKOUT_BRANCH
        git pull
        popd
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtwebkit.armeabi/data/qtwebkit.7z ]
    then
        mkdir build-webkit-armeabi
        pushd build-webkit-armeabi
        compileNecessitasQtWebkit armeabi Android/Qt/$NECESSITAS_QT_VERSION_SHORT
        popd #build-webkit-armeabi
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtwebkit.armeabi_v7a/data/qtwebkit.7z ]
    then
        mkdir build-webkit-armeabi-v7a
        pushd build-webkit-armeabi-v7a
        compileNecessitasQtWebkit armeabi-v7a Android/Qt/$NECESSITAS_QT_VERSION_SHORT
        popd #build-webkit-armeabi-v7a
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtwebkit.armeabi_android_4/data/qtwebkit.7z ]
    then
        mkdir build-webkit-armeabi-android-4
        pushd build-webkit-armeabi-android-4
        compileNecessitasQtWebkit armeabi-android-4 Android/Qt/$NECESSITAS_QT_VERSION_SHORT
        popd #build-webkit-armeabi-android-4
    fi

#     if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtwebkit.x86/data/qtwebkit.7z ]
#     then
#         mkdir build-webkit-x86
#         pushd build-webkit-x86
#         compileNecessitasQtWebkit x86 Android/Qt/$NECESSITAS_QT_VERSION_SHORT
#         popd #build-webkit-x86
#     fi
#
    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtwebkit.src/data/qtwebkit-src.7z ]
    then
        packSource qtwebkit-src
    fi
    popd #Android/Qt/$NECESSITAS_QT_VERSION_SHORT
}

function prepareOpenJDK
{
    mkdir openjdk
    pushd openjdk

    mkdir -p $REPO_PATH_PACKAGES/org.kde.necessitas.misc.openjdk/data
    WINE=0
    which wine && WINE=1
    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.misc.openjdk/data/openjdk-windows.7z ] ; then
        if [ "$OSTYPE_MAJOR" = "msys" -o "$WINE" = "1" ] ; then
            downloadIfNotExists oscg-openjdk6b21-1-windows-installer.exe http://oscg-downloads.s3.amazonaws.com/installers/oscg-openjdk6b21-1-windows-installer.exe
            rm -rf openjdk6b21-windows
            wine oscg-openjdk6b21-1-windows-installer.exe --unattendedmodeui none --mode unattended --prefix `pwd`/openjdk6b21-windows
            pushd openjdk6b21-windows
            createArchive openjdk-6.0.21 openjdk-windows.7z
            mv openjdk-windows.7z $REPO_PATH_PACKAGES/org.kde.necessitas.misc.openjdk/data/
            popd
        fi
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.misc.openjdk/data/openjdk-linux-x86.7z ] ; then
        downloadIfNotExists openjdk-1.6.0-b21.i386.openscg.deb http://oscg-downloads.s3.amazonaws.com/packages/openjdk-1.6.0-b21.i386.openscg.deb
        ar x openjdk-1.6.0-b21.i386.openscg.deb
        tar xzf data.tar.gz
        pushd opt
        createArchive openjdk openjdk-linux-x86.7z
        mv openjdk-linux-x86.7z $REPO_PATH_PACKAGES/org.kde.necessitas.misc.openjdk/data/
        popd
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.misc.openjdk/data/openjdk-darwin-x86.7z ] ; then
        downloadIfNotExists oscg-openjdk6b16-5a-osx-installer.zip http://oscg-downloads.s3.amazonaws.com/installers/oscg-openjdk6b16-5a-osx-installer.zip
        unzip -o oscg-openjdk6b16-5a-osx-installer.zip
        createArchive oscg-openjdk6b16-5a-osx-installer.app openjdk-darwin-x86.7z
        mv openjdk-darwin-x86.7z $REPO_PATH_PACKAGES/org.kde.necessitas.misc.openjdk/data/
    fi

    popd
}

function prepareAnt
{
    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ant/data/ant.7z ] ; then
        mkdir -p ant
        pushd ant
        mkdir -p $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ant/data
        downloadIfNotExists apache-ant-1.8.4-bin.tar.bz2 http://mirror.ox.ac.uk/sites/rsync.apache.org//ant/binaries/apache-ant-1.8.4-bin.tar.bz2
        tar xjvf apache-ant-1.8.4-bin.tar.bz2
        createArchive apache-ant-1.8.4 ant.7z
        mv ant.7z $REPO_PATH_PACKAGES/org.kde.necessitas.misc.ant/data/
        popd
    fi
}

function patchPackages
{
    pushd $REPO_PATH_PACKAGES
    for files_name in "*.qs" "*.xml"
    do
        for file_name in `find . -name $files_name`
        do
            # Can't use / as a delimiter for paths.
            doSed $"s#$1#$2#g" $file_name
        done
    done
    popd
}

function patchPackage
{
    if [ -d $REPO_PATH_PACKAGES/$3 ] ; then
        pushd $REPO_PATH_PACKAGES/$3
        for files_name in "*.qs" "*.xml"
        do
            for file_name in `find . -name $files_name`
            do
                doSed $"s#$1#$2#g" $file_name
            done
        done
        popd
    else
        echo "patchPackage : Warning, failed to find directory $REPO_PATH_PACKAGES/$3"
    fi
}

function setPackagesVariables
{
    patchPackages "@@TODAY@@" $TODAY

    patchPackages "@@NECESSITAS_QT_VERSION@@" $NECESSITAS_QT_VERSION
    patchPackages "@@NECESSITAS_QT_VERSION_SHORT@@" $NECESSITAS_QT_VERSION_SHORT
    patchPackages "@@NECESSITAS_QT_PACKAGE_VERSION@@" $NECESSITAS_QT_PACKAGE_VERSION

    patchPackages "@@NECESSITAS_QTWEBKIT_VERSION@@" $NECESSITAS_QTWEBKIT_VERSION
    patchPackages "@@NECESSITAS_QTMOBILITY_VERSION@@" $NECESSITAS_QTMOBILITY_VERSION
    patchPackages "@@REPOSITORY@@" $CHECKOUT_BRANCH
    patchPackages "@@TEMP_PATH@@" $TEMP_PATH

    patchPackage "@@NECESSITAS_QT_CREATOR_VERSION@@" $NECESSITAS_QT_CREATOR_VERSION "org.kde.necessitas.tools.qtcreator"

    patchPackage "@@ANDROID_NDK_VERSION@@" $ANDROID_NDK_VERSION "org.kde.necessitas.misc.ndk.${ANDROID_NDK_VERSION}"
    patchPackage "@@ANDROID_NDK_VERSION@@" $ANDROID_NDK_VERSION "org.kde.necessitas.misc.ndk.${ANDROID_NDK_VERSION}"
    patchPackage "@@ANDROID_NDK_VERSION@@" $ANDROID_NDK_VERSION "org.kde.necessitas.misc.ndk.ma"
    patchPackage "@@ANDROID_NDK_VERSION@@" $ANDROID_NDK_VERSION "org.kde.necessitas.misc.ndk.ma"

    patchPackage "@@ANDROID_API_4_VERSION@@" $ANDROID_API_4_VERSION "org.kde.necessitas.misc.sdk.android_4"
    patchPackage "@@ANDROID_API_5_VERSION@@" $ANDROID_API_5_VERSION "org.kde.necessitas.misc.sdk.android_5"
    patchPackage "@@ANDROID_API_6_VERSION@@" $ANDROID_API_6_VERSION "org.kde.necessitas.misc.sdk.android_6"
    patchPackage "@@ANDROID_API_7_VERSION@@" $ANDROID_API_7_VERSION "org.kde.necessitas.misc.sdk.android_7"
    patchPackage "@@ANDROID_API_8_VERSION@@" $ANDROID_API_8_VERSION "org.kde.necessitas.misc.sdk.android_8"
    patchPackage "@@ANDROID_API_9_VERSION@@" $ANDROID_API_9_VERSION "org.kde.necessitas.misc.sdk.android_9"
    patchPackage "@@ANDROID_API_10_VERSION@@" $ANDROID_API_10_VERSION "org.kde.necessitas.misc.sdk.android_10"
    patchPackage "@@ANDROID_API_11_VERSION@@" $ANDROID_API_11_VERSION "org.kde.necessitas.misc.sdk.android_11"
    patchPackage "@@ANDROID_API_12_VERSION@@" $ANDROID_API_12_VERSION "org.kde.necessitas.misc.sdk.android_12"
    patchPackage "@@ANDROID_API_13_VERSION@@" $ANDROID_API_13_VERSION "org.kde.necessitas.misc.sdk.android_13"
    patchPackage "@@ANDROID_API_14_VERSION@@" $ANDROID_API_14_VERSION "org.kde.necessitas.misc.sdk.android_14"
    patchPackage "@@ANDROID_API_15_VERSION@@" $ANDROID_API_15_VERSION "org.kde.necessitas.misc.sdk.android_15"
    patchPackage "@@ANDROID_API_16_VERSION@@" $ANDROID_API_16_VERSION "org.kde.necessitas.misc.sdk.android_16"
    patchPackage "@@ANDROID_PLATFORM_TOOLS_VERSION@@" $ANDROID_PLATFORM_TOOLS_VERSION "org.kde.necessitas.misc.sdk.platform_tools"
    patchPackage "@@ANDROID_SDK_VERSION@@" $ANDROID_SDK_VERSION "org.kde.necessitas.misc.sdk.base"

    patchPackage "@@NECESSITAS_QTMOBILITY_ARMEABI_INSTALL_PATH@@" "$TEMP_PATH/$CHECKOUT_BRANCH/Android/Qt/$NECESSITAS_QT_VERSION_SHORT/build-mobility-armeabi/install"
    patchPackage "@@NECESSITAS_QTMOBILITY_ARMEABI_ANDROID_4_INSTALL_PATH@@" "$TEMP_PATH/$CHECKOUT_BRANCH/Android/Qt/$NECESSITAS_QT_VERSION_SHORT/build-mobility-armeabi-android-4/install"
    patchPackage "@@NECESSITAS_QTMOBILITY_ARMEABI-V7A_INSTALL_PATH@@" "$TEMP_PATH/$CHECKOUT_BRANCH/Android/Qt/$NECESSITAS_QT_VERSION_SHORT/build-mobility-armeabi-v7a/install"
    patchPackage "@@NECESSITAS_QTWEBKIT_ARMEABI_INSTALL_PATH@@" "/data/data/org.kde.necessitas.ministro/files/qt"
    patchPackage "@@NECESSITAS_QTWEBKIT_ARMEABI_ANDROID_4_INSTALL_PATH@@" "/data/data/org.kde.necessitas.ministro/files/qt"
    patchPackage "@@NECESSITAS_QTWEBKIT_ARMEABI-V7A_INSTALL_PATH@@" "/data/data/org.kde.necessitas.ministro/files/qt"

}

function prepareSDKBinary
{
    $SDK_TOOLS_PATH/binarycreator -v -t $SDK_TOOLS_PATH/installerbase$HOST_EXE_EXT -c $REPO_SRC_PATH/config -p $REPO_PATH_PACKAGES -n $REPO_SRC_PATH/necessitas-sdk-installer$HOST_QT_CONFIG$HOST_EXE_EXT org.kde.necessitas
    # Work around mac bug. qt_menu.nib doesn't get copied to the build, nor to the app.
    # https://bugreports.qt.nokia.com//browse/QTBUG-5952
    if [ "$OSTYPE_MAJOR" = "darwin" ] ; then
        pushd $REPO_SRC_PATH
        $SHARED_QT_PATH/bin/macdeployqt necessitas-sdk-installer$HOST_QT_CONFIG.app
        popd
        cp -rf $QT_SRCDIR/src/gui/mac/qt_menu.nib $REPO_SRC_PATH/necessitas-sdk-installer$HOST_QT_CONFIG.app/Contents/Resources/
    fi
    mkdir sdkmaintenance
    pushd sdkmaintenance
    rm -fr *.7z
    if [ "$OSTYPE_MAJOR" = "msys" ] ; then
        mkdir temp
        cp -a $REPO_SRC_PATH/necessitas-sdk-installer$HOST_QT_CONFIG.exe temp/SDKMaintenanceToolBase.exe
        createArchive temp sdkmaintenance-windows.7z
    else
        if [ "$OSTYPE_MAJOR" = "darwin" ] ; then
            cp -a $REPO_SRC_PATH/necessitas-sdk-installer${HOST_QT_CONFIG}.app .tempSDKMaintenanceTool
        else
            cp -a $REPO_SRC_PATH/necessitas-sdk-installer$HOST_QT_CONFIG .tempSDKMaintenanceTool
        fi

        if [ "$OSTYPE_MAJOR" = "linux-gnu" ] ; then
                createArchive . sdkmaintenance-linux-x86.7z
        else
                createArchive . sdkmaintenance-darwin-x86.7z
        fi
    fi
    mkdir -p $REPO_PATH_PACKAGES/org.kde.necessitas.tools.sdkmaintenance/data/
    cp -f *.7z $REPO_PATH_PACKAGES/org.kde.necessitas.tools.sdkmaintenance/data/
    popd
}

function prepareSDKRepository
{
    rm -fr $REPO_PATH
    $SDK_TOOLS_PATH/repogen -v  -p $REPO_PATH_PACKAGES -c $REPO_SRC_PATH/config -u http://files.kde.org/necessitas/test $REPO_PATH
}

function prepareMinistroRepository
{
    rm -fr $MINISTRO_REPO_PATH
    pushd $REPO_SRC_PATH/ministrorepogen
    if [ ! -f all_done ]
    then
        $STATIC_QT_PATH/bin/qmake CONFIG+=static -r || error_msg "Can't configure ministrorepogen"
        doMake "Can't compile ministrorepogen" "all done" ma-make
        if [ "$OSTYPE" = "msys" ] ; then
            cp $REPO_SRC_PATH/ministrorepogen/release/ministrorepogen$EXE_EXT $REPO_SRC_PATH/ministrorepogen/ministrorepogen$EXE_EXT
        fi
    fi
    popd
    for platfromArchitecture in armeabi armeabi-v7a armeabi-android-4
    do
        pushd $TEMP_PATH/$CHECKOUT_BRANCH/Android/Qt/$NECESSITAS_QT_VERSION_SHORT/install-$platfromArchitecture || error_msg "Can't prepare ministro repo, Android Qt not built?"
        architecture=$platfromArchitecture;
        repoVersion=$MINISTRO_VERSION-$platfromArchitecture
        if [ $architecture = "armeabi-android-4" ] ; then
            architecture="armeabi"
        fi
        MINISTRO_OBJECTS_PATH=$MINISTRO_REPO_PATH/objects/$repoVersion
        rm -fr $MINISTRO_OBJECTS_PATH
        mkdir -p $MINISTRO_OBJECTS_PATH
        rm -fr Android
        for lib in `find . -name *.so`
        do
            libDirname=`dirname $lib`
            mkdir -p $MINISTRO_OBJECTS_PATH/$libDirname
            cp $lib $MINISTRO_OBJECTS_PATH/$libDirname/
            $ANDROID_STRIP_BINARY --strip-unneeded $MINISTRO_OBJECTS_PATH/$lib
        done

        for jar in `find . -name *.jar`
        do
            jarDirname=`dirname $jar`
            mkdir -p $MINISTRO_OBJECTS_PATH/$jarDirname
            cp $jar $MINISTRO_OBJECTS_PATH/$jarDirname/
        done

        for qmldirfile in `find . -name qmldir`
        do
            qmldirfileDirname=`dirname $qmldirfile`
            cp $qmldirfile $MINISTRO_OBJECTS_PATH/$qmldirfileDirname/
        done
        if [ "$OSTYPE_MAJOR" = "msys" ] ; then
            cp $REPO_SRC_PATH/ministrorepogen/release/ministrorepogen$EXE_EXT $REPO_SRC_PATH/ministrorepogen/ministrorepogen$EXE_EXT
        fi
        $REPO_SRC_PATH/ministrorepogen/ministrorepogen$EXE_EXT $ANDROID_READELF_BINARY $MINISTRO_OBJECTS_PATH $MINISTRO_VERSION $architecture $REPO_SRC_PATH/ministrorepogen/rules-$platfromArchitecture.xml $MINISTRO_REPO_PATH/$CHECKOUT_BRANCH $repoVersion $MINISTRO_QT_VERSION
        popd
    done
}

function packforWindows
{
    echo "packforWindows $1/$2"
    rm -fr $TEMP_PATH/packforWindows
    mkdir -p $TEMP_PATH/packforWindows
    pushd $TEMP_PATH/packforWindows
        $EXTERNAL_7Z $EXTERNAL_7Z_X_PARAMS $1/$2.7z
        mv Android Android_old
        $CPRL Android_old Android
        rm -fr Android_old
        find -name *.so.4* | xargs rm -fr
        find -name *.so.1* | xargs rm -fr
        createArchive Android $1/$2-windows.7z $EXTERNAL_7Z_A_PARAMS_WIN
    popd
    rm -fr $TEMP_PATH/packforWindows
}

function prepareWindowsPackages
{
    #  Qt framework
    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.armeabi/data/qt-framework-windows.7z ]
    then
        packforWindows $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.armeabi/data/ qt-framework
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.armeabi_v7a/data/qt-framework-windows.7z ]
    then
        packforWindows $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.armeabi_v7a/data/ qt-framework
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.src/data/qt-src-windows.7z ]
    then
        packforWindows $REPO_PATH_PACKAGES/org.kde.necessitas.android.qt.src/data/ qt-src
    fi


    #  Qt Mobility
    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtmobility.armeabi/data/qtmobility-windows.7z ]
    then
        packforWindows $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtmobility.armeabi/data/ qtmobility
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtmobility.armeabi_v7a/data/qtmobility-windows.7z ]
    then
        packforWindows $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtmobility.armeabi_v7a/data/ qtmobility
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtmobility.src/data/qtmobility-src-windows.7z ]
    then
        packforWindows $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtmobility.src/data/ qtmobility-src
    fi


    #  Qt WebKit
    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtwebkit.armeabi/data/qtwebkit-windows.7z ]
    then
        packforWindows $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtwebkit.armeabi/data/ qtwebkit
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtwebkit.armeabi_v7a/data/qtwebkit-windows.7z ]
    then
        packforWindows $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtwebkit.armeabi_v7a/data/ qtwebkit
    fi

    if [ ! -f $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtwebkit.src/data/qtwebkit-src-windows.7z ]
    then
        packforWindows $REPO_PATH_PACKAGES/org.kde.necessitas.android.qtwebkit.src/data/ qtwebkit-src
    fi

}

# Sorry for adding these checks BogDan, but I keep forgetting to run setup.sh
# and use linux32.
if [ "$OSTYPE_MAJOR" = "linux-gnu" ] ; then
   if [ ! -d /proc ] ; then
      echo "Refusing to continue as /proc is not mounted"
      echo "You may need to run $HOME/setup.sh in your chroot env"
      exit 1
   fi
   TEST_BUILD_ARCH=$(arch)
   case $TEST_BUILD_ARCH in
   i?86*)
      ;;
    *)
      echo "Refusing to continue as you are on a $TEST_BUILD_ARCH machine"
      echo "Various things (e.g. cross compilation) will fail."
      echo "Re-run with:"
      echo "linux32 $0 $@"
      exit 1
      ;;
   esac
fi

Set_HOST_OSTYPE $OSTYPE_MAJOR

if [ "$OSTYPE_MAJOR" = "msys" ] ; then
    makeInstallMinGWLibs
fi
prepareHostQt
prepareSdkInstallerTools
prepareNDKs
prepareSDKs
# prepareOpenJDK
prepareAnt
prepareNecessitasQtCreator
# prepareGDBVersion head $HOST_TAG
# prepareGDBVersion 7.3
# prepareGDBVersion head
mkdir $CHECKOUT_BRANCH
pushd $CHECKOUT_BRANCH
prepareNecessitasQt
prepareNecessitasQtTools windows

#prepareNecessitasQtTools macosx

# TODO :: Fix webkit build in Windows (-no-video fails) and Mac OS X (debug-and-release config incorrectly used and fails)
# git clone often fails for webkit
# Webkit is broken currently.
# prepareNecessitasQtWebkit

prepareNecessitasQtMobility
popd

prepareSDKBinary

if [ "$OSTYPE_MAJOR" = "linux-gnu" ] ; then
# TODO :: Get darwin cross working.
#    for CROSS_HOST in msys darwin ; do
    for CROSS_HOST in msys ; do
        Set_HOST_OSTYPE $CROSS_HOST
        if [ "$HOST_OSTYPE_MAJOR" = "msys" ] ; then
            makeInstallMinGWLibs
        fi
        prepareHostQt
        prepareSdkInstallerTools
        prepareNecessitasQtCreator
        prepareSDKBinary
    done
fi

#prepareWindowsPackages
setPackagesVariables

# Comment this block in if you want necessitas-sdk-installer-d and qtcreator-d to be built.
if [ "$MAKE_DEBUG_HOST_APPS" = "1" ] ; then
    prepareHostQt -d
    prepareNecessitasQtCreator
    prepareSdkInstallerTools
    prepareSDKBinary
fi

removeUnusedPackages

prepareSDKRepository
prepareMinistroRepository

popd
