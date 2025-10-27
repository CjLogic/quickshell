import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Rectangle {
    id: root
    property int messageIndex
    property var messageData
    property var messageInputField

    // Conditional bubble: user messages get a bubble; assistant is flat
    property real messagePadding: messageData?.role == 'user' ? 7 : 0
    property real contentSpacing: 4

    property bool enableMouseSelection: false
    property bool renderMarkdown: true
    property bool editing: false

    property list<var> messageBlocks: StringUtils.splitMarkdownBlocks(root.messageData?.content)

    anchors.left: parent?.left
    anchors.right: parent?.right
    implicitHeight: columnLayout.implicitHeight + root.messagePadding * 2

    radius: messageData?.role == 'user' ? Appearance.rounding.normal : 0
    color: messageData?.role == 'user' ? Appearance.colors.colLayer1 : "transparent"

    function saveMessage() {
        if (!root.editing) return;
        // Get all Loader children (each represents a segment)
        const segments = messageContentColumnLayout.children
            .map(child => child.segment)
            .filter(segment => (segment));

        // Reconstruct markdown
        const newContent = segments.map(segment => {
            if (segment.type === "code") {
                const lang = segment.lang ? segment.lang : "";
                // Remove trailing newlines
                const code = segment.content.replace(/\n+$/, "");
                return "```" + lang + "\n" + code + "\n```";
            } else {
                return segment.content;
            }
        }).join("");

        root.editing = false
        root.messageData.content = newContent;
    }

    Keys.onPressed: (event) => {
        if ( // Prevent de-select
            event.key === Qt.Key_Control ||
            event.key == Qt.Key_Shift ||
            event.key == Qt.Key_Alt ||
            event.key == Qt.Key_Meta
        ) {
            event.accepted = true
        }
        // Ctrl + S to save
        if ((event.key === Qt.Key_S) && event.modifiers == Qt.ControlModifier) {
            root.saveMessage();
            event.accepted = true;
        }
    }


    ColumnLayout { // Main layout of the whole thing
        id: columnLayout

    // Add a small extra gap only when switching between user and assistant
    property string _prevRole: (messageIndex > 0 && Ai.messageByID[Ai.messageIDs[messageIndex-1]]) ? (Ai.messageByID[Ai.messageIDs[messageIndex-1]].role || "") : ""
    property int _roleGap: (_prevRole !== (messageData?.role || "")) ? 8 : 0

    anchors.left: parent?.left
    anchors.right: parent?.right
    anchors.top: parent?.top
    anchors.margins: messagePadding
    anchors.topMargin: _roleGap
        spacing: root.contentSpacing


        Rectangle {
            Layout.fillWidth: true
            implicitWidth: headerRowLayout.implicitWidth + 4 * 2
            implicitHeight: headerRowLayout.implicitHeight + 4 * 2
            // Make header bar transparent for both user and assistant
            color: "transparent"
            radius: Appearance.rounding.small

            RowLayout { // Header
                id: headerRowLayout
                anchors {
                    fill: parent
                    margins: 4
                }
                spacing: 18

                Item { // Name
                    id: nameWrapper
                    implicitHeight: Math.max(nameRowLayout.implicitHeight + 5 * 2, 30)
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter

                    RowLayout {
                        id: nameRowLayout
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 7

                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillHeight: true
                            implicitWidth: messageData?.role == 'assistant' ? modelIcon.width : roleIcon.implicitWidth
                            implicitHeight: messageData?.role == 'assistant' ? modelIcon.height : roleIcon.implicitHeight

                            CustomIcon {
                                id: modelIcon
                                anchors.centerIn: parent
                                visible: messageData?.role == 'assistant' && Ai.models[messageData?.model].icon
                                width: Appearance.font.pixelSize.large
                                height: Appearance.font.pixelSize.large
                                source: messageData?.role == 'assistant' ? Ai.models[messageData?.model].icon :
                                    messageData?.role == 'user' ? 'linux-symbolic' : 'desktop-symbolic'

                                colorize: true
                                color: messageData?.role == 'user' ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSecondaryContainer
                            }

                            MaterialSymbol {
                                id: roleIcon
                                anchors.centerIn: parent
                                visible: !modelIcon.visible
                                iconSize: Appearance.font.pixelSize.larger
                                color: messageData?.role == 'user' ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSecondaryContainer
                                text: messageData?.role == 'user' ? 'person' :
                                    messageData?.role == 'interface' ? 'settings' :
                                    messageData?.role == 'assistant' ? 'neurology' :
                                    'computer'
                            }
                        }

                        StyledText {
                            id: providerName
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: messageData?.role == 'user' ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSecondaryContainer
                            text: messageData?.role == 'assistant' ? Ai.models[messageData?.model].name :
                                (messageData?.role == 'user' && SystemInfo.username) ? SystemInfo.username :
                                Translation.tr("Interface")
                        }

                        BusyIndicator {
                            running: messageData?.thinking || false
                            visible: running
                            implicitWidth: Appearance.font.pixelSize.normal
                            implicitHeight: Appearance.font.pixelSize.normal
                        }
                    }
                }

                Button { // Not visible to model
                    id: modelVisibilityIndicator
                    visible: messageData?.role == 'interface'
                    implicitWidth: 16
                    implicitHeight: 30
                    Layout.alignment: Qt.AlignVCenter

                    background: Item

                    MaterialSymbol {
                        id: notVisibleToModelText
                        anchors.centerIn: parent
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        text: "visibility_off"
                    }
                    StyledToolTip {
                        text: Translation.tr("Not visible to model")
                    }
                }

                // Header tools (only for user messages); transparent background
                ButtonGroup {
                    visible: messageData?.role == 'user'
                    spacing: 5

                    AiMessageControlButton {
                        id: copyButton
                        colBackground: "transparent"
                        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colSecondaryContainerHover, 1)
                        buttonIcon: activated ? "inventory" : "content_copy"

                        onClicked: {
                            Quickshell.clipboardText = root.messageData?.content
                            copyButton.activated = true
                            copyIconTimer.restart()
                        }

                        Timer {
                            id: copyIconTimer
                            interval: 1500
                            repeat: false
                            onTriggered: {
                                copyButton.activated = false
                            }
                        }

                        StyledToolTip {
                            text: Translation.tr("Copy")
                        }
                    }
                    AiMessageControlButton {
                        id: editButton
                        colBackground: "transparent"
                        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colSecondaryContainerHover, 1)
                        activated: root.editing
                        enabled: root.messageData?.done ?? false
                        buttonIcon: "edit"
                        onClicked: {
                            root.editing = !root.editing
                            if (!root.editing) { // Save changes
                                root.saveMessage()
                            }
                        }
                        StyledToolTip {
                            text: root.editing ? Translation.tr("Save") : Translation.tr("Edit")
                        }
                    }
                    AiMessageControlButton {
                        id: toggleMarkdownButton
                        colBackground: "transparent"
                        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colSecondaryContainerHover, 1)
                        activated: !root.renderMarkdown
                        buttonIcon: "code"
                        onClicked: {
                            root.renderMarkdown = !root.renderMarkdown
                        }
                        StyledToolTip {
                            text: Translation.tr("View Markdown source")
                        }
                    }
                    AiMessageControlButton {
                        id: deleteButton
                        colBackground: "transparent"
                        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colSecondaryContainerHover, 1)
                        buttonIcon: "close"
                        onClicked: {
                            Ai.removeMessage(root.messageIndex)
                        }
                        StyledToolTip {
                            text: Translation.tr("Delete")
                        }
                    }
                }
            }
        }

        Loader {
            Layout.fillWidth: true
            active: root.messageData?.localFilePath && root.messageData?.localFilePath.length > 0
            sourceComponent: AttachedFileIndicator {
                filePath: root.messageData?.localFilePath
                canRemove: false
            }
        }

        ColumnLayout { // Message content
            id: messageContentColumnLayout

            // Typing dots while waiting for first tokens
            Item {
                visible: (root.messageData?.thinking ?? false) && (!root.messageData?.content || root.messageData?.content.length === 0)
                implicitHeight: 18
                Layout.fillWidth: false
                RowLayout {
                    spacing: 6
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            width: 6; height: 6; radius: 3
                            color: Appearance.colors.colSubtext
                            opacity: 0.3
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { to: 1; duration: 300; easing.type: Easing.InOutQuad }
                                NumberAnimation { to: 0.3; duration: 300; easing.type: Easing.InOutQuad }
                                running: true
                                // stagger
                                onRunningChanged: {}
                            }
                            // delay via Timer per index
                            Timer { interval: index * 150; running: true; repeat: false; onTriggered: parent.opacity = parent.opacity }
                        }
                    }
                }
            }

            spacing: 0
            Repeater {
                model: root.messageBlocks.length
                delegate: Loader {
                    required property int index
                    property var thisBlock: root.messageBlocks[index]
                    Layout.fillWidth: true
                    // property var segment: thisBlock
                    property var segmentContent: thisBlock.content
                    property var segmentLang: thisBlock.lang
                    property var messageData: root.messageData
                    property var editing: root.editing
                    property var renderMarkdown: root.renderMarkdown
                    property var enableMouseSelection: root.enableMouseSelection
                    property bool thinking: root.messageData?.thinking ?? true
                    property bool done: root.messageData?.done ?? false
                    property bool completed: thisBlock.completed ?? false

                    property bool forceDisableChunkSplitting: root.messageData.content.includes("```")

                    source: thisBlock.type === "code" ? "MessageCodeBlock.qml" :
                        thisBlock.type === "think" ? "MessageThinkBlock.qml" :
                        "MessageTextBlock.qml"

                }
            }
        }

        // Bottom tools for assistant messages (transparent, below content)
        RowLayout {
            visible: messageData?.role == 'assistant'
            spacing: 5
            Layout.fillWidth: false
            Layout.alignment: Qt.AlignRight

            AiMessageControlButton {
                id: copyButtonBottom
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colSecondaryContainerHover, 1)
                buttonIcon: copyButton.activated ? "inventory" : "content_copy"
                onClicked: copyButton.clicked()
                StyledToolTip { text: Translation.tr("Copy") }
            }
            AiMessageControlButton {
                id: editButtonBottom
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colSecondaryContainerHover, 1)
                activated: editButton.activated
                enabled: editButton.enabled
                buttonIcon: "edit"
                onClicked: editButton.clicked()
                StyledToolTip { text: editButton.activated ? Translation.tr("Save") : Translation.tr("Edit") }
            }
            AiMessageControlButton {
                id: toggleMarkdownButtonBottom
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colSecondaryContainerHover, 1)
                activated: toggleMarkdownButton.activated
                buttonIcon: "code"
                onClicked: toggleMarkdownButton.clicked()
                StyledToolTip { text: Translation.tr("View Markdown source") }
            }
            AiMessageControlButton {
                id: deleteButtonBottom
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colSecondaryContainerHover, 1)
                buttonIcon: "close"
                onClicked: deleteButton.clicked()
                StyledToolTip { text: Translation.tr("Delete") }
            }
        }

        Flow { // Annotations
            visible: root.messageData?.annotationSources?.length > 0
            spacing: 5
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft

            Repeater {
                model: ScriptModel {
                    values: root.messageData?.annotationSources || []
                }
                delegate: AnnotationSourceButton {
                    required property var modelData
                    displayText: modelData.text
                    url: modelData.url
                }
            }
        }

        Flow { // Search queries
            visible: root.messageData?.searchQueries?.length > 0
            spacing: 5
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft

            Repeater {
                model: ScriptModel {
                    values: root.messageData?.searchQueries || []
                }
                delegate: SearchQueryButton {
                    required property var modelData
                    query: modelData
                }
            }
        }

    }
}

