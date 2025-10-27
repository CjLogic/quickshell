# Changes and updates (2025-10-27)

This document summarizes modifications to the Quickshell AI sidebar and related services.

## Highlights

- Sessions start fresh; autosave overwrites the current session.
- Suppressed status spam; only one greeting shows after prompt load.
- fetch_url now JSON-only via direct curl; memory tools use local storage.
- Filesystem tool unchanged.
- Added settings window capabilities and OpenAI support; UI/UX tweaks and backend hardening.

---

## What changed (functional)

1) Session behavior and autosave

- On chat open, messages are cleared (no stacking).
- Autosave continues to overwrite the same chat name.

2) Interface message visibility

- Added visibility flag to internal messages and hid routine notices:
  - Model temp enforcement, "Temperature set", "Re-syncing model context…", API-key advice, and the full system prompt dump.
- Visible system message after prompt loads:
  - `System prompt loaded.. Good day Logic, how can i help you today?`

3) Tools: fetch_url and memory
 -Filesystem tool

- fetch_url: direct curl-based Process with JSON enforcement
  - Auto-adds `Accept: application/json` if not provided.
  - Emits error on non-JSON bodies.
- write_memory/search_memory: local file store
  - Stored at `state/user/ai/chats/memory.json`.
  - Simple append and substring search with optional namespace and top_k.

---

## UX and settings improvements

- Added settings menu window to sidebarLeft AI
  - Change API keys in menu.
  - Change temperature in menu (auto-adjusts for models that enforce a temp).
  - Change system prompt in menu.
  - Change autosave session name.
- Added OpenAI models.

### Sidebar Chat (modules/sidebarLeft/AiChat.qml, ai/qml)

- Tweaked design of user and assistant messages.

### Sidebar UI (modules/sidebarLeft)

- modules/sidebarLeft/AiChat.qml
  - Added Settings window “Save” toast and auto-close on save.
  - System prompt editor wrapped in a ScrollView with vertical scrollbar.
  - Fallback to `defaults/ai/prompts/ii-Default.md` when no chat-specific prompt exists.
  - Restores last session settings on startup (autosave enabled/name); now also clears previous chat content for a fresh start.
  - Status header shows token count; updates for OpenAI via backend change.
- modules/sidebarLeft/aiChat/AiMessage.qml
  - Transparent header/toolbars; BusyIndicator/typing dots while message is "thinking".
  - Assistant tools moved to a bottom toolbar; bottom tools right-aligned; “Copy” placed next to “Edit”.
  - Small top margin between messages only when role changes for clearer separation.

### Support/Services

- services/ai/OpenAiApiStrategy.qml
  - Added `stream_options: { include_usage: true }` to emit usage; token counts update for OpenAI.
  - Hardened SSE parsing to ignore non-JSON lines before JSON.parse.
- services/ai/MistralApiStrategy.qml
  - Hardened SSE parsing to ignore non-JSON lines before JSON.parse.
- modules/common/widgets/RippleButton.qml
  - Guard ripple animations when item/window not ready to prevent warnings.
- services/Ai.qml
  - Ensures persisted model re-selects automatically (onCurrentModelIdChanged → setModel(..., false, false)).
  - Token count binding drives the token counter for both Gemini and OpenAI.
  - addMessage(message, role, visible) supports hidden interface messages.
  - Prompt load emits only a single visible greeting line.
  - Replaced MCP fetch/memory with direct implementations (see above).

### Notes

- Token count appears next to temperature for OpenAI models.
- Experimental spacing changes reverted; only the role-switch gap remains.

---

## Usage examples

- Select tools: `/tool functions`
- Memory:
  - “Use write_memory with text 'Set DNS via systemd-resolved' namespace 'notes'.”
  - “Use search_memory query 'DNS' top_k 3 namespace 'notes' and show results.”
- Fetch JSON:
  - “Use fetch_url to GET <https://httpbin.org/json>; summarize the JSON keys in 3 bullets.”
  - Provide headers/body as needed, e.g. `{'Authorization':'Bearer ...'}`.
  - Non-JSON endpoints will return `ERROR: Non-JSON response`.

---

## Affected files (relative to repo root)

- `.config/quickshell/ii/modules/sidebarLeft/AiChat.qml`
- `.config/quickshell/ii/modules/sidebarLeft/aiChat/AiMessage.qml`
- `.config/quickshell/ii/services/Ai.qml`
- `.config/quickshell/ii/services/ai/OpenAiApiStrategy.qml`
- `.config/quickshell/ii/services/ai/MistralApiStrategy.qml`
- `.config/quickshell/ii/modules/common/widgets/RippleButton.qml`

## Breaking/behavior changes

- Added settings menu window to sidebarLeft AI
- Tweaked design of user and assistant messages.
  - Change API keys in menu.
  - Change temperature in menu (auto-adjusts for models that enforce a temp).
  - Change system prompt in menu.
  - Change autosave session name.
- Added OpenAI models.
- Hidden status messages by default; only one greeting shows after prompt load.
- fetch_url requires JSON responses; servers returning HTML will error.
- Memory uses local file store instead of MCP.
