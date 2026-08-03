// Replacement for opencode's built-in `internal:sidebar-context` section, which
// renders "N tokens / P% used / $X.XX spent". The dollar figure is meaningless on
// a subscription, and the token count is already in the prompt footer, so this
// keeps only the percentage.
//
// Constraints enforced by the TUI plugin loader:
//   - filename must end in .tsx, otherwise the JSX transform is skipped
//   - the slot renderer must return exactly one node, synchronously
//   - registered via tui.json `plugin`, not opencode.json `plugin`
import type { TuiPluginApi } from "@opencode-ai/plugin/tui"

function ContextPercent(props: { api: TuiPluginApi; session_id: string }) {
  const theme = () => props.api.theme.current
  const percent = () => {
    const messages = props.api.state.session.messages(props.session_id)
    const last = messages.findLast((m) => m.role === "assistant" && m.tokens.output > 0)
    if (!last) return null
    const used =
      last.tokens.input +
      last.tokens.output +
      last.tokens.reasoning +
      last.tokens.cache.read +
      last.tokens.cache.write
    const limit = props.api.state.provider.find((p) => p.id === last.providerID)?.models[
      last.modelID
    ]?.limit.context
    return limit ? Math.round((used / limit) * 100) : null
  }

  // Mirrors the built-in section's node tree and colours, minus the token and
  // cost lines.
  return (
    <box>
      <text fg={theme().text}>
        <b>Context</b>
      </text>
      <text fg={theme().textMuted}>{percent() ?? 0}% used</text>
    </box>
  )
}

export default {
  id: "custom:context-percent",
  async tui(api: TuiPluginApi) {
    api.slots.register({
      // Same order as the built-in section it replaces, so it lands above
      // sidebar-mcp (200) / lsp (300) / todo (400) / files (500).
      order: 100,
      slots: {
        sidebar_content: (_ctx, data) => (
          <ContextPercent api={api} session_id={data.session_id} />
        ),
      },
    })
  },
}
