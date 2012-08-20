MINISTRO_VERSION="0.4" #Ministro repo version

OSTYPE_MAJOR=${OSTYPE//[0-9.]/}

if [ "$OSTYPE_MAJOR" = "linux-gnu" ] ; then
    JOBS=`cat /proc/cpuinfo | grep processor | wc -l`
    JOBS=`expr $JOBS + 2`
elif [ "$OSTYPE_MAJOR" = "darwin" ] ; then
    JOBS=`sysctl -n hw.ncpu`
    JOBS=`expr $JOBS + 2`
else
    JOBS=`expr $NUMBER_OF_PROCESSORS + 2`
fi

CHECKOUT_BRANCH="unstable"

NECESSITAS_QT_CREATOR_VERSION="2.5.81"

# p7zip sometimes doesn't come with 7z (just 7za),
#  whereas p7zip-full includes it.
# Debian 6.0.5 runs an old 7z (9.04) with a -l option
#  that's since been removed. It dereferences symlinks.
if [ $(which 7z) -a ! "$(OSTYPE_MAJOR)" = "darwin" ] ; then
    EXTERNAL_7Z=7z
    EXTERNAL_7Z_A_PARAMS="a -t7z -mx=9 -mmt=$JOBS"
    # Check if version <= 9.04 and use -l when creating windows 7zs if so.
    EXTERNAL_7Z_VER=$(7z | sed -n 2p | sed -e 's/7-Zip[ A-Z\(\)]*\([0-9]*\)\.\([0-9]*\).*$/\1\2/')
    if [ ! $EXTERNAL_7Z_VER -gt 904 ] ; then
        EXTERNAL_7Z_A_PARAMS_WIN="-l"
    fi
    EXTERNAL_7Z_X_PARAMS="-y x"
else
    EXTERNAL_7Z=7za
    EXTERNAL_7Z_A_PARAMS="a -mx=9"
    EXTERNAL_7Z_A_PARAMS_WIN=
    EXTERNAL_7Z_X_PARAMS="x"
fi

# Qt Framework versions
NECESSITAS_QT_VERSION_SHORT=482 #Necessitas Qt Framework Version
NECESSITAS_QT_VERSION="4.8.2 Alpha 4" #Necessitas Qt Framework Long Version
NECESSITAS_QT_PACKAGE_VERSION="4.8.2-400"
MINISTRO_QT_VERSION=$((0x040802)) #Minstro Qt Version

NECESSITAS_QTWEBKIT_VERSION="2.2" #Necessitas QtWebkit Version

NECESSITAS_QTMOBILITY_VERSION="1.2.0" #Necessitas QtMobility Version

# NDK variables
BUILD_ANDROID_GIT_NDK=0 # Latest and the greatest NDK built from sources
ANDROID_NDK_MAJOR_VERSION=r8b # NDK major version, used by package name (and ma ndk)
ANDROID_NDK_VERSION=r8b # NDK full package version
USE_MA_NDK=1

# SDK variables
ANDROID_SDK_VERSION=r20
ANDROID_PLATFORM_TOOLS_VERSION=r12
ANDROID_API_4_VERSION=1.6_r03
ANDROID_API_5_VERSION=2.0_r01
ANDROID_API_6_VERSION=2.0.1_r01
ANDROID_API_7_VERSION=2.1_r03
ANDROID_API_8_VERSION=2.2_r03
ANDROID_API_9_VERSION=2.3.1_r02
ANDROID_API_10_VERSION=2.3.3_r02
ANDROID_API_11_VERSION=3.0_r02
ANDROID_API_12_VERSION=3.1_r03
ANDROID_API_13_VERSION=3.2_r01
ANDROID_API_14_VERSION=14_r03
ANDROID_API_15_VERSION=15_r03
ANDROID_API_16_VERSION=16_r01

# Make debug versions of host applications (Qt Creator and installer).
MAKE_DEBUG_HOST_APPS=0

MAKE_DEBUG_GDBSERVER=0
