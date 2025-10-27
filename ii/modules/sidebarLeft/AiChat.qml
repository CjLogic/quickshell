import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "./aiChat/"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Item {
    id: root
    required property var scopeRoot
    property var inputField: messageInputField
    property string commandPrefix: "/"

    // Auto-save settings
    property bool autoSaveEnabled: true
    property string autoSaveName: "autosave"

    // Settings state
    property var modelIds: Ai.modelList
    property int selectedModelIndex: 0
    property string selectedModelId: modelIds[selectedModelIndex] || ""
    property string promptDraft: ""
    readonly property string promptPath: FileUtils.trimFileProtocol(`${Directories.defaultAiPrompts}/${autoSaveName}.md`)

    // Staged (unsaved) settings
    property real pendingTemperature: 0
    property string pendingApiKey: ""

    property var suggestionQuery: ""
    property var suggestionList: []

    onFocusChanged: (focus) => {
        if (focus) {
            root.inputField.forceActiveFocus()
        }
    }

    Component.onCompleted: {
        // Restore last session autosave settings and prompt
        if (Persistent?.states?.ai) {
            if (Persistent.states.ai.autoSaveEnabled !== undefined) root.autoSaveEnabled = Persistent.states.ai.autoSaveEnabled;
            if (Persistent.states.ai.autoSaveName) root.autoSaveName = Persistent.states.ai.autoSaveName;
        }
        Ai.loadPrompt(root.promptPath);
    }

    Keys.onPressed: (event) => {
        messageInputField.forceActiveFocus()
        if (event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageUp) {
                messageListView.contentY = Math.max(0, messageListView.contentY - messageListView.height / 2)
                event.accepted = true
            } else if (event.key === Qt.Key_PageDown) {
                messageListView.contentY = Math.min(messageListView.contentHeight - messageListView.height / 2, messageListView.contentY + messageListView.height / 2)
                event.accepted = true
            }
        }
        if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_O) {
            Ai.clearMessages();
        }
    }

    property var allCommands: [
        {
            name: "attach",
            description: Translation.tr("Attach a file. Only works with Gemini."),
            execute: (args) => {
                Ai.attachFile(args.join(" ").trim());
            }
        },
        {
            name: "model",
            description: Translation.tr("Choose model"),
            execute: (args) => {
                Ai.setModel(args[0]);
            }
        },
        {
            name: "tool",
            description: Translation.tr("Set the tool to use for the model."),
            execute: (args) => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.addMessage(Translation.tr("Usage: %1tool TOOL_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                } else {
                    const tool = args[0];
                    const switched = Ai.setTool(tool);
                    if (switched) {
                        Ai.addMessage(Translation.tr("Tool set to: %1").arg(tool), Ai.interfaceRole);
                    }
                }
            }
        },
        {
            name: "prompt",
            description: Translation.tr("Set the system prompt for the model."),
            execute: (args) => {
                if (args.length === 0 || args[0] === "get") {
                    Ai.printPrompt();
                    return;
                }
                Ai.loadPrompt(args.join(" ").trim());
            }
        },
        {
            name: "key",
            description: Translation.tr("Set API key"),
            execute: (args) => {
                if (args[0] == "get") {
                    Ai.printApiKey()
                } else {
                    Ai.setApiKey(args[0]);
                }
            }
        },
        {
            name: "save",
            description: Translation.tr("Save chat"),
            execute: (args) => {
                const joinedArgs = args.join(" ")
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1save CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.saveChat(joinedArgs)
            }
        },
        {
            name: "load",
            description: Translation.tr("Load chat"),
            execute: (args) => {
                const joinedArgs = args.join(" ")
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1load CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.loadChat(joinedArgs)
            }
        },
        {
            name: "clear",
            description: Translation.tr("Clear chat history"),
            execute: () => {
                Ai.clearMessages();
            }
        },
        {
            name: "temp",
            description: Translation.tr("Set temperature (randomness) of the model. Values range between 0 to 2 for Gemini, 0 to 1 for other models. Default is 0.5."),
            execute: (args) => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.printTemperature()
                } else {
                    const temp = parseFloat(args[0]);
                    Ai.setTemperature(temp);
                }
            }
        },
        {
            name: "test",
            description: Translation.tr("Markdown test"),
            execute: () => {
                Ai.addMessage(`
<think>
A longer think block to test revealing animation
OwO wem ipsum dowo sit amet, consekituwet awipiscing ewit, sed do eiuwsmod tempow inwididunt ut wabowe et dowo mawa. Ut enim ad minim weniam, quis nostwud exeucitation uwuwamcow bowowis nisi ut awiquip ex ea commowo consequat. Duuis aute iwuwe dowo in wepwependewit in wowuptate velit esse ciwwum dowo eu fugiat nuwa pawiatuw. Excepteuw sint occaecat cupidatat non pwowoident, sunt in cuwpa qui officia desewunt mowit anim id est wabowum. Meouw! >w<
Mowe uwu wem ipsum!
</think>
## ✏️ Markdown test
### Formatting

- *Italic*, \`Monospace\`, **Bold**, [Link](https://example.com)
- Arch lincox icon <img src="${Quickshell.shellPath("assets/icons/arch-symbolic.svg")}" height="${Appearance.font.pixelSize.small}"/>

### Table

Quickshell vs AGS/Astal

|                          | Quickshell       | AGS/Astal         |
|--------------------------|------------------|-------------------|
| UI Toolkit               | Qt               | Gtk3/Gtk4         |
| Language                 | QML              | Js/Ts/Lua         |
| Reactivity               | Implied          | Needs declaration |
| Widget placement         | Mildly difficult | More intuitive    |
| Bluetooth & Wifi support | ❌               | ✅                |
| No-delay keybinds        | ✅               | ❌                |
| Development              | New APIs         | New syntax        |

### Code block

Just a hello world...

\`\`\`cpp
#include <bits/stdc++.h>
// This is intentionally very long to test scrolling
const std::string GREETING = \"UwU\";
int main(int argc, char* argv[]) {
    std::cout << GREETING;
}
\`\`\`

### LaTeX


Inline w/ dollar signs: $\\frac{1}{2} = \\frac{2}{4}$

Inline w/ double dollar signs: $$\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}$$

Inline w/ backslash and square brackets \\[\\int_0^\\infty \\frac{1}{x^2} dx = \\infty\\]

Inline w/ backslash and round brackets \\(e^{i\\pi} + 1 = 0\\)
`,
                    Ai.interfaceRole);
            }
        },
    ]

    function handleInput(inputText) {
        if (inputText.startsWith(root.commandPrefix)) {
            // Handle special commands
            const command = inputText.split(" ")[0].substring(1);
            const args = inputText.split(" ").slice(1);
            const commandObj = root.allCommands.find(cmd => cmd.name === `${command}`);
            if (commandObj) {
                commandObj.execute(args);
            } else {
                Ai.addMessage(Translation.tr("Unknown command: ") + command, Ai.interfaceRole);
            }
        }
        else {
            Ai.sendUserMessage(inputText);
        }

        // Always scroll to bottom when user sends a message
        messageListView.positionViewAtEnd()
    }

    Process {
        id: decodeImageAndAttachProc
        property string imageDecodePath: Directories.cliphistDecode
        property string imageDecodeFileName: "image"
        property string imageDecodeFilePath: `${imageDecodePath}/${imageDecodeFileName}`
        function handleEntry(entry: string) {
            imageDecodeFileName = parseInt(entry.match(/^(\d+)\t/)[1])
            decodeImageAndAttachProc.exec(["bash", "-c",
                `[ -f ${imageDecodeFilePath} ] || echo '${StringUtils.shellSingleQuoteEscape(entry)}' | ${Cliphist.cliphistBinary} decode > '${imageDecodeFilePath}'`
            ])
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                Ai.attachFile(imageDecodeFilePath);
            } else {
                console.error("[AiChat] Failed to decode image in clipboard content")
            }
        }
    }

    component StatusItem: MouseArea {
        id: statusItem
        property string icon
        property string statusText
        property string description
        hoverEnabled: true
        implicitHeight: statusItemRowLayout.implicitHeight
        implicitWidth: statusItemRowLayout.implicitWidth

        RowLayout {
            id: statusItemRowLayout
            spacing: 0
            MaterialSymbol {
                text: statusItem.icon
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colSubtext
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                text: statusItem.statusText
                color: Appearance.colors.colSubtext
                animateChange: true
            }
        }

        StyledToolTip {
            text: statusItem.description
            extraVisibleCondition: false
            alternativeVisibleCondition: statusItem.containsMouse
        }
    }

    component StatusSeparator: Rectangle {
        implicitWidth: 4
        implicitHeight: 4
        radius: implicitWidth / 2
        color: Appearance.colors.colOutlineVariant
    }

    // Throttled auto-save when messages change
    Timer {
        id: autoSaveTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if (root.autoSaveEnabled) {
                Ai.saveChat(root.autoSaveName)
            }
        }
    }

    // Settings dialog state
    property bool aiSettingsOpen: false

    ColumnLayout {
        id: columnLayout
        anchors.fill: parent

        RowLayout { // Status
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            StatusItem {
                icon: Ai.currentModelHasApiKey ? "key" : "key_off"
                statusText: ""
                description: Ai.currentModelHasApiKey ? Translation.tr("API key is set\nChange with /key YOUR_API_KEY") : Translation.tr("No API key\nSet it with /key YOUR_API_KEY")
            }
            StatusSeparator {}
            StatusItem {
                icon: "device_thermostat"
                statusText: Ai.temperature.toFixed(1)
                description: Translation.tr("Temperature\nChange with /temp VALUE")
            }
            StatusSeparator {
                visible: Ai.tokenCount.total > 0
            }
            StatusItem {
                visible: Ai.tokenCount.total > 0
                icon: "token"
                statusText: Ai.tokenCount.total
                description: Translation.tr("Total token count\nInput: %1\nOutput: %2")
                    .arg(Ai.tokenCount.input)
                    .arg(Ai.tokenCount.output)
            }
        }

        Item { // Messages
            Layout.fillWidth: true
            Layout.fillHeight: true
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: swipeView.width
                    height: swipeView.height
                    radius: Appearance.rounding.small
                }
            }

            ScrollEdgeFade {
                z: 1
                target: messageListView
                vertical: true
            }

            // Settings (gear) button in top-right
            RippleButton {
                id: aiSettingsButton
                z: 3
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 6
                anchors.rightMargin: 6
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                downAction: () => { root.aiSettingsOpen = true }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "settings"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer2
                }
                StyledToolTip { text: Translation.tr("AI Settings") }
            }

            StyledListView { // Message list
                id: messageListView
                z: 0
                anchors.fill: parent
                spacing: 10
                popin: false

                touchpadScrollFactor: Config.options.interactions.scrolling.touchpadScrollFactor * 1.4
                mouseScrollFactor: Config.options.interactions.scrolling.mouseScrollFactor * 1.4

                property int lastResponseLength: 0
                onContentHeightChanged: {
                    if (atYEnd) Qt.callLater(positionViewAtEnd);
                }
                onCountChanged: { // Auto-scroll when new messages are added
                    if (atYEnd) Qt.callLater(positionViewAtEnd);
                    autoSaveTimer.restart(); // trigger autosave shortly after changes
                }

                add: null // Prevent function calls from being janky

                model: ScriptModel {
                    values: Ai.messageIDs.filter(id => {
                        const message = Ai.messageByID[id];
                        if (message === undefined || message === null) return true;
                        return (message.visibleToUser === undefined || message.visibleToUser === null) ? true : message.visibleToUser;
                    })
                }
                delegate: AiMessage {
                    required property var modelData
                    required property int index
                    messageIndex: index
                    messageData: {
                        Ai.messageByID[modelData]
                    }
                    messageInputField: root.inputField
                    enableMouseSelection: true
                }
            }

            PagePlaceholder {
                z: 2
                shown: Ai.messageIDs.length === 0
                icon: "neurology"
                title: Translation.tr("Large language models")
                description: Translation.tr("Type /key to get started with online models\nCtrl+O to expand the sidebar\nCtrl+P to detach sidebar into a window")
            }

            ScrollToBottomButton {
                z: 3
                target: messageListView
            }
        }

        DescriptionBox {
            text: (root.suggestionList[suggestions.selectedIndex] && root.suggestionList[suggestions.selectedIndex].description)
                ? root.suggestionList[suggestions.selectedIndex].description
                : ""
            showArrows: root.suggestionList.length > 1
        }

        FlowButtonGroup { // Suggestions
            id: suggestions
            visible: root.suggestionList.length > 0 && messageInputField.text.length > 0
            property int selectedIndex: 0
            Layout.fillWidth: true
            spacing: 5

            Repeater {
                id: suggestionRepeater
                model: {
                    suggestions.selectedIndex = 0
                    return root.suggestionList.slice(0, 10)
                }
                delegate: ApiCommandButton {
                    id: commandButton
                    colBackground: suggestions.selectedIndex === index ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
                    bounce: false
                    contentItem: StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                        horizontalAlignment: Text.AlignHCenter
                        text: (modelData.displayName !== undefined && modelData.displayName !== null) ? modelData.displayName : modelData.name
                    }

                    onHoveredChanged: {
                        if (commandButton.hovered) {
                            suggestions.selectedIndex = index;
                        }
                    }
                    onClicked: {
                        suggestions.acceptSuggestion(modelData.name)
                    }
                }
            }

            function acceptSuggestion(word) {
                const words = messageInputField.text.trim().split(/\s+/);
                if (words.length > 0) {
                    words[words.length - 1] = word;
                } else {
                    words.push(word);
                }
                const updatedText = words.join(" ") + " ";
                messageInputField.text = updatedText;
                messageInputField.cursorPosition = messageInputField.text.length;
                messageInputField.forceActiveFocus();
            }

            function acceptSelectedWord() {
                if (suggestions.selectedIndex >= 0 && suggestions.selectedIndex < suggestionRepeater.count) {
                    const word = root.suggestionList[suggestions.selectedIndex].name;
                    suggestions.acceptSuggestion(word);
                }
            }
        }

        Rectangle { // Input area
                id: inputWrapper
                property real spacing: 10
                Layout.fillWidth: true
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1
            implicitHeight: Math.max(inputFieldRowLayout.implicitHeight + inputFieldRowLayout.anchors.topMargin
                + commandButtonsRow.implicitHeight + commandButtonsRow.anchors.bottomMargin + spacing, 45)
                + (attachedFileIndicator.implicitHeight + spacing + attachedFileIndicator.anchors.topMargin)
            clip: true
            border.color: Appearance.colors.colOutlineVariant
            border.width: 1

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            AttachedFileIndicator {
                id: attachedFileIndicator
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: visible ? 5 : 0
                }
                filePath: Ai.pendingFilePath
                onRemove: Ai.attachFile("")
            }

            RowLayout { // Input field and send button
                id: inputFieldRowLayout
                anchors {
                    top: attachedFileIndicator.bottom
                    left: parent.left
                    right: parent.right
                    topMargin: 5
                }
                spacing: 0

                StyledTextArea { // The actual TextArea
                    id: messageInputField
                    wrapMode: TextArea.Wrap
                    Layout.fillWidth: true
                    padding: 10
                    color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                    placeholderText: Translation.tr('Message the model... "%1" for commands').arg(root?.commandPrefix ?? "/key")

                    background: null

                    onTextChanged: { // Handle suggestions
                        if (messageInputField.text.length === 0) {
                            root.suggestionQuery = ""
                            root.suggestionList = []
                            return
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}model`)) {
                            root.suggestionQuery = messageInputField.text.split(" ")[1] || ""
                            const modelResults = Fuzzy.go(root.suggestionQuery, Ai.modelList.map(model => {
                                return {
                                    name: Fuzzy.prepare(model),
                                    obj: model,
                                }
                            }), {
                                all: true,
                                key: "name"
                            })
                            root.suggestionList = modelResults.map(model => {
                                return {
                                    name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "model ") : ""}${model.target}`,
                                    displayName: `${Ai.models[model.target].name}`,
                                    description: `${Ai.models[model.target].description}`,
                                }
                            })
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}prompt`)) {
                            root.suggestionQuery = messageInputField.text.split(" ")[1] || ""
                            const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.promptFiles.map(file => {
                                return {
                                    name: Fuzzy.prepare(file),
                                    obj: file,
                                }
                            }), {
                                all: true,
                                key: "name"
                            })
                            root.suggestionList = promptFileResults.map(file => {
                                return {
                                    name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "prompt ") : ""}${file.target}`,
                                    displayName: `${FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target))}`,
                                    description: Translation.tr("Load prompt from %1").arg(file.target),
                                }
                            })
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}save`)) {
                            root.suggestionQuery = messageInputField.text.split(" ")[1] || ""
                            const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.savedChats.map(file => {
                                return {
                                    name: Fuzzy.prepare(file),
                                    obj: file,
                                }
                            }), {
                                all: true,
                                key: "name"
                            })
                            root.suggestionList = promptFileResults.map(file => {
                                const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target)).trim()
                                return {
                                    name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "save ") : ""}${chatName}`,
                                    displayName: `${chatName}`,
                                    description: Translation.tr("Save chat to %1").arg(chatName),
                                }
                            })
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}load`)) {
                            root.suggestionQuery = messageInputField.text.split(" ")[1] || ""
                            const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.savedChats.map(file => {
                                return {
                                    name: Fuzzy.prepare(file),
                                    obj: file,
                                }
                            }), {
                                all: true,
                                key: "name"
                            })
                            root.suggestionList = promptFileResults.map(file => {
                                const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target)).trim()
                                return {
                                    name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "load ") : ""}${chatName}`,
                                    displayName: `${chatName}`,
                                    description: Translation.tr(`Load chat from %1`).arg(file.target),
                                }
                            })
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}tool`)) {
                            root.suggestionQuery = messageInputField.text.split(" ")[1] || ""
                            const toolResults = Fuzzy.go(root.suggestionQuery, Ai.availableTools.map(tool => {
                                return {
                                    name: Fuzzy.prepare(tool),
                                    obj: tool,
                                }
                            }), {
                                all: true,
                                key: "name"
                            })
                            root.suggestionList = toolResults.map(tool => {
                                const toolName = tool.target
                                return {
                                    name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "tool ") : ""}${tool.target}`,
                                    displayName: toolName,
                                    description: Ai.toolDescriptions[toolName],
                                }
                            })
                        } else if(messageInputField.text.startsWith(root.commandPrefix)) {
                            root.suggestionQuery = messageInputField.text
                            root.suggestionList = root.allCommands.filter(cmd => cmd.name.startsWith(messageInputField.text.substring(1))).map(cmd => {
                                return {
                                    name: `${root.commandPrefix}${cmd.name}`,
                                    description: `${cmd.description}`,
                                }
                            })
                        }
                    }

                    function accept() {
                        root.handleInput(text)
                        text = ""
                    }

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Tab) {
                            suggestions.acceptSelectedWord();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up && suggestions.visible) {
                            suggestions.selectedIndex = Math.max(0, suggestions.selectedIndex - 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down && suggestions.visible) {
                            suggestions.selectedIndex = Math.min(root.suggestionList.length - 1, suggestions.selectedIndex + 1);
                            event.accepted = true;
                        } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
                            if (event.modifiers & Qt.ShiftModifier) {
                                // Insert newline
                                messageInputField.insert(messageInputField.cursorPosition, "\n")
                                event.accepted = true
                            } else { // Accept text
                                const inputText = messageInputField.text
                                messageInputField.clear()
                                root.handleInput(inputText)
                                event.accepted = true
                            }
                        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) { // Intercept Ctrl+V to handle image/file pasting
                            if (event.modifiers & Qt.ShiftModifier) { // Let Shift+Ctrl+V = plain paste
                                messageInputField.text += Quickshell.clipboardText
                                event.accepted = true;
                                return;
                            }
                            // Try image paste first
                            const currentClipboardEntry = Cliphist.entries[0]
                            const cleanCliphistEntry = StringUtils.cleanCliphistEntry(currentClipboardEntry)
                            if (/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(currentClipboardEntry)) { // First entry = currently copied entry = image?
                                decodeImageAndAttachProc.handleEntry(currentClipboardEntry)
                                event.accepted = true;
                                return;
                            } else if (cleanCliphistEntry.startsWith("file://")) { // First entry = currently copied entry = image?
                                const fileName = decodeURIComponent(cleanCliphistEntry)
                                Ai.attachFile(fileName);
                                event.accepted = true;
                                return;
                            }
                            event.accepted = false; // No image, let text pasting proceed
                        } else if (event.key === Qt.Key_Escape) { // Esc to detach file
                            if (Ai.pendingFilePath.length > 0) {
                                Ai.attachFile("");
                                event.accepted = true;
                            } else {
                                event.accepted = false;
                            }
                        }
                    }
                }

                RippleButton { // Send button
                    id: sendButton
                    Layout.alignment: Qt.AlignTop
                    Layout.rightMargin: 5
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.small
                    enabled: messageInputField.text.length > 0
                    toggled: enabled

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: sendButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            const inputText = messageInputField.text
                            root.handleInput(inputText)
                            messageInputField.clear()
                        }
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: Appearance.font.pixelSize.larger
                        // fill: sendButton.enabled ? 1 : 0
                        color: sendButton.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                        text: "send"
                    }
                }
            }

            RowLayout { // Controls
                id: commandButtonsRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                anchors.leftMargin: 10
                anchors.rightMargin: 5
                spacing: 4

                property var commandsShown: [
                    {
                        name: "",
                        sendDirectly: false,
                        dontAddSpace: true,
                    },
                    {
                        name: "clear",
                        sendDirectly: true,
                    },
                ]

                ApiInputBoxIndicator { // Model indicator
                    icon: "api"
                    text: Ai.getModel().name
                    tooltipText: Translation.tr("Current model: %1\nSet it with %2model MODEL")
                        .arg(Ai.getModel().name)
                        .arg(root?.commandPrefix ?? "/key")
                }

                ApiInputBoxIndicator { // Tool indicator
                    icon: "service_toolbox"
                    text: Ai.currentTool.charAt(0).toUpperCase() + Ai.currentTool.slice(1)
                    tooltipText: Translation.tr("Current tool: %1\nSet it with %2tool TOOL")
                        .arg(Ai.currentTool)
                        .arg(root?.commandPrefix ?? "/key")
                }

                Item { Layout.fillWidth: true }

                ButtonGroup { // Command buttons
                    padding: 0

                    Repeater { // Command buttons
                        model: commandButtonsRow.commandsShown
                        delegate: ApiCommandButton {
                            property string commandRepresentation: `${root.commandPrefix}${modelData.name}`
                            buttonText: commandRepresentation
                            downAction: () => {
                                if (modelData.sendDirectly) {
                                    root.handleInput(commandRepresentation)
                                } else {
                                    messageInputField.text = commandRepresentation + (modelData.dontAddSpace ? "" : " ")
                                    messageInputField.cursorPosition = messageInputField.text.length
                                    messageInputField.forceActiveFocus()
                                }
                                if (modelData.name === "clear") {
                                    messageInputField.text = ""
                                }
                            }
                        }
                    }
                }
            }

        }

    }

    // Settings window centered on screen (non-modal)
    Loader {
        id: aiSettingsLoader
        // Avoid binding loops: only control activation from state, not from item.visible
        active: root.aiSettingsOpen
        sourceComponent: FloatingWindow {
            id: settingsWin
            // Use implicit sizes to avoid deprecation warnings
            implicitWidth: 600
            implicitHeight: 560
            color: Appearance.m3colors.m3background
            visible: true

            // Show on focused monitor
            screen: (Hyprland.focusedMonitor && Hyprland.focusedMonitor.name)
                ? (Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor.name) || Quickshell.primaryScreen)
                : Quickshell.primaryScreen

            onVisibleChanged: {
                if (!visible) {
                    root.aiSettingsOpen = false
                } else {
                    // Initialize staged values from current state when opening
                    const currentName = Ai.getModel().name;
                    var idx = root.modelIds.findIndex(id => Ai.models[id].name === currentName);
                    if (idx < 0) idx = 0;
                    root.selectedModelIndex = idx;
                    root.selectedModelId = root.modelIds[idx];
                    root.pendingTemperature = Ai.temperature;
                    root.pendingApiKey = "";
                    if (apiKeyField) apiKeyField.text = ""; // avoid showing/storing keys

                    // Load prompt draft: prefer saved chat prompt; fallback to ii-Default.md
                    chatPromptReader.path = root.promptPath;
                    // default will be loaded on failure or empty
                }
            }

            Rectangle {
                id: settingsContentBg
                anchors.fill: parent
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - 12

                // Save toast
                Rectangle {
                    id: saveToast
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 12
                    radius: 8
                    color: Appearance.colors.colLayer2
                    visible: false
                    opacity: 0.95
                    implicitHeight: 34
                    implicitWidth: saveToastText.implicitWidth + 24
                    StyledText {
                        id: saveToastText
                        anchors.centerIn: parent
                        text: Translation.tr("Settings saved")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                    }
                }

                Flickable {
                    id: settingsFlick
                    anchors.fill: parent
                    clip: true
                    contentWidth: width
                    contentHeight: contentColumn.implicitHeight + 32

                    ColumnLayout {
                        id: contentColumn
                        width: settingsFlick.width - 32
                        x: 16
                        y: 16
                        spacing: 12

                    WindowDialogTitle { text: Translation.tr("AI Settings") }

                // Autosave toggle
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    StyledSwitch {
                        id: autosaveSwitch2
                        checked: root.autoSaveEnabled
                        onToggled: root.autoSaveEnabled = checked
                    }
                    StyledText { text: Translation.tr("Auto-save chat") }
                }

                // Autosave name
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText { text: Translation.tr("Autosave name") }
                    MaterialTextField {
                        text: root.autoSaveName
                        placeholderText: Translation.tr("e.g. autosave")
                        onTextChanged: root.autoSaveName = text
                    }
                }

                // Model selector
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText { text: Translation.tr("Model") }
                    ComboBox {
                        Layout.fillWidth: true
                        model: root.modelIds.map(id => Ai.models[id].name)
                        currentIndex: (function() {
                            const currentName = Ai.getModel().name;
                            const idx = root.modelIds.findIndex(id => Ai.models[id].name === currentName);
                            return idx >= 0 ? idx : 0;
                        })()
                        onActivated: (index) => {
                            root.selectedModelIndex = index;
                            root.selectedModelId = root.modelIds[index];
                            // Defer applying model until Save is clicked
                        }
                    }
                }

                // API key for current model
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText { text: Translation.tr("API key") }
                    MaterialTextField {
                        id: apiKeyField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Enter API key for %1").arg(Ai.models[root.selectedModelId]?.name || Ai.getModel().name)
                        echoMode: TextInput.Normal
                    }
                }

                // Temperature slider
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText { text: Translation.tr("Temperature") }
                    StyledSlider {
                        from: 0
                        to: 2
                        value: root.pendingTemperature
                        onValueChanged: {
                            root.pendingTemperature = value
                        }
                        stopIndicatorValues: [0, 0.5, 1, 1.5, 2]
                        tooltipContent: value.toFixed(2)
                    }
                }

                // Prompt editor (saved per chat name)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText { text: Translation.tr("System prompt for this chat") }
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 260
                        clip: true
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        MaterialTextArea {
                            id: systemPromptArea
                            Layout.fillWidth: true
                            wrapMode: TextEdit.Wrap
                            placeholderText: Translation.tr("Write a system prompt to steer the model…")
                            text: root.promptDraft
                            onTextChanged: root.promptDraft = text
                        }
                    }
                    RowLayout {
                        spacing: 8
                        RippleButton {
                            buttonText: Translation.tr("Save prompt")
                            downAction: () => {
                                Quickshell.execDetached(["bash", "-c",
                                    `mkdir -p '${Directories.defaultAiPrompts.replace(/file:\/\//, "")}'; printf %s '${StringUtils.shellSingleQuoteEscape(root.promptDraft)}' > '${root.promptPath}'`])
                                Ai.loadPrompt(root.promptPath)
                                Ai.addMessage(Translation.tr("Prompt saved for chat: %1").arg(root.autoSaveName), Ai.interfaceRole)
                            }
                        }
                        StyledText { text: FileUtils.fileNameForPath(root.promptPath); color: Appearance.colors.colSubtext }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignRight
                    Item { Layout.fillWidth: true }
                    RippleButton {
                        buttonText: Translation.tr("Close")
                        downAction: () => { settingsWin.visible = false }
                    }
                    RippleButton {
                        buttonText: Translation.tr("Save")
                        downAction: () => {
                            // Persist autosave settings (guard Persistent availability)
                            if (Persistent?.states?.ai) {
                                try {
                                    Persistent.states.ai.autoSaveEnabled = root.autoSaveEnabled
                                    Persistent.states.ai.autoSaveName = root.autoSaveName
                                } catch (e) {
                                    console.warn("[AiChat] Could not persist autosave settings:", e)
                                }
                            }

                            // Persist model and temperature
                            if (root.selectedModelId && root.selectedModelId.length > 0) {
                                if (Persistent?.states?.ai) Persistent.states.ai.model = root.selectedModelId
                                Ai.setModel(root.selectedModelId)
                            }
                            Ai.setTemperature(root.pendingTemperature)
                            if (Persistent?.states?.ai) Persistent.states.ai.temperature = root.pendingTemperature

                            // Apply API key if provided (write directly to keyring)
                            if (apiKeyField && apiKeyField.text && apiKeyField.text.trim().length > 0) {
                                const k = apiKeyField.text.trim();
                                Ai.setApiKey(k)
                                apiKeyField.text = ""; // clear after saving
                            }

                            // Save prompt to file and load
                            Quickshell.execDetached(["bash", "-c",
                                `mkdir -p '${Directories.defaultAiPrompts.replace(/file:\/\//, "")}'; printf %s '${StringUtils.shellSingleQuoteEscape(root.promptDraft)}' > '${root.promptPath}'`])
                            Ai.loadPrompt(root.promptPath)

                            // Show toast and auto-close
                            saveToast.visible = true
                            saveToastTimer.restart()
                        }
                    }
                }

                // Readers for prompts
                FileView {
                    id: chatPromptReader
                    onLoaded: {
                        if (chatPromptReader.text() && chatPromptReader.text().length > 0) {
                            root.promptDraft = chatPromptReader.text()
                        } else {
                            defaultPromptReader.path = `${Directories.defaultAiPrompts}/ii-Default.md`
                        }
                    }
                    onLoadFailed: (error) => {
                        defaultPromptReader.path = `${Directories.defaultAiPrompts}/ii-Default.md`
                    }
                }
                FileView {
                    id: defaultPromptReader
                    onLoaded: {
                        root.promptDraft = defaultPromptReader.text()
                    }
                }

                Timer {
                    id: saveToastTimer
                    interval: 700
                    repeat: false
                    onTriggered: settingsWin.visible = false
                }
            }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            }
        }
    }

}
}
