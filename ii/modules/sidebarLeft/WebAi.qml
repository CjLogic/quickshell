import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine

Item {
    id: root
    anchors.fill: parent

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: 8
        color: "transparent"
        border.color: "transparent"
        clip: true

        WebEngineView {
            id: web
            anchors.fill: parent
            url: Qt.resolvedUrl("./webai/index.html")
            profile: WebEngineProfile.defaultProfile
            settings.javascriptEnabled: true
            settings.pluginsEnabled: false
            settings.errorPageEnabled: true
            settings.touchIconsEnabled: true
            settings.webRTCPublicInterfacesOnly: false
            zoomFactor: 1.0
            focus: true
        }
    }
}