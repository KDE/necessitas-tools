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
    if (installer.value("os") == "x11" || installer.value("os") == "mac")
    {
        compiler = installer.execute( "/usr/bin/which", new Array( "make" ) )[0];
        if (!compiler) {
            QMessageBox["warning"]( "Error", "No *make* tool!", "You need *make* tool. Please install it using the System Package Management tools." );
        }
        compiler = installer.execute( "/usr/bin/which", new Array( "java" ) )[0];
        if (!compiler) {
            QMessageBox["warning"]( "Error", "No java compiler!", "You need a java compiler. Please install it using the System Package Management tools  (e.g. sudo apt-get install openjdk-6-jdk)." );
        }
        compiler = installer.execute( "/usr/bin/which", new Array( "javac" ) )[0];
        if (!compiler) {
            QMessageBox["warning"]( "Error", "No java compiler!", "You need a java compiler. Please install it using the System Package Management tools (e.g. sudo apt-get install openjdk-6-jdk)." );
        }
    }
    installer.setValue("GlobalExamplesDir", "Examples");
    installer.setValue("GlobalDemosDir", "Demos");
    installer.setValue("QtVersionLabel", "Necessitas Qt SDK");
}

Component.prototype.createOperations = function()
{
    // Call the base createOperations and afterwards set some registry settings
    component.createOperations();
    if (installer.value("QtCreatorSettingsFile") !== "")
        component.addOperation( "SimpleMoveFile", "@QtCreatorSettingsFile@", "@QtCreatorSettingsFile@_backup");
    if (installer.value("QtCreatorSettingsQtVersionFile") !== "")
        component.addOperation( "SimpleMoveFile", "@QtCreatorSettingsQtVersionFile@", "@QtCreatorSettingsQtVersionFile@_backup");
    if (installer.value("QtCreatorSettingsToolchainsFile") !== "")
        component.addOperation( "SimpleMoveFile", "@QtCreatorSettingsToolchainsFile@", "@QtCreatorSettingsToolchainsFile@_backup");
}
