# sku-menubar (myClaude)

## Project
- macOS SwiftUI menubar app — AI Command Center wrapping Claude CLI
- Path: `/Users/steffen/Documents/GitHub/sku-menubar/sku-menubar`
- Build: `swift build -c release` (NICHT `--target myClaude` — das kompiliert nur, linkt nicht!)
- Binary-Pfad: `.build/arm64-apple-macosx/release/myClaude`
- Deploy: `cp .build/arm64-apple-macosx/release/myClaude ~/Applications/myClaude.app/Contents/MacOS/myClaude && codesign --force --deep --sign - ~/Applications/myClaude.app`
- App vom Dock starten (terminal `open` wird von Gatekeeper geblockt: RBSRequestErrorDomain Code=5)

## Architecture
- `MainWindowView`: NavigationSplitView — Sidebar + detail
- `ChatView` / `SingleChatSessionView`: multi-tab chat with Claude CLI
- `CodeReviewView`: file picker + review config + source viewer + output (3-column)
- `CLIModels.swift`: shared data models (ChatMessage, ToolCall, AppSection, etc.)
- `MCPView.swift`: MCP server list + AddMCPServerSheet (catalog + manual tab)
- `NotesView.swift`: Notes & Tasks with TaskLines editor
- `ThemeManager`: `AppTheme` via `@Environment(\.appTheme)`

## Conventions
- Accent color: `Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)`
- `theme.isLight` for light/dark conditional styling
- Git diff fetched via `git diff HEAD` after tool calls, stored in `ChatMessage.gitDiff`
- AppSection cases use dot-syntax: `.tasks`, `.notes` etc. (not plain `tasks`)

## Key Patterns
- **macOS SwiftUI Popover + TextField = Freeze**: Popover auf TextField verursacht Focus-Ownership-Zyklus → unendliche Re-Renders. Lösung: Popover entfernen, nur onSubmit verwenden.
- **FocusState + animation in ScrollView = Layout-Loop**: `@FocusState` kombiniert mit `.animation()` auf Frame-Breite in einer ScrollView → endlose Layout-Neuberechnungen. Vermeiden.
- Diff side panel: `activeDiff: String?` state in `SingleChatSessionView`, shown as right column
- `parseDiffFiles()` is a top-level function (shared); trims `\r` for Windows compat
- `MessageBubbleView` has `onDiffTap: ((String) -> Void)?` callback to open side panel
- `ChatMessage`, `ToolCall`, `MessageRole` conform to `Equatable` (custom `==` by id)
- Input lag fix: `onChange(of: messages)` only writes `tab.messages` when `!isStreaming`
- `scrollToBottom` only fires on `messages.last?.content` change when NOT streaming; once on stream end
- `NSOpenPanel` for directory selection extracted to `openDirectoryPicker()` in `SingleChatSessionView`
- New empty chat auto-opens directory picker via `DispatchQueue.main.asyncAfter(deadline: .now() + 0.15)`

## MCPView Patterns
- `KnownModel` struct: 52 models across 10 providers (Anthropic, OpenAI, Google, Meta, Mistral, xAI, Cohere, DeepSeek, Amazon, Perplexity)
- `ModelPickerPopover`: search + provider chips + grouped list with contextK badge
- Selected model written as `MODEL=<apiName>` env-var in `addServer()`
- `MCPCatalogEntry.all`: predefined server catalog with category/transport/envVars

## Agent Files
- Agent-Dateien liegen unter ~/.claude/agents/*.md als YAML-Frontmatter + Prompt-Body
- Verwendete Frontmatter-Keys in vorhandenen Dateien: name, description, model, optional color, optional memory
- Agent-ID entspricht dem Dateinamen ohne .md; Umbenennen sollte Dateiname und ~/.claude/agent-memory/<id> gemeinsam verschieben
- AgentsView verwaltet Agents jetzt komplett in der App: anlegen, bearbeiten, duplizieren, loeschen, importieren, exportieren
- AgentEditorSheet zeigt eine Live-Rohvorschau der serialisierten .md-Datei und kann diese in die Zwischenablage kopieren
- Import/Export der Agent-Dateien nutzt macOS NSOpenPanel/NSSavePanel; fuer .md wird UTType(filenameExtension: "md") verwendet

## Key Patterns (Auto-Switch)
- Rate-Limit Detection erfolgt an 2 Stellen in `performSend`: im `"result"` case (bei `event.isError == true`) UND im `catch` Block
- Catch-Block prüft auch `messages[assistantIndex].content` (nicht nur `error.localizedDescription`)
- `AccentToggleStyle` (custom ToggleStyle) in SettingsFormView.swift statt `.tint()` — macOS respektiert `.tint()` auf Toggle nicht zuverlässig

## Last Commits
- `be749b4`: fix: TagInputView radikal vereinfacht — kein FocusState, keine Animation, kein onChange
- `6a1577f`: fix: TagInputView — Popover komplett entfernt
- `4e80520`: fix: Tag-Eingabe in Aufgaben hängt nicht mehr — onChange(of: body) auf .note beschränkt, Popover-Setter korrigiert
- `6ca119a`: fix: Auto-Switch Copilot bei isError-Result + AccentToggleStyle für Theme-Akzentfarbe
- `d3bbe63`: fix: TaskLine-Toggle via lines.indices — direkter @Binding-Setter statt ForEach-Binding-Closure
- `bf16b81`: fix: TaskLine-Toggle überträgt Änderung korrekt durch Binding-Kette
- `063849a`: feat: Projektauswahl-Dialog öffnet automatisch bei neuem Chat
- `c92c788`: fix: Input-Lag im Chat — onChange/scrollToBottom nur außerhalb Streaming
- `0a79055`: feat: HowTo-Hinweis unter Modell-Picker
