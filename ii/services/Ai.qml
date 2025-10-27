pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common.functions as CF
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "./ai/"

/**
 * Basic service to handle LLM chats. Supports Google's and OpenAI's API formats.
 * Supports Gemini and OpenAI models.
 * Limitations:
 * - For now functions only work with Gemini API format
 */
Singleton {
    id: root

    property Component aiMessageComponent: AiMessageData {}
    property Component aiModelComponent: AiModel {}
    property Component geminiApiStrategy: GeminiApiStrategy {}
    property Component openaiApiStrategy: OpenAiApiStrategy {}
    property Component mistralApiStrategy: MistralApiStrategy {}
    readonly property string interfaceRole: "interface"
    readonly property string apiKeyEnvVarName: "API_KEY"

    signal responseFinished()

    property string systemPrompt: {
        let prompt = Config.options?.ai?.systemPrompt ?? "";
        for (let key in root.promptSubstitutions) {
            // prompt = prompt.replaceAll(key, root.promptSubstitutions[key]);
            // QML/JS doesn't support replaceAll, so use split/join
            prompt = prompt.split(key).join(root.promptSubstitutions[key]);
        }
        return prompt;
    }
    // property var messages: []
    property var messageIDs: []
    property var messageByID: ({})
    readonly property var apiKeys: KeyringStorage.keyringData?.apiKeys ?? {}
    readonly property var apiKeysLoaded: KeyringStorage.loaded
    readonly property bool currentModelHasApiKey: {
        const model = models[currentModelId];
        if (!model || !model.requires_key) return true;
        if (!apiKeysLoaded) return false;
        const key = apiKeys[model.key_id];
        return (key?.length > 0);
    }
    property var postResponseHook

    property real temperature: {
        // Use stored value if available
        const stored = Persistent.states?.ai?.temperature;

        // If undefined or invalid, fall back to 1 (safe default)
        if (stored === undefined || isNaN(stored) || stored < 0 || stored > 2)
            return 1;

        return stored;
    }

    property QtObject tokenCount: QtObject {
        property int input: -1
        property int output: -1
        property int total: -1
    }

    function idForMessage(message) {
        // Generate a unique ID using timestamp and random value
        return Date.now().toString(36) + Math.random().toString(36).substr(2, 8);
    }

    function safeModelName(modelName) {
        return modelName.replace(/:/g, "_").replace(/ /g, "-").replace(/\//g, "-")
    }

    property list<var> defaultPrompts: []
    property list<var> userPrompts: []
    property list<var> promptFiles: [...defaultPrompts, ...userPrompts]
    property list<var> savedChats: []

    property var promptSubstitutions: {
        "{DISTRO}": SystemInfo.distroName,
        "{DATETIME}": `${DateTime.time}, ${DateTime.collapsedCalendarFormat}`,
        "{WINDOWCLASS}": ToplevelManager.activeToplevel?.appId ?? "Unknown",
        "{DE}": `${SystemInfo.desktopEnvironment} (${SystemInfo.windowingSystem})`
    }

    // Gemini: https://ai.google.dev/gemini-api/docs/function-calling
    // OpenAI: https://platform.openai.com/docs/guides/function-calling
    property string currentTool: Config?.options.ai.tool ?? "search"
    property var tools: {
        "gemini": {
            "functions": [{"functionDeclarations": [
                {
                    "name": "switch_to_search_mode",
                    "description": "Search the web",
                },
                {
                    "name": "get_shell_config",
                    "description": "Get the desktop shell config file contents",
                },
                {
                    "name": "set_shell_config",
                    "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "key": {
                                "type": "string",
                                "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                            },
                            "value": {
                                "type": "string",
                                "description": "The value to set, e.g. `true`"
                            }
                        },
                        "required": ["key", "value"]
                    }
                },
                {
                    "name": "run_shell_command",
                    "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "command": {
                                "type": "string",
                                "description": "The bash command to run",
                            },
                        },
                        "required": ["command"]
                    }
                },
                {
                    "name": "read_file",
                    "description": "Read the contents of a file from the filesystem using MCP. Use this when the user wants to see what's in a file.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "path": {
                                "type": "string",
                                "description": "The absolute path to the file to read"
                            }
                        },
                        "required": ["path"]
                    }
                },
                {
                    "name": "fetch_url",
                    "description": "Fetch the contents of a URL over HTTP(S) using MCP server-fetch.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "url": { "type": "string", "description": "The URL to fetch" },
                            "method": { "type": "string", "description": "HTTP method (GET, POST, etc.)", "default": "GET" },
                            "headers": { "type": "object", "description": "Optional headers as a JSON object" },
                            "body": { "description": "Optional request body; string or JSON-serializable value" }
                        },
                        "required": ["url"]
                    }
                },
                {
                    "name": "write_memory",
                    "description": "Store a memory note using MCP server-memory.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "text": { "type": "string", "description": "The content to remember" },
                            "namespace": { "type": "string", "description": "Optional namespace or topic" },
                            "metadata": { "type": "object", "description": "Optional metadata object" }
                        },
                        "required": ["text"]
                    }
                },
                {
                    "name": "search_memory",
                    "description": "Search stored memories using MCP server-memory.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "query": { "type": "string", "description": "Search query" },
                            "top_k": { "type": "number", "description": "Number of results", "default": 5 },
                            "namespace": { "type": "string", "description": "Optional namespace filter" }
                        },
                        "required": ["query"]
                    }
                },
            ]}],
            "search": [{
                "google_search": {}
            }],
            "none": []
        },
        "openai": {
            "functions": [
                {
                    "type": "function",
                    "function": {
                        "name": "get_shell_config",
                        "description": "Get the desktop shell config file contents",
                        "parameters": {}
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "set_shell_config",
                        "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "key": {
                                    "type": "string",
                                    "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                                },
                                "value": {
                                    "type": "string",
                                    "description": "The value to set, e.g. `true`"
                                }
                            },
                            "required": ["key", "value"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "run_shell_command",
                        "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "command": {
                                    "type": "string",
                                    "description": "The bash command to run",
                                },
                            },
                            "required": ["command"]
                        }
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "fetch_url",
                        "description": "Fetch the contents of a URL over HTTP(S) using MCP server-fetch.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "url": { "type": "string", "description": "The URL to fetch" },
                                "method": { "type": "string", "description": "HTTP method (GET, POST, etc.)", "default": "GET" },
                                "headers": { "type": "object", "description": "Optional headers as a JSON object" },
                                "body": { "description": "Optional request body; string or JSON-serializable value" }
                            },
                            "required": ["url"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "write_memory",
                        "description": "Store a memory note using MCP server-memory.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "text": { "type": "string", "description": "The content to remember" },
                                "namespace": { "type": "string", "description": "Optional namespace or topic" },
                                "metadata": { "type": "object", "description": "Optional metadata object" }
                            },
                            "required": ["text"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "search_memory",
                        "description": "Search stored memories using MCP server-memory.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "query": { "type": "string", "description": "Search query" },
                                "top_k": { "type": "number", "description": "Number of results", "default": 5 },
                                "namespace": { "type": "string", "description": "Optional namespace filter" }
                            },
                            "required": ["query"]
                        }
                    }
                },
            ],
            "search": [],
            "none": [],
        },
        "mistral": {
            "functions": [
                {
                    "type": "function",
                    "function": {
                        "name": "get_shell_config",
                        "description": "Get the desktop shell config file contents",
                        "parameters": {}
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "set_shell_config",
                        "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "key": {
                                    "type": "string",
                                    "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                                },
                                "value": {
                                    "type": "string",
                                    "description": "The value to set, e.g. `true`"
                                }
                            },
                            "required": ["key", "value"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "run_shell_command",
                        "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "command": {
                                    "type": "string",
                                    "description": "The bash command to run",
                                },
                            },
                            "required": ["command"]
                        }
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "fetch_url",
                        "description": "Fetch the contents of a URL over HTTP(S) using MCP server-fetch.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "url": { "type": "string", "description": "The URL to fetch" },
                                "method": { "type": "string", "description": "HTTP method (GET, POST, etc.)", "default": "GET" },
                                "headers": { "type": "object", "description": "Optional headers as a JSON object" },
                                "body": { "description": "Optional request body; string or JSON-serializable value" }
                            },
                            "required": ["url"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "write_memory",
                        "description": "Store a memory note using MCP server-memory.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "text": { "type": "string", "description": "The content to remember" },
                                "namespace": { "type": "string", "description": "Optional namespace or topic" },
                                "metadata": { "type": "object", "description": "Optional metadata object" }
                            },
                            "required": ["text"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "search_memory",
                        "description": "Search stored memories using MCP server-memory.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "query": { "type": "string", "description": "Search query" },
                                "top_k": { "type": "number", "description": "Number of results", "default": 5 },
                                "namespace": { "type": "string", "description": "Optional namespace filter" }
                            },
                            "required": ["query"]
                        }
                    }
                },
            ],
            "search": [],
            "none": [],
        }
    }
    property list<var> availableTools: Object.keys(root.tools[models[currentModelId]?.api_format])
    property var toolDescriptions: {
        "functions": Translation.tr("Commands, edit configs, search.\nTakes an extra turn to switch to search mode if that's needed"),
        "search": Translation.tr("Gives the model search capabilities (immediately)"),
        "none": Translation.tr("Disable tools")
    }

    // Model properties:
    // - name: Name of the model
    // - icon: Icon name of the model
    // - description: Description of the model
    // - endpoint: Endpoint of the model
    // - model: Model name of the model
    // - requires_key: Whether the model requires an API key
    // - key_id: The identifier of the API key. Use the same identifier for models that can be accessed with the same key.
    // - key_get_link: Link to get an API key
    // - key_get_description: Description of pricing and how to get an API key
    // - api_format: The API format of the model. Can be "openai" or "gemini". Default is "openai".
    // - extraParams: Extra parameters to be passed to the model. This is a JSON object.
    property var models: Config.options.policies.ai === 2 ? {} : {
        "openai-gpt-5-mini": aiModelComponent.createObject(this, {
            "name": "GPT-5 Mini (OP Models)",
            "icon": "openai-symbolic",
            "description": Translation.tr("Online | %1's model\nLatest OpenAI model with high reasoning and coding performance Trained by CjLogic.").arg("OpenAI"),
            "homepage": "https://platform.openai.com",
            "endpoint": "https://api.openai.com/v1/chat/completions",
            "model": "gpt-5-mini",
            "requires_key": true,
            "fixed_temperature": 1,
            "key_id": "openai",
            "key_get_link": "https://platform.openai.com/api-keys",
            "key_get_description": Translation.tr("**Pricing**: pay-as-you-go. Data not used for training.\n\n**Instructions**: Log into OpenAI, create a new API key, then set it with `/key set openai <your_key>`"),
            "api_format": "openai",
}),
        "gemini-2.0-flash": aiModelComponent.createObject(this, {
            "name": "Gemini 2.0 Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nFast, can perform searches for up-to-date information"),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:streamGenerateContent",
            "model": "gemini-2.0-flash",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            "api_format": "gemini",
        }),
        "gemini-2.5-flash": aiModelComponent.createObject(this, {
            "name": "Gemini 2.5 Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nNewer model that's slower than its predecessor but should deliver higher quality answers"),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent",
            "model": "gemini-2.5-flash",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            "api_format": "gemini",
        }),
        "gemini-2.5-flash-pro": aiModelComponent.createObject(this, {
            "name": "Gemini 2.5 Pro",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nGoogle's state-of-the-art multipurpose model that excels at coding and complex reasoning tasks."),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:streamGenerateContent",
            "model": "gemini-2.5-pro",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            "api_format": "gemini",
        }),
        "gemini-2.5-flash-lite": aiModelComponent.createObject(this, {
            "name": "Gemini 2.5 Flash-Lite",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nA Gemini 2.5 Flash model optimized for cost-efficiency and high throughput."),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:streamGenerateContent",
            "model": "gemini-2.5-flash-lite",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            "api_format": "gemini",
        }),
        "mistral-medium-3": aiModelComponent.createObject(this, {
            "name": "Mistral Medium 3",
            "icon": "mistral-symbolic",
            "description": Translation.tr("Online | %1's model | Delivers fast, responsive and well-formatted answers. Disadvantages: not very eager to do stuff; might make up unknown function calls").arg("Mistral"),
            "homepage": "https://mistral.ai/news/mistral-medium-3",
            "endpoint": "https://api.mistral.ai/v1/chat/completions",
            "model": "mistral-medium-2505",
            "requires_key": true,
            "key_id": "mistral",
            "key_get_link": "https://console.mistral.ai/api-keys",
            "key_get_description": Translation.tr("**Instructions**: Log into Mistral account, go to Keys on the sidebar, click Create new key"),
            "api_format": "mistral",
        }),
        "openrouter-deepseek-r1": aiModelComponent.createObject(this, {
            "name": "DeepSeek R1",
            "icon": "deepseek-symbolic",
            "description": Translation.tr("Online via %1 | %2's model").arg("OpenRouter").arg("DeepSeek"),
            "homepage": "https://openrouter.ai/deepseek/deepseek-r1:free",
            "endpoint": "https://openrouter.ai/api/v1/chat/completions",
            "model": "deepseek/deepseek-r1:free",
            "requires_key": true,
            "key_id": "openrouter",
            "key_get_link": "https://openrouter.ai/settings/keys",
            "key_get_description": Translation.tr("**Pricing**: free. Data use policy varies depending on your OpenRouter account settings.\n\n**Instructions**: Log into OpenRouter account, go to Keys on the topright menu, click Create API Key"),
        }),
    }
    property var modelList: Object.keys(root.models)
    property var currentModelId: Persistent.states?.ai?.model || modelList[0]
    onCurrentModelIdChanged: {
        // Ensure we re-select the model when Persistent becomes available
        setModel(currentModelId, false, false);
    }

    property var apiStrategies: {
        "openai": openaiApiStrategy.createObject(this),
        "gemini": geminiApiStrategy.createObject(this),
        "mistral": mistralApiStrategy.createObject(this),
    }
    property ApiStrategy currentApiStrategy: apiStrategies[models[currentModelId]?.api_format || "openai"]
    // MCP servers configuration (for future tool integration)
    property var mcpServers: Persistent.states?.ai?.mcpServers ?? []

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return;
            (Config?.options.ai?.extraModels ?? []).forEach(model => {
                const safeModelName = root.safeModelName(model["model"]);
                root.addModel(safeModelName, model)
            });
        }
    }

    property string requestScriptFilePath: "/tmp/quickshell/ai/request.sh"
    property string pendingFilePath: ""

    Component.onCompleted: {
        setModel(currentModelId, false, false); // Do necessary setup for model
    }

    function guessModelLogo(model) {
        if (model.includes("llama")) return "ollama-symbolic";
        if (model.includes("gemma")) return "google-gemini-symbolic";
        if (model.includes("deepseek")) return "deepseek-symbolic";
        if (/^phi\d*:/i.test(model)) return "microsoft-symbolic";
        return "ollama-symbolic";
    }

    function guessModelName(model) {
        const replaced = model.replace(/-/g, ' ').replace(/:/g, ' ');
        let words = replaced.split(' ');
        words[words.length - 1] = words[words.length - 1].replace(/(\d+)b$/, (_, num) => `${num}B`)
        words = words.map((word) => {
            return (word.charAt(0).toUpperCase() + word.slice(1))
        });
        if (words[words.length - 1] === "Latest") words.pop();
        else words[words.length - 1] = `(${words[words.length - 1]})`; // Surround the last word with square brackets
        const result = words.join(' ');
        return result;
    }

    function addModel(modelName, data) {
        root.models[modelName] = aiModelComponent.createObject(this, data);
    }

    Process {
        id: getOllamaModels
        running: true
        command: ["bash", "-c", `${Directories.scriptPath}/ai/show-installed-ollama-models.sh`.replace(/file:\/\//, "")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    if (data.length === 0) return;
                    const dataJson = JSON.parse(data);
                    root.modelList = [...root.modelList, ...dataJson];
                    dataJson.forEach(model => {
                        const safeModelName = root.safeModelName(model);
                        root.addModel(safeModelName, {
                            "name": guessModelName(model),
                            "icon": guessModelLogo(model),
                            "description": Translation.tr("Local Ollama model | %1").arg(model),
                            "homepage": `https://ollama.com/library/${model}`,
                            "endpoint": "http://localhost:11434/v1/chat/completions",
                            "model": model,
                            "requires_key": false,
                        })
                    });

                    root.modelList = Object.keys(root.models);

                } catch (e) {
                    console.log("Could not fetch Ollama models:", e);
                }
            }
        }
    }

    Process {
        id: getDefaultPrompts
        running: true
        command: ["ls", "-1", Directories.defaultAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.defaultPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.defaultAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getUserPrompts
        running: true
        command: ["ls", "-1", Directories.userAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.userPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.userAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getSavedChats
        running: true
        command: ["ls", "-1", Directories.aiChats]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.savedChats = text.split("\n")
                    .filter(fileName => fileName.endsWith(".json"))
                    .map(fileName => `${Directories.aiChats}/${fileName}`)
            }
        }
    }

    FileView {
        id: promptLoader
        watchChanges: false;
        onLoadedChanged: {
            if (!promptLoader.loaded) return;
            Config.options.ai.systemPrompt = promptLoader.text();
            // Show a single visible greeting message
            root.clearMessages();
            root.addMessage("System prompt loaded.. Good day Logic, how can i help you today?", root.interfaceRole, true);
        }
    }

    function printPrompt() {
        root.addMessage(Translation.tr("The current system prompt is\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
    }

    function loadPrompt(filePath) {
        promptLoader.path = "" // Unload
        promptLoader.path = filePath; // Load
        promptLoader.reload();
    }

    function addMessage(message, role, visible = true) {
        if (message.length === 0) return;
        const aiMessage = aiMessageComponent.createObject(root, {
            "role": role,
            "content": message,
            "rawContent": message,
            "thinking": false,
            "done": true,
        });
        aiMessage.visibleToUser = visible;
        const id = idForMessage(aiMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
    }

    function removeMessage(index) {
        if (index < 0 || index >= messageIDs.length) return;
        const id = root.messageIDs[index];
        root.messageIDs.splice(index, 1);
        root.messageIDs = [...root.messageIDs];
        delete root.messageByID[id];
    }

    function addApiKeyAdvice(model) {
        root.addMessage(
            Translation.tr('To set an API key, pass it with the %4 command\n\nTo view the key, pass "get" with the command<br/>\n\n### For %1:\n\n**Link**: %2\n\n%3')
                .arg(model.name).arg(model.key_get_link).arg(model.key_get_description ?? Translation.tr("<i>No further instruction provided</i>")).arg("/key"),
            Ai.interfaceRole,
            false
        );
    }

    function getModel() {
        return models[currentModelId];
    }

   function setModel(modelId, feedback = true, setPersistentState = true) {
    if (!modelId) modelId = "";
    modelId = modelId.toLowerCase();

    if (modelList.indexOf(modelId) !== -1) {
        const model = models[modelId];

        if (model?.requires_key)
            KeyringStorage.fetchKeyringData();

        if (Config.options.policies.ai === 2 && !model.endpoint.includes("localhost")) {
            root.addMessage(
                Translation.tr("Online models disallowed\n\nControlled by `policies.ai` config option"),
                root.interfaceRole
            );
            return;
        }

        if (setPersistentState)
            Persistent.states.ai.model = modelId;

        // Handle temperature recheck
        const fixedTemp = model.fixed_temperature;
        let desiredTemp = Persistent.states?.ai?.temperature ?? 1;

        if (fixedTemp !== undefined) {
            desiredTemp = fixedTemp;
            root.addMessage(
                Translation.tr("%1 enforces temperature = %2")
                    .arg(model.name)
                    .arg(fixedTemp),
                Ai.interfaceRole,
                false
            );
        } else if (desiredTemp < 0 || desiredTemp > 2) {
            desiredTemp = 1;
        }

        root.setTemperature(desiredTemp);

        // 🔁 Sync immediately for next request
        Persistent.states.ai.temperature = desiredTemp;
        root.temperature = desiredTemp;

        if (feedback)
            root.addMessage(
                Translation.tr("Model set to %1 (Temp: %2)")
                    .arg(model.name)
                    .arg(desiredTemp),
                root.interfaceRole,
                false
            );

        if (model.requires_key) {
            if (root.apiKeysLoaded &&
                (!root.apiKeys[model.key_id] ||
                 root.apiKeys[model.key_id].length === 0))
                root.addApiKeyAdvice(model);
        }

        // 🔧 Update API strategy
        root.currentApiStrategy = root.apiStrategies[model.api_format || "openai"];

        // Optional auto-refresh
        if (root.messageIDs.length > 0) {
            root.addMessage(Translation.tr("Re-syncing model context..."), root.interfaceRole, false);
            requester.makeRequest();
        }

    } else {
        if (feedback)
            root.addMessage(
                Translation.tr("Invalid model. Supported: \n```\n") +
                    modelList.join("\n```\n```\n"),
                Ai.interfaceRole
            ) + "\n```";
    }
}




    function setTool(tool) {
        if (!root.tools[models[currentModelId]?.api_format] || !(tool in root.tools[models[currentModelId]?.api_format])) {
            root.addMessage(Translation.tr("Invalid tool. Supported tools:\n- %1").arg(root.availableTools.join("\n- ")), root.interfaceRole);
            return false;
        }
        Config.options.ai.tool = tool;
        return true;
    }

    function getTemperature() {
        return root.temperature;
    }

    function setTemperature(value) {
    const model = models[currentModelId];
    const fixedTemp = model.fixed_temperature; // e.g., 1 if the model locks it

    // Handle models with fixed temperature
        if (fixedTemp !== undefined) {
        if (value !== fixedTemp) {
            root.addMessage(
                Translation.tr("%1 only supports temperature = %2. Automatically set.")
                    .arg(model.name)
                    .arg(fixedTemp),
                Ai.interfaceRole,
                false
            );
        }
        value = fixedTemp;
    }

    // Validate range
    if (isNaN(value) || value < 0 || value > 2) {
        root.addMessage(Translation.tr("Temperature must be between 0 and 2"), Ai.interfaceRole, false);
        return;
    }

    // Save and notify
    Persistent.states.ai.temperature = value;
    root.temperature = value;
    root.addMessage(Translation.tr("Temperature set to %1").arg(value), Ai.interfaceRole, false);
    console.log("Sending model:", currentModelId, "temp:", root.temperature)

}



    function setApiKey(key) {
        const model = models[currentModelId];
        if (!model.requires_key) {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole, false);
            return;
        }
        if (!key || key.length === 0) {
            const model = models[currentModelId];
            root.addApiKeyAdvice(model)
            return;
        }
        KeyringStorage.setNestedField(["apiKeys", model.key_id], key.trim());
        root.addMessage(Translation.tr("API key set for %1").arg(model.name), Ai.interfaceRole, false);
    }

    function printApiKey() {
        const model = models[currentModelId];
        if (model.requires_key) {
            const key = root.apiKeys[model.key_id];
            if (key) {
                root.addMessage(Translation.tr("API key:\n\n```txt\n%1\n```").arg(key), Ai.interfaceRole);
            } else {
                root.addMessage(Translation.tr("No API key set for %1").arg(model.name), Ai.interfaceRole);
            }
        } else {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
        }
    }

    function printTemperature() {
        root.addMessage(Translation.tr("Temperature: %1").arg(root.temperature), Ai.interfaceRole);
    }

    function clearMessages() {
        root.messageIDs = [];
        root.messageByID = ({});
        root.tokenCount.input = -1;
        root.tokenCount.output = -1;
        root.tokenCount.total = -1;
    }

    FileView {
        id: requesterScriptFile
    }

    Process {
        id: requester
        property list<string> baseCommand: ["bash"]
        property AiMessageData message
        property ApiStrategy currentStrategy

        function markDone() {
            requester.message.done = true;
            if (root.postResponseHook) {
                root.postResponseHook();
                root.postResponseHook = null; // Reset hook after use
            }
            root.saveChat("lastSession")
            root.responseFinished()
        }

        function makeRequest() {
            const model = models[currentModelId];
            requester.currentStrategy = root.currentApiStrategy;
            requester.currentStrategy.reset(); // Reset strategy state

            /* Put API key in environment variable */
            if (model.requires_key) requester.environment[`${root.apiKeyEnvVarName}`] = root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : ""

            /* Build endpoint, request data */
            const endpoint = root.currentApiStrategy.buildEndpoint(model);
            const messageArray = root.messageIDs.map(id => root.messageByID[id]);
            const filteredMessageArray = messageArray.filter(message => message.role !== Ai.interfaceRole);
            const data = root.currentApiStrategy.buildRequestData(model, filteredMessageArray, root.systemPrompt, root.temperature, root.tools[model.api_format][root.currentTool], root.pendingFilePath);
            // console.log("[Ai] Request data: ", JSON.stringify(data, null, 2));

            let requestHeaders = {
                "Content-Type": "application/json",
            }

            /* Create local message object */
            requester.message = root.aiMessageComponent.createObject(root, {
                "role": "assistant",
                "model": currentModelId,
                "content": "",
                "rawContent": "",
                "thinking": true,
                "done": false,
            });
            const id = idForMessage(requester.message);
            root.messageIDs = [...root.messageIDs, id];
            root.messageByID[id] = requester.message;

            /* Build header string for curl */
            let headerString = Object.entries(requestHeaders)
                .filter(([k, v]) => v && v.length > 0)
                .map(([k, v]) => `-H '${k}: ${v}'`)
                .join(' ');

            // console.log("Request headers: ", JSON.stringify(requestHeaders));
            // console.log("Header string: ", headerString);

            /* Get authorization header from strategy */
            const authHeader = requester.currentStrategy.buildAuthorizationHeader(root.apiKeyEnvVarName);

            /* Script shebang */
            const scriptShebang = "#!/usr/bin/env bash\n";

            /* Create extra setup when there's an attached file */
            let scriptFileSetupContent = ""
            if (root.pendingFilePath && root.pendingFilePath.length > 0) {
                requester.message.localFilePath = root.pendingFilePath;
                scriptFileSetupContent = requester.currentStrategy.buildScriptFileSetup(root.pendingFilePath);
                root.pendingFilePath = ""
            }

            /* Create command string */
            let scriptRequestContent = ""
            scriptRequestContent += `curl --no-buffer "${endpoint}"`
                + ` ${headerString}`
                + (authHeader ? ` ${authHeader}` : "")
                + ` --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'`
                + "\n"

            /* Send the request */
            const scriptContent = requester.currentStrategy.finalizeScriptContent(scriptShebang + scriptFileSetupContent + scriptRequestContent)
            const shellScriptPath = CF.FileUtils.trimFileProtocol(root.requestScriptFilePath)
            requesterScriptFile.path = Qt.resolvedUrl(shellScriptPath)
            requesterScriptFile.setText(scriptContent)
            requester.command = baseCommand.concat([shellScriptPath]);
            requester.running = true
        }

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                if (requester.message.thinking) requester.message.thinking = false;
                // console.log("[Ai] Raw response line: ", data);

                // Handle response line
                try {
                    const result = requester.currentStrategy.parseResponseLine(data, requester.message);
                    // console.log("[Ai] Parsed response result: ", JSON.stringify(result, null, 2));

                    if (result.functionCall) {
                        requester.message.functionCall = result.functionCall;
                        root.handleFunctionCall(result.functionCall.name, result.functionCall.args, requester.message);
                    }
                    if (result.tokenUsage) {
                        root.tokenCount.input = result.tokenUsage.input;
                        root.tokenCount.output = result.tokenUsage.output;
                        root.tokenCount.total = result.tokenUsage.total;
                    }
                    if (result.finished) {
                        requester.markDone();
                    }

                } catch (e) {
                    console.log("[AI] Could not parse response: ", e);
                    requester.message.rawContent += data;
                    requester.message.content += data;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            const result = requester.currentStrategy.onRequestFinished(requester.message);

            if (result.finished) {
                requester.markDone();
            } else if (!requester.message.done) {
                requester.markDone();
            }

            // Handle error responses
            if (requester.message.content.includes("API key not valid")) {
                root.addApiKeyAdvice(models[requester.message.model]);
            }
        }
    }

    function sendUserMessage(message) {
        if (message.length === 0) return;
        root.addMessage(message, "user");
        requester.makeRequest();
    }

    function attachFile(filePath: string) {
        root.pendingFilePath = CF.FileUtils.trimFileProtocol(filePath);
    }

    function createFunctionOutputMessage(name, output, includeOutputInChat = true) {
        return aiMessageComponent.createObject(root, {
            "role": "user",
            "content": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "rawContent": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "functionName": name,
            "functionResponse": output,
            "thinking": false,
            "done": true,
            // "visibleToUser": false,
        });
    }

    function addFunctionOutputMessage(name, output) {
        const aiMessage = createFunctionOutputMessage(name, output);
        const id = idForMessage(aiMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
    }

    function rejectCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"
        addFunctionOutputMessage(message.functionName, Translation.tr("Command rejected by user"))
    }

    function approveCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"

        const responseMessage = createFunctionOutputMessage(message.functionName, "", false);
        const id = idForMessage(responseMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = responseMessage;

        commandExecutionProc.message = responseMessage;
        commandExecutionProc.baseMessageContent = responseMessage.content;
        commandExecutionProc.shellCommand = message.functionCall.args.command;
        commandExecutionProc.running = true; // Start the command execution
    }

    Process {
        id: commandExecutionProc
        property string shellCommand: ""
        property AiMessageData message
        property string baseMessageContent: ""
        command: ["bash", "-c", shellCommand]
        stdout: SplitParser {
            onRead: (output) => {
                commandExecutionProc.message.functionResponse += output + "\n\n";
                const updatedContent = commandExecutionProc.baseMessageContent + `\n\n<think>\n<tt>${commandExecutionProc.message.functionResponse}</tt>\n</think>`;
                commandExecutionProc.message.rawContent = updatedContent;
                commandExecutionProc.message.content = updatedContent;
            }
        }
        onExited: (exitCode, exitStatus) => {
            commandExecutionProc.message.functionResponse += `[[ Command exited with code ${exitCode} (${exitStatus}) ]]\n`;
            requester.makeRequest(); // Continue
        }
    }

    // Process to call filesystem MCP server
    Process {
        id: filesystemMcpProc
        property string filePath: ""
        property string functionName: ""
        command: ["bash", "-c", `(
            echo '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"quickshell","version":"1.0"}},"id":0}'
            echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"read_file","arguments":{"path":"${filePath}"}},"id":1}'
        ) | env npm_config_loglevel=silent npx -y @modelcontextprotocol/server-filesystem@latest /home 2>/dev/null | node -e 'let b="";process.stdin.setEncoding("utf8");process.stdin.on("data",d=>b+=d);process.stdin.on("end",()=>{b=b.split("\\r").join("");const ls=b.split("\\n").filter(l=>l.startsWith("{\"jsonrpc\"")&&l.includes("\"id\":1"));console.log(ls.length?ls[ls.length-1]:"");});'`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    // Parse MCP response (last line only)
                    const lines = text.trim().split('\n');
                    let response = null;
                    for (let i = lines.length - 1; i >= 0; i--) {
                        try { response = JSON.parse(lines[i]); break; } catch (e2) { /* skip non-JSON lines */ }
                    }
                    if (!response) throw new Error('No JSON-RPC response found');

                    if (response.result && response.result.content) {
                        const content = response.result.content[0];
                        if (content.type === "text") {
                            addFunctionOutputMessage(filesystemMcpProc.functionName, `File contents:\n\n${content.text}`);
                        }
                    } else if (response.error) {
                        addFunctionOutputMessage(filesystemMcpProc.functionName, `Error: ${response.error.message}`);
                    } else {
                        addFunctionOutputMessage(filesystemMcpProc.functionName, `Unexpected response: ${JSON.stringify(response).substring(0, 200)}`);
                    }
                } catch (e) {
                    addFunctionOutputMessage(filesystemMcpProc.functionName, `Failed to parse response. Raw: ${text.substring(0, 300)}... Error: ${e}`);
                }
                requester.makeRequest(); // Continue conversation
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("[Filesystem MCP stderr]", text);
                }
            }
        }
    }

    // Direct fetch (no MCP dependency)
    Process {
        id: fetchDirectProc
        property string functionName: ""
        property string url: ""
        property string method: "GET"
        property string headersJson: "{}"
        property string bodyJson: "null"
        command: ["bash", "-lc", `
            URL=${CF.StringUtils.shellSingleQuoteEscape(url)};
            METHOD=${CF.StringUtils.shellSingleQuoteEscape(method)};
            HDRS=${CF.StringUtils.shellSingleQuoteEscape(headersJson)};
            BODY=${CF.StringUtils.shellSingleQuoteEscape(bodyJson)};
            # Build header flags from JSON
            HDRFLAGS=$(jq -r 'to_entries|map("-H \""+ .key + ": " + ( .value|tostring ) + "\"")|.[]' <<< "$HDRS" 2>/dev/null | tr '\n' ' ');
            # Always ask for JSON unless caller overrides
            case "$HDRFLAGS" in (*"Accept:"*) : ;; (*) HDRFLAGS="$HDRFLAGS -H 'Accept: application/json'" ;; esac
            # Make request
            if [ "$METHOD" = "GET" ] || [ "$BODY" = "null" ]; then
              RESP=$(eval curl --fail-with-body -sS -L "$URL" $HDRFLAGS) || { echo "ERROR: HTTP error"; exit 0; }
            else
              RESP=$(eval curl --fail-with-body -sS -L -X "$METHOD" $HDRFLAGS --data @<(printf %s "$BODY")) || { echo "ERROR: HTTP error"; exit 0; }
            fi
            # Ensure JSON only
            if jq -e . >/dev/null 2>&1 <<< "$RESP"; then
              echo "$RESP"
            else
              echo "ERROR: Non-JSON response"
            fi
        `]
        stdout: StdioCollector { onStreamFinished: { addFunctionOutputMessage(fetchDirectProc.functionName, text.substring(0, 200000)); requester.makeRequest(); } }
        stderr: StdioCollector { onStreamFinished: { if (text.length>0) addFunctionOutputMessage(fetchDirectProc.functionName, `Error: ${text.substring(0, 500)}`); } }
    }

    // Simple local memory store (no MCP dependency)
    FileView { id: memoryFile; path: `${Directories.aiChats}/memory.json`; blockLoading: true }
    function ensureMemoryFile() {
        try {
            memoryFile.reload();
            const t = memoryFile.text();
            if (!t || t.trim().length===0) memoryFile.setText("[]");
        } catch (e) { memoryFile.setText("[]"); }
    }
    function memoryWrite(text, namespace, metadata) {
        ensureMemoryFile();
        const raw = memoryFile.text();
        let arr = [];
        try { arr = JSON.parse(raw); } catch (e) { arr = []; }
        arr.push({ text, namespace, metadata, ts: Date.now() });
        memoryFile.setText(JSON.stringify(arr));
        return "Saved to memory.";
    }
    function memorySearch(query, top_k, namespace) {
        ensureMemoryFile();
        const raw = memoryFile.text();
        let arr = [];
        try { arr = JSON.parse(raw); } catch (e) { arr = []; }
        const q = (query||"").toLowerCase();
        const results = arr.filter(it => (!namespace || it.namespace===namespace) && (it.text||"").toLowerCase().includes(q)).slice(0, top_k||5);
        return results.map(r => `- ${new Date(r.ts).toISOString()}: ${r.text}`).join("\n");
    }

    function handleFunctionCall(name, args: var, message: AiMessageData) {
        if (name === "switch_to_search_mode") {
            const modelId = root.currentModelId;
            root.currentTool = "search"
            root.postResponseHook = () => { root.currentTool = "functions" }
            addFunctionOutputMessage(name, Translation.tr("Switched to search mode. Continue with the user's request."))
            requester.makeRequest();
        } else if (name === "get_shell_config") {
            const configJson = CF.ObjectUtils.toPlainObject(Config.options)
            addFunctionOutputMessage(name, JSON.stringify(configJson));
            requester.makeRequest();
        } else if (name === "set_shell_config") {
            if (!args.key || !args.value) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `key` and `value`."));
                return;
            }
            const key = args.key;
            const value = args.value;
            Config.setNestedValue(key, value);
        } else if (name === "run_shell_command") {
            if (!args.command || args.command.length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `command`."));
                return;
            }
            const contentToAppend = `\n\n**Command execution request**\n\n\`\`\`command\n${args.command}\n\`\`\``;
            message.rawContent += contentToAppend;
            message.content += contentToAppend;
            message.functionPending = true; // Use thinking to indicate the command is waiting for approval
        } else if (name === "read_file") {
            if (!args.path || args.path.length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `path`."));
                requester.makeRequest();
                return;
            }
            // Call the filesystem MCP server
            filesystemMcpProc.filePath = args.path;
            filesystemMcpProc.functionName = name;
            filesystemMcpProc.running = true;
        } else if (name === "fetch_url") {
            if (!args.url || args.url.length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `url`."));
                requester.makeRequest();
                return;
            }
            fetchDirectProc.functionName = name;
            fetchDirectProc.url = args.url;
            fetchDirectProc.method = args.method ?? "GET";
            try { fetchDirectProc.headersJson = JSON.stringify(args.headers ?? {}); } catch (e) { fetchDirectProc.headersJson = "{}"; }
            try { fetchDirectProc.bodyJson = (args.body === undefined) ? "null" : JSON.stringify(args.body); } catch (e) { fetchDirectProc.bodyJson = "null"; }
            fetchDirectProc.running = true;
        } else if (name === "write_memory") {
            if (!args.text || args.text.length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `text`."));
                requester.makeRequest();
                return;
            }
            const msg = memoryWrite(args.text, args.namespace, args.metadata);
            addFunctionOutputMessage(name, msg);
            requester.makeRequest();
        } else if (name === "search_memory") {
            if (!args.query || args.query.length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `query`."));
                requester.makeRequest();
                return;
            }
            const out = memorySearch(args.query, args.top_k ?? 5, args.namespace);
            addFunctionOutputMessage(name, out.length ? out : "No matches.");
            requester.makeRequest();
        }
        else root.addMessage(Translation.tr("Unknown function call: %1").arg(name), "assistant");
    }

    function chatToJson() {
        return root.messageIDs.map(id => {
            const message = root.messageByID[id]
            return ({
                "role": message.role,
                "rawContent": message.rawContent,
                "fileMimeType": message.fileMimeType,
                "fileUri": message.fileUri,
                "localFilePath": message.localFilePath,
                "model": message.model,
                "thinking": false,
                "done": true,
                "annotations": message.annotations,
                "annotationSources": message.annotationSources,
                "functionName": message.functionName,
                "functionCall": message.functionCall,
                "functionResponse": message.functionResponse,
                "visibleToUser": message.visibleToUser,
            })
        })
    }

    FileView {
        id: chatSaveFile
        property string chatName: ""
        path: chatName.length > 0 ? `${Directories.aiChats}/${chatName}.json` : ""
        blockLoading: true // Prevent race conditions
    }

    /**
     * Saves chat to a JSON list of message objects.
     * @param chatName name of the chat
     */
    function saveChat(chatName) {
        chatSaveFile.chatName = chatName.trim()
        const saveContent = JSON.stringify(root.chatToJson())
        chatSaveFile.setText(saveContent)
        getSavedChats.running = true;
    }

    /**
     * Loads chat from a JSON list of message objects
     * @param chatName name of the chat
     */
    function loadChat(chatName) {
        try {
            chatSaveFile.chatName = chatName.trim()
            chatSaveFile.reload()
            const saveContent = chatSaveFile.text()
            // console.log(saveContent)
            const saveData = JSON.parse(saveContent)
            root.clearMessages()
            root.messageIDs = saveData.map((_, i) => {
                return i
            })
            // console.log(JSON.stringify(messageIDs))
            for (let i = 0; i < saveData.length; i++) {
                const message = saveData[i];
                root.messageByID[i] = root.aiMessageComponent.createObject(root, {
                    "role": message.role,
                    "rawContent": message.rawContent,
                    "content": message.rawContent,
                    "fileMimeType": message.fileMimeType,
                    "fileUri": message.fileUri,
                    "localFilePath": message.localFilePath,
                    "model": message.model,
                    "thinking": message.thinking,
                    "done": message.done,
                    "annotations": message.annotations,
                    "annotationSources": message.annotationSources,
                    "functionName": message.functionName,
                    "functionCall": message.functionCall,
                    "functionResponse": message.functionResponse,
                    "visibleToUser": message.visibleToUser,
                });
            }
        } catch (e) {
            console.log("[AI] Could not load chat: ", e);
        } finally {
            getSavedChats.running = true;
        }
    }
}
