#!/bin/bash

MINISTRO_REPO_VERSION=5.106
ANDROID_NDK_PATH=/root/necessitas/android-ndk
READELF=$ANDROID_NDK_PATH/toolchains/arm-linux-androideabi-4.7/prebuilt/linux-x86_64/bin/arm-linux-androideabi-readelf
RULES=rules.xml
QT_BINS=/opt/Qt5.1.0/5.1.0-beta1

create_repo()
{
    ARCHITECTURE=$1 #armeabi-v7a # armeabi x86 mips
    QT_PATH=$PWD/Qt/$ARCHITECTURE/
    OUT_PATH=$PWD/unstable
    OBJECTS_REPO=$MINISTRO_REPO_VERSION-$ARCHITECTURE
    OBJECTS_PATH=$PWD/objects
    QT_VERSION=$((0x050100))

    ./ministrorepogen $READELF $QT_PATH $MINISTRO_REPO_VERSION $ARCHITECTURE $RULES $OUT_PATH $OBJECTS_REPO $QT_VERSION

    mkdir -p $OBJECTS_PATH
    rm -fr $OBJECTS_PATH/$OBJECTS_REPO
    cp -a $QT_PATH $OBJECTS_PATH/$OBJECTS_REPO
}

copy_qt()
{
    mkdir -p Qt/$2/lib
    cp -L $1/lib/*.so Qt/$2/lib
    cp $ANDROID_NDK_PATH/sources/cxx-stl/gnu-libstdc++/4.7/libs/$2/libgnustl_shared.so Qt/$2/lib/
    cp -a $1/imports Qt/$2
    cp -a $1/jar Qt/$2
    cp -a $1/plugins Qt/$2
    cp -a $1/qml Qt/$2
}

rm -fr Qt
rm -fr objects
rm -fr unstable

copy_qt $QT_BINS/android_armv7 armeabi-v7a
copy_qt $QT_BINS/android_x86 x86

create_repo armeabi-v7a
create_repo x86
