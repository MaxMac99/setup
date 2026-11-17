// Starts a Claude chat thread (herdr-chat) from one dialog (cmd-shift-n):
// the first message, the Vorhaben (a named space; empty: the shown one), the
// repos (the first is where Claude starts, the rest go in as --add-dir) and
// the MCP profile (only its servers load). The profile and repos reach claude
// through the chat host's environment and the claude-profiled wrapper, which
// mods/chat/config.json names as the claude command.

import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input, TextareaState, Textarea } from "gpui-base";
import { exec, run, props, closeOverlay, theme, spaces, focused, shared, setShared, home, notify, checking, readTextFile, appHome } from "herdr";

const PROFILES = ".config/claude-profiles/mcp";
const LAST = "launch.last";

// Git checkouts under ~/projects, without worktrees in .work.
const REPOS = `find "$HOME/projects" -maxdepth 4 -name .git -not -path '*/.work/*' -not -path '*/node_modules/*' 2>/dev/null | sed 's|/.git$||' | sort`;

const chatId = () => `c-${Array.from({ length: 8 }, () => "0123456789abcdef"[Math.floor(Math.random() * 16)]).join("")}`;

export default class Launch extends View {
  init(_props, cx) {
    const last = shared(LAST) ?? {};
    this.prompt = TextareaState.new({ placeholder: "Was soll Claude tun? (z. B. /milestone M2 aus docs/planning/concepts/…)" });
    this.prompt.set_auto_grow(4, 10);
    // A first message handed over (the skills list: "/<skill> ").
    if (props()?.prompt) this.prompt.set_value(props().prompt);
    if (props()?.vorhaben) this.space.set_value(props().vorhaben);
    this.space = InputState.new({ placeholder: "Vorhaben: Name eines Spaces (leer = aktueller)" });
    this.filter = InputState.new({ placeholder: "Repos filtern" });
    this.filter.on("change", (_e, cx) => cx.notify());
    this.prompt.on("submit", (e, cx) => { if (e.secondary) this.start(cx); });
    this.repos = [];
    this.picked = [];
    this.profiles = [];
    // MCP servers this thread gets, one file each; none picked: the empty "keine".
    this.mcp = new Set(last.mcp ?? []);
    this.starting = false;
    this.handle = cx.focus_handle();
    if (checking()) return;
    this.prompt.focus();
    cx.spawn(async (cx) => {
      const r = await exec("sh", ["-c", REPOS], { cwd: home() }).catch(() => null);
      this.repos = (r?.stdout ?? "").split("\n").filter(Boolean);
      // Start where the focused terminal works, when that is one of the repos.
      const cwd = focused()?.cwd ?? "";
      const here = this.repos.filter((p) => cwd === p || cwd.startsWith(p + "/")).sort((a, b) => b.length - a.length)[0];
      const asked = props()?.repo ? this.repos.find((p) => p === props().repo) : null;
      if (asked || here) this.picked = [asked ?? here];
      // A milestone handed over by the board: its repos, the first as the working folder.
      if (props()?.repos?.length) this.picked = [...props().repos];
      const p = await exec("sh", ["-c", `ls "$HOME/${PROFILES}" 2>/dev/null | sed -n 's/\\.json$//p'`]).catch(() => null);
      const names = (p?.stdout ?? "").split("\n").filter(Boolean);
      this.profiles = names.filter((n) => n !== "keine");
      this.mcp = new Set([...this.mcp].filter((n) => this.profiles.includes(n)));
      cx.notify();
    });
  }

  toggle(repo) {
    this.picked = this.picked.includes(repo) ? this.picked.filter((r) => r !== repo) : [...this.picked, repo];
  }

  // The space to put the chat in: an existing one by name, a new named one, or the shown one.
  async targetSpace(name, folder, cx) {
    if (!name) return focused()?.space ?? null;
    const found = spaces().find((s) => s.name === name && !s.machine);
    if (found) return found.id;
    run("space.new", { name, folder, tab: "Setup", focus: false });
    for (let i = 0; i < 40; i++) {
      await new Promise((resolve) => cx.timer.after(100, () => resolve(null)));
      const s = spaces().find((s) => s.name === name && !s.machine);
      if (s) return s.id;
    }
    return null;
  }

  start(cx) {
    const text = this.prompt.value().trim();
    if (this.starting || (!this.picked.length && !text)) return;
    this.starting = true;
    cx.notify();
    const [repo, ...extra] = this.picked;
    // No repo: a scratch folder of its own, in the Scratch space unless a Vorhaben is named.
    const name = this.space.value().trim() || (repo ? "" : "Scratch");
    const mcp = [...this.mcp];
    setShared(LAST, { mcp });
    cx.spawn(async (cx) => {
      try {
        const cwd = repo ?? await this.scratch(text);
        const space = await this.targetSpace(name, cwd, cx);
        if (!space) throw new Error(`Space „${name}“ ließ sich nicht anlegen`);
        // A new space comes with a shell tab ("Setup"): the chat replaces it.
        const shell = name ? spaces().find((s) => s.id === space)?.tabs.find((t) => t.name === "Setup") : null;
        const chat = chatId();
        const hostEnv = { CLAUDE_MCP_PROFILE: mcp.length ? mcp.join(",") : "keine", ...(extra.length ? { CLAUDE_ADD_DIRS: extra.join(":") } : {}) };
        run("tab.new", { space, name: text.split("\n")[0].slice(0, 40) || "claude", mod: "chat", props: { chat, provider: "claude", cwd, hostEnv } });
        if (shell) run("tab.close", { id: shell.id, confirmed: true });
        closeOverlay(props().overlay);
        if (text) await this.send(chat, text);
      } catch (e) {
        this.starting = false;
        notify({ title: "Thread nicht gestartet", body: String(e?.message ?? e), level: "error" });
        cx.notify();
      }
    });
  }

  // ~/.scratch/<date>-<first words>, made fresh.
  async scratch(text) {
    const slug = text.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-").split("-").filter(Boolean).slice(0, 5).join("-") || "thread";
    const dir = `${home()}/.scratch/${new Date().toISOString().slice(0, 10)}-${slug}`;
    const r = await exec("sh", ["-c", 'd="$1"; n=1; while [ -e "$d" ]; do n=$((n+1)); d="$1-$n"; done; mkdir -p "$d" && printf %s "$d"', "sh", dir]);
    if (r.code !== 0) throw new Error(r.stderr.trim() || "Scratch-Ordner nicht angelegt");
    return r.stdout;
  }

  // The first message, once the chat's host is up (it waits up to a minute).
  async send(chat, text) {
    const cfg = JSON.parse((await readTextFile(`${appHome()}/mods/chat/config.json`)) ?? "{}");
    const r = await exec(cfg.node ?? "node", [cfg.host.replace(/\/bin\/herdr-chat-host$/, "/host/main.ts"), "send", "--chat", chat, "--timeout", "60", text], { timeout: 90000 }).catch((e) => ({ code: 1, stderr: String(e) }));
    if (r.code !== 0) notify({ title: "Erste Nachricht nicht gesendet", body: (r.stderr || "").trim().split("\n").pop(), level: "warning" });
  }

  render(cx) {
    const t = theme();
    const q = this.filter.value().trim().toLowerCase();
    const short = (p) => p.replace(home() + "/projects/", "");
    const shown = this.repos.filter((p) => !q || short(p).toLowerCase().includes(q));
    const label = (s) => div().text_size(11).text_color(t.dim).child(s);
    const field = (el) => div().px(10).py(6).rounded(6).border(1).border_color(t.input).bg(t.background).child(el);
    const chip = (id, text, on, click) =>
      div().id(id).px(10).h(26).flex().items_center().rounded(13).border(1).cursor_pointer()
        .border_color(on ? t.accent : t.border).text_color(on ? t.foreground : t.muted).when(on, (s) => s.bg(t.selected))
        .hover((s) => s.bg(t.hover)).on_click(click).child(text);

    return v_flex()
      .id("launch")
      .track_focus(this.handle)
      .on_key_down((e, cx) => {
        if (e.key === "escape") closeOverlay(props().overlay);
        else if (e.key === "enter" && (e.modifiers?.platform)) this.start(cx);
        else return;
        cx.stop_propagation();
      })
      .size_full().min_h(0).p(18).gap(12).rounded(8).bg(t.popover).text_size(13)
      .child(h_flex().items_center()
        .child(div().flex_1().text_size(15).font_semibold().text_color(t.foreground).child("Neuer Thread"))
        .child(div().text_size(11).text_color(t.dim).child("Esc")))
      .child(field(Textarea.new(this.prompt)))
      .child(field(Input.new(this.space)))
      .child(v_flex().gap(6)
        .child(label("MCP-Server (Mehrfachauswahl)"))
        .child(this.profiles.length
          ? h_flex().gap(6).flex_wrap().children(this.profiles.map((p) =>
            chip(`mcp-${p}`, p, this.mcp.has(p), (_e, cx) => { this.mcp.has(p) ? this.mcp.delete(p) : this.mcp.add(p); cx.notify(); })))
          : div().text_size(12).text_color(t.dim).child("Noch keine: eine Datei pro Server in ~/.config/claude-profiles/mcp/")))
      .child(v_flex().gap(6).flex_1().min_h(0)
        .child(h_flex().items_center().gap(8)
          .child(label("Repos (optional): das erste ist das Arbeitsverzeichnis, weitere per --add-dir; keins = Scratch-Ordner"))
          .child(div().flex_1())
          .child(div().w(200).child(field(Input.new(this.filter)))))
        .child(v_flex().flex_1().min_h(0).overflow_y_scrollbar().children(shown.map((p, i) => {
          const n = this.picked.indexOf(p);
          return h_flex().id(`repo-${i}`).h(28).px(8).gap(8).items_center().rounded(6).cursor_pointer()
            .hover((s) => s.bg(t.hover)).on_click((_e, cx) => { this.toggle(p); cx.notify(); })
            .child(div().w(18).h(18).flex_none().rounded(4).border(1).flex().items_center().justify_center().text_size(10)
              .border_color(n >= 0 ? t.accent : t.border).when(n >= 0, (s) => s.bg(t.accent).text_color(t.background))
              .child(n >= 0 ? String(n + 1) : ""))
            .child(div().flex_1().truncate().text_color(n >= 0 ? t.foreground : t.muted).child(short(p)))
            .when(n === 0, (s) => s.child(div().text_size(11).text_color(t.dim).child("Arbeitsverzeichnis")));
        }))))
      .child(h_flex().items_center().gap(10)
        .child(div().flex_1().text_size(11).text_color(t.dim).child(`${this.picked.length ? `${this.picked.length} Repo(s)` : "Scratch"} · ${this.mcp.size ? [...this.mcp].join(", ") : "ohne MCP"}`))
        .child(div().id("start").h(32).px(14).flex().items_center().rounded(8).cursor_pointer()
          .bg(t.solid).text_color(t.solid_foreground)
          .hover((s) => s.opacity(0.88)).on_click((_e, cx) => this.start(cx))
          .child(this.starting ? "Startet…" : "Starten  ⌘↵")));
  }
}
