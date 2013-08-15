/*
    Copyright (c) 2011-2013, BogDan Vatra <bog_dan_ro@yahoo.com>

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License as
    published by the Free Software Foundation; either version 2 of
    the License or (at your option) version 3 or any later version
    accepted by the membership of KDE e.V. (or its successor approved
    by the membership of KDE e.V.), which shall act as a proxy
    defined in Section 14 of version 3 of the license.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <QtCore/QCoreApplication>
#include "sortlibs.h"
#include <QDebug>
#include <QDomDocument>
#include <QFile>
#include <QDir>
#include <QCryptographicHash>

#if defined(__MINGW32__)
#include <io.h>
#endif

#include <QDirIterator>
#include <unistd.h>

static void printHelp()
{
    qDebug()<<"Usage:./ministrorepogen <readelf executable path> <libraries path> <version> <abi version> <xml rules file> <output folder>  <out objects repo version> <qt version>";
}


static void getFileInfo(const QString & filePath, qint64 & fileSize, QString & sha1)
{
    fileSize = -1;
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly))
        return;
    QCryptographicHash hash(QCryptographicHash::Sha1);
    hash.addData(file.readAll());
    sha1=hash.result().toHex();
    fileSize=file.size();
}

static void addNeedsFile(QVector<NeedsStruct> & needs, const QString & file)
{
    NeedsStruct needed;
    needed.relativePath=file;
    needed.name=file.mid(file.lastIndexOf('/') + 1);
    needs << needed;
}

static QString niceName(const QString & name)
{
    if (name.startsWith("lib") && name.endsWith(".so"))
        return name.mid(3, name.length() -6);
    return name;
}

static void parseXmlFile(librariesMap &libs, const QString &xmlFile, const QString &libsPath)
{
    QDomDocument doc("libs");
    QFile xf(xmlFile);
    if (!xf.open(QIODevice::ReadOnly))
        return;
    if (!doc.setContent(&xf))
        return;
    QDomElement element = doc.documentElement().firstChildElement("dependencies").firstChildElement("lib");
    if (element.isNull())
        return;

    if (!element.hasAttribute("name"))
        return;

    const QString name=element.attribute("name");
    const QString libraryName=QString("lib%1.so").arg(name);
    libs[libraryName].relativePath=QString("lib/%1").arg(libraryName);
    libs[libraryName].name=name;
    if (element.hasAttribute("platform"))
        libs[libraryName].platform=element.attribute("platform").toInt();
    element = element.firstChildElement("depends");
    QDomElement childs=element.firstChildElement("lib");
    while(!childs.isNull())
    {
        QString file = childs.attribute("file");
        if (file != "libs/libgnustl_shared.so")
        {
            QString libName = niceName(file.mid(file.lastIndexOf('/') + 1));
            if (!file.startsWith("lib/"))
            {
                libs[libName].relativePath = file;
                libs[libName].name = libName;
                libs[libName].level = 9999;
            }

            if (!libs[libraryName].dependencies.contains(libName))
                libs[libraryName].dependencies << libName;

            if (childs.hasAttribute("replaces"))
            {
                QString replaces = childs.attribute("replaces");
                replaces = niceName(replaces.mid(replaces.lastIndexOf('/') + 1));
                if (!libs[libName].replaces.contains(replaces))
                        libs[libName].replaces << replaces;
            }
        }
        childs=childs.nextSiblingElement("lib");
    }

    childs=element.firstChildElement("jar");
    while(!childs.isNull())
    {
        if (!childs.hasAttribute("bundling"))
        {
            NeedsStruct needed;
            needed.relativePath=childs.attribute("file");
            needed.name=needed.relativePath.mid(needed.relativePath.lastIndexOf('/') + 1);
            needed.type="jar";
            if (childs.hasAttribute("initClass"))
                needed.initClass=childs.attribute("initClass");
            libs[libraryName].needs << needed;
        }
        childs=childs.nextSiblingElement("jar");
    }

    childs=element.firstChildElement("bundled");
    while(!childs.isNull())
    {
        QString file = childs.attribute("file");
        if (QFileInfo(libsPath + file).isDir())
        {
            QDirIterator it(libsPath + file, QDirIterator::Subdirectories);
            while(it.hasNext())
            {
                it.next();
                if (it.fileInfo().isFile())
                    addNeedsFile(libs[libraryName].needs, it.fileInfo().filePath().mid(libsPath.length()));
            }
        }
        else
            addNeedsFile(libs[libraryName].needs, file);
        childs=childs.nextSiblingElement("bundled");
    }
}

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    if (argc<9)
    {
        printHelp();
        return 1;
    }

    const char * readelfPath=argv[1];
    QString libsPath(argv[2]);
    if (!libsPath.endsWith('/'))
        libsPath += '/';
    const char * version=argv[3];
    const char * abiVersion=argv[4];
    const char * rulesFile=argv[5];
    const char * outputFolder=argv[6];
    const char * objfolder =argv [7];
    const char * qtVersion =argv [8];

    QDomDocument document("libs");
    QFile f(rulesFile);
    if (!f.open(QIODevice::ReadOnly))
        return 1;
    document.setContent(&f);
    QDomElement root=document.documentElement();
    if (root.isNull())
        return 1;

    QDomElement element=root.firstChildElement("platforms");
    if (element.isNull())
        return 1;

    QMap<int, QVector<int> >platformLibs;
    element=element.firstChildElement("libs").firstChildElement("version");
    while(!element.isNull())
    {
        if (element.hasAttribute("symlink"))
            platformLibs[element.attribute("symlink", 0).toInt()].push_back(element.attribute("value", 0).toInt());
        else
            platformLibs[element.attribute("value", 0).toInt()].clear();
        element = element.nextSiblingElement();
    }

    QMap<int, int >platformJars;
    element=root.firstChildElement("platforms").firstChildElement("jars").firstChildElement("version");
    while(!element.isNull())
    {
        if (element.hasAttribute("symlink"))
            platformJars[element.attribute("value", 0).toInt()]=element.attribute("symlink", 0).toInt();
        else
            platformJars[element.attribute("value", 0).toInt()]=element.attribute("value", 0).toInt();
        element = element.nextSiblingElement();
    }

    element=root.firstChildElement("libs");
        if (element.isNull())
            return 1;

    QStringList excludePaths=element.attribute("excludePaths").split(';');
    QString loaderClassName=element.attribute("loaderClassName");
    QString applicationParameters=element.attribute("applicationParameters");
    QString environmentVariables=element.attribute("environmentVariables");
    librariesMap libs;

    // check all android xml rules
    QDirIterator it(libsPath + "lib/", QStringList("*.xml"));
    while(it.hasNext())
        parseXmlFile(libs, it.next(), libsPath);

    SortLibraries(libs, readelfPath, libsPath, excludePaths);

    QDir path;
    QString xmlPath(outputFolder+QString("/%1/").arg(abiVersion));
    path.mkpath(xmlPath);
    path.cd(xmlPath);
    chdir(path.absolutePath().toUtf8().constData());
    foreach (int androdPlatform, platformLibs.keys())
    {
        qDebug()<<"============================================";
        qDebug()<<"Generating repository for android platform :"<<androdPlatform;
        qDebug()<<"--------------------------------------------";
        path.mkpath(QString("android-%1").arg(androdPlatform));
        xmlPath=QString("android-%1/libs-%2.xml").arg(androdPlatform).arg(version);
        foreach(int symLink, platformLibs[androdPlatform])
            QFile::link(QString("android-%1").arg(androdPlatform), QString("android-%1").arg(symLink));
        QFile outXmlFile(xmlPath);
        outXmlFile.open(QIODevice::WriteOnly);
        outXmlFile.write(QString("<libs flags=\"0\" version=\"%1\" applicationParameters=\"%2\" environmentVariables=\"%3\" loaderClassName=\"%4\" qtVersion=\"%5\">\n")
					.arg(version)
					.arg(applicationParameters)
					.arg(environmentVariables)
					.arg(loaderClassName)
					.arg(qtVersion).toUtf8());
        foreach (const QString & key, libs.keys())
        {
            if (libs[key].platform && libs[key].platform != androdPlatform)
                continue;
            qDebug()<<"Generating "<<key<<" informations";
            qint64 fileSize;
            QString sha1Hash;
            getFileInfo(libsPath+"/"+libs[key].relativePath, fileSize, sha1Hash);
            if (-1==fileSize)
            {
                qWarning()<<"Warning : Can't find \""<<libsPath+"/"+libs[key].relativePath<<"\" item will be skipped";
                continue;
            }
            outXmlFile.write(QString("\t<lib name=\"%1\" url=\"http://download.qt-project.org/ministro/android/qt5/objects/%2/%3\" file=\"%3\" size=\"%4\" sha1=\"%5\" level=\"%6\"")
                             .arg(libs[key].name).arg(objfolder).arg(libs[key].relativePath).arg(fileSize).arg(sha1Hash).arg(libs[key].level).toUtf8());
            if (!libs[key].dependencies.size() && !libs[key].needs.size())
            {
                outXmlFile.write(" />\n\n");
                continue;
            }
            outXmlFile.write(">\n");
            if (libs[key].dependencies.size())
            {
                outXmlFile.write("\t\t<depends>\n");
                foreach(const QString & libName, libs[key].dependencies)
                    outXmlFile.write(QString("\t\t\t<lib name=\"%1\"/>\n").arg(libName).toUtf8());
                outXmlFile.write("\t\t</depends>\n");
            }

            if (libs[key].replaces.size())
            {
                outXmlFile.write("\t\t<replaces>\n");
                foreach(const QString & libName, libs[key].replaces)
                    outXmlFile.write(QString("\t\t\t<lib name=\"%1\"/>\n").arg(libName).toUtf8());
                outXmlFile.write("\t\t</replaces>\n");
            }

            if (libs[key].needs.size())
            {
                outXmlFile.write("\t\t<needs>\n");
                foreach(const NeedsStruct & needed, libs[key].needs)
                {
                    qint64 fileSize;
                    QString sha1Hash;
                    getFileInfo(libsPath+"/"+needed.relativePath.arg(platformJars[androdPlatform]), fileSize, sha1Hash);
                    if (-1==fileSize)
                    {
                        qWarning()<<"Warning : Can't find \""<<libsPath+"/"+needed.relativePath.arg(platformJars[androdPlatform])<<"\" item will be skipped";
                        continue;
                    }

                    QString type;
                    if (needed.type.length())
                        type=QString(" type=\"%1\" ").arg(needed.type);

                    QString initClass;
                    if (needed.initClass.length())
                        initClass=QString(" initClass=\"%1\" ").arg(needed.initClass);

                    outXmlFile.write(QString("\t\t\t<item name=\"%1\" url=\"http://download.qt-project.org/ministro/android/qt5/objects/%2/%3\" file=\"%3\" size=\"%4\" sha1=\"%5\"%6%7/>\n")
                                     .arg(needed.name).arg(objfolder).arg(needed.relativePath.arg(platformJars[androdPlatform])).arg(fileSize).arg(sha1Hash).arg(type).arg(initClass).toUtf8());
                }
                outXmlFile.write("\t\t</needs>\n");
            }
            outXmlFile.write("\t</lib>\n\n");
        }
        outXmlFile.write("</libs>\n");
        outXmlFile.close();
    }
    return 0;
}
