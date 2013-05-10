#!/bin/bash

ARCHITECTURE=armeabi-v7a # armeabi x86 mips
MINISTRO_REPO_VERSION=5.103
QT_PATH=$PWD/Qt/$ARCHITECTURE/
READELF=/root/necessitas/android-ndk/toolchains/arm-linux-androideabi-4.7/prebuilt/linux-x86_64/bin/arm-linux-androideabi-readelf
RULES=rules.xml
OUT_PATH=$PWD/unstable
OBJECTS_REPO=$MINISTRO_REPO_VERSION-$ARCHITECTURE
OBJECTS_PATH=$PWD/objects
QT_VERSION=$((0x050100))

./ministrorepogen $READELF $QT_PATH $MINISTRO_REPO_VERSION $ARCHITECTURE $RULES $OUT_PATH $OBJECTS_REPO $QT_VERSION
mkdir -p $OBJECTS_PATH
rm -fr $OBJECTS_PATH/$OBJECTS_REPO
cp -a $QT_PATH $OBJECTS_PATH/$OBJECTS_REPO
#./ministrorepogen /root/necessitas/android-ndk/toolchains/arm-linux-androideabi-4.7/prebuilt/linux-x86_64/bin/arm-linux-androideabi-readelf $PWD/Qt 5.1 armeabi-v7a rules.xml $PWD/unstable armeabi-v7a-5.1 327936
