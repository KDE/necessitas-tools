/*
    Copyright (c) 2011, BogDan Vatra <bog_dan_ro@yahoo.com>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

// constructor
function Component()
{
    if( component.fromOnlineRepository )
    {
        if (installer.value("os") == "x11")
        {
            component.addDownloadableArchive( "android-ndk-@@ANDROID_NDK_VERSION@@-ma-linux-x86.7z" );
        }
        else if (installer.value("os") == "win")
        {
            component.addDownloadableArchive( "android-ndk-@@ANDROID_NDK_VERSION@@-ma-windows.7z" );
        }
        else if (installer.value("os") == "mac")
        {
            component.addDownloadableArchive( "android-ndk-@@ANDROID_NDK_VERSION@@-ma-darwin-x86.7z" );
        }
    }
}

Component.prototype.beginInstallation = function()
{
    if (installer.value("os") == "x11" )
        component.setStopProcessForUpdateRequest("@TargetDir@/QtCreator/bin/qtcreator", true);
    else if (installer.value("os") == "mac")
        component.setStopProcessForUpdateRequest("@TargetDir@/Qt Creator.app/Contents/MacOS/Qt Creator", true);
    else if (installer.value("os") === "win")
        component.setStopProcessForUpdateRequest("qtcreator.exe", true);
}

Component.prototype.createOperations = function()
{
    // Call the base createOperations(unpacking ...)
    component.createOperations();
    if (installer.isUpdater())
    {
        if (installer.value("os") == "mac")
            component.addOperation( "SimpleMoveFile", "@TargetDir@/Qt Creator.app/Contents/Resources/Nokia/android.xml", "@TargetDir@/Qt Creator.app/Contents/Resources/Nokia/android.xml_backup");
        else
            component.addOperation( "SimpleMoveFile", "@TargetDir@/QtCreator/share/qtcreator/Nokia/android.xml", "@TargetDir@/QtCreator/share/qtcreator/Nokia/android.xml_backup");
    }
    // set NDK Location
    component.addOperation( "RegisterPersistentSettings",
                            "android.xml",
                            "NDKLocation",
                            "@TargetDir@/android-ndk" );
    // set NDK toolchain version
    component.addOperation( "RegisterPersistentSettings",
                            "android.xml",
                            "NDKToolchainVersion",
                            "4.4.3" );

    // set DEFAULT gdb location
    var gdbPath = "@TargetDir@/android-ndk/toolchains/arm-linux-androideabi-4.6/prebuilt/";
    var gdbserverPath = "@TargetDir@/android-ndk/prebuilt/android-arm/gdbserver/gdbserver";
    if (installer.value("os") == "x11")
    {
        gdbPath+="linux-x86/bin/arm-linux-androideabi-gdb";
    }
    else if (installer.value("os") == "win")
    {
        gdbPath+="windows/bin/arm-linux-androideabi-gdb.exe";
    }
    else if (installer.value("os") == "mac")
    {
        gdbPath+="darwin-x86/bin/arm-linux-androideabi-gdb";
    }

    component.addOperation( "RegisterPersistentSettings",
                            "android.xml",
                            "GdbLocation",
                            gdbPath );
    component.addOperation( "RegisterPersistentSettings",
                            "android.xml",
                            "GdbserverLocation",
                            gdbserverPath );
}
