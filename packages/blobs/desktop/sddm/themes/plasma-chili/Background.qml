/*
 *   Copyright 2016 Boudhayan Gupta <bgupta@kde.org>
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU Library General Public License as
 *   published by the Free Software Foundation; either version 2 or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details
 *
 *   You should have received a copy of the GNU Library General Public
 *   License along with this program; if not, write to the
 *   Free Software Foundation, Inc.,
 *   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

import QtQuick 2.2

import QtGraphicalEffects 1.0

FocusScope {
    id: sceneBackground

    Image {
        id: sceneImageBackground
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: config.background || config.Background
        smooth: true
    }

    RecursiveBlur {
        anchors.fill: sceneImageBackground
        source: sceneImageBackground
        radius: config.Blur == "true" ? config.RecursiveBlurRadius : 0
        loops: config.Blur == "true" ? config.RecursiveBlurLoops : 0
    }
}
