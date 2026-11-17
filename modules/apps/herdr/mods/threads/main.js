// The sidebar's thread tree, as T3's: machine → project → threads (top-level
// agents). Rows keep their place: no Working group, nothing re-sorted by
// status. Settled and snoozed threads leave the tree for the shelves at the
// bottom, through the same terminal labels herdr-t3's Inbox uses
// (`settled=<ms>:<turn>`, `snoozed=<wake ms>`), so both views agree.
// A blocked thread shows even while snoozed. Also opened as a popup with
// props {snooze: address}: the snooze times for one thread.

import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { agents, terminals, spaces, panes, theme, run, props, openOverlay, closeOverlay, shared, setShared, setAgentOrder, hc, exec, notify, home, checking } from "herdr";
// project.js, program.js, store.js and color.js are herdr-t3's (Apache-2.0), copied as they are:
// the project's favicon or T3's colored monogram, and the program's mark.
import { projectMark } from "./project.js";
import { programIcon } from "./program.js";

const FOLDS = "threads.folds";

const label = async (address, key, value) => {
  if (checking()) return;
  const r = await hc(["label", address, `${key}=${value}`]).catch((e) => ({ code: 1, stderr: String(e) }));
  if (r.code !== 0) notify({ title: "Thread nicht geändert", body: (r.stderr ?? "").trim(), level: "error" });
};

// A folder's repo (the main checkout's name, also from a worktree) and branch, tab-separated; nothing outside git.
const WHERE = `top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || exit 0
common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)
printf '%s\t%s' "$(dirname "$common")" "$(git -C "$1" branch --show-current)"`;

// Wake times for the snooze menu, in local time.
const at = (h, m = 0, days = 0) => { const d = new Date(); d.setDate(d.getDate() + days); d.setHours(h, m, 0, 0); return d.getTime(); };
const nextMonday = () => { const d = new Date(); return at(9, 0, ((8 - d.getDay()) % 7) || 7); };
const PRESETS = () => [
  ["30 Minuten", Date.now() + 30 * 60000],
  ["1 Stunde", Date.now() + 3600000],
  ["3 Stunden", Date.now() + 3 * 3600000],
  ...(new Date().getHours() < 17 ? [["Heute 18:00", at(18)]] : []),
  ["Morgen 9:00", at(9, 0, 1)],
  ["Montag 9:00", nextMonday()],
];

const clock = (ms) => new Date(ms).toLocaleString("de-DE", { weekday: "short", hour: "2-digit", minute: "2-digit" });
// Working time: to the second under an hour (42s, 4m 12s), then 1h 5m, then days.
const since = (ms) => {
  const sec = Math.max(0, Math.floor((Date.now() - ms) / 1000));
  if (sec < 60) return `${sec}s`;
  if (sec < 3600) return `${Math.floor(sec / 60)}m ${sec % 60}s`;
  if (sec < 86400) return `${Math.floor(sec / 3600)}h ${Math.floor(sec / 60) % 60}m`;
  return `${Math.floor(sec / 86400)}d`;
};

// The project a space belongs to: a named space (a Vorhaben) is its own; else
// its repo, with worktrees (<repo>/.work/…, ~/.herdr/worktrees/<repo>/…) folded in.
const projectOf = (s) => {
  if (s.named) return { key: `space:${s.id}`, name: s.name };
  const f = s.folder || "";
  const work = f.match(/^(.*?)\/\.work\//);
  if (work) return { key: work[1], name: work[1].split("/").pop() };
  const hw = f.match(/\/\.herdr\/worktrees\/([^/]+)/);
  if (hw) return { key: `herdr-wt:${hw[1]}`, name: hw[1] };
  if (!f || f === home()) return { key: "~", name: "~" };
  return { key: f, name: s.name || f.split("/").pop() };
};

export default class Threads extends View {
  init(_props, cx) {
    this.openShelf = null;
    this.hot = null;
    // cwd -> {repo, branch} | null, asked of git once per folder and again each refresh.
    this.where = new Map();
    this.asking = new Set();
    if (props()?.snooze) return;
    // Snoozes end by the clock: look again each minute.
    // Branches change under a running thread: ask again on the same beat.
    if (!checking()) cx.timer.every(30000, (cx) => { this.where.clear(); cx.notify(); });
    // The working clock ticks by the second only while a thread under an hour is working.
    if (!checking()) cx.timer.every(1000, (cx) => { if (this.ticking) cx.notify(); });
  }

  hover(id, on, cx) {
    if (on) this.hot = id;
    else if (this.hot === id) this.hot = null;
    cx.notify();
  }

  model() {
    const now = Date.now();
    const term = new Map(terminals().map((t) => [t.address, t]));
    const lab = (a, k) => term.get(a.address)?.labels?.[k] ?? "";
    const all = agents();
    const top = all.filter((a) => !term.get(a.address)?.parent);
    const kids = (a) => all.filter((b) => term.get(b.address)?.parent === a.address).length;
    const settled = (a) => Boolean(lab(a, "settled"));
    const napUntil = (a) => Number(lab(a, "snoozed")) || 0;
    const napping = (a) => !settled(a) && napUntil(a) > now && a.status !== "blocked";
    const sp = new Map(spaces().map((s) => [s.id, s]));
    const tabOf = (a) => sp.get(a.space)?.tabs.find((t) => t.id === a.tab);
    return { top, kids, settled, napUntil, napping, sp, tabOf, term };
  }

  name(a) {
    if (a.tab_name && !/^\d+$/.test(a.tab_name)) return a.tab_name;
    return a.title || a.program?.name || a.address;
  }

  // Where a thread works, once known; asks git in the background the first time.
  whereOf(cwd, cx) {
    if (!cwd) return null;
    if (this.where.has(cwd)) return this.where.get(cwd);
    if (!this.asking.has(cwd) && !checking()) {
      this.asking.add(cwd);
      cx.spawn(async (cx) => {
        const r = await exec("sh", ["-c", WHERE, "where", cwd]).catch(() => null);
        const [root, branch] = (r?.stdout ?? "").split("\t");
        this.where.set(cwd, root ? { root, repo: root.split("/").pop(), branch: branch || null } : null);
        this.asking.delete(cwd);
        cx.notify();
      });
    }
    return null;
  }

  settle(a, m) {
    label(a.address, "settled", `${Date.now()}:${m.term.get(a.address)?.turn ?? 0}`);
    label(a.address, "snoozed", "");
  }

  render(cx) {
    if (props()?.snooze) return this.snoozeMenu(cx);
    const t = theme();
    const m = this.model();
    const folds = shared(FOLDS) ?? {};
    const fold = (key) => { setShared(FOLDS, { ...folds, [key]: !folds[key] }); };

    // machine → project → threads, in agents()' own (space, tab, pane) order.
    const tree = new Map();
    for (const a of m.top) {
      if (m.settled(a) || m.napping(a)) continue;
      const s = m.sp.get(a.space);
      if (!s) continue;
      const machine = s.machine ?? "Dieser Mac";
      const p = projectOf(s);
      if (!tree.has(machine)) tree.set(machine, new Map());
      const projects = tree.get(machine);
      if (!projects.has(p.key)) projects.set(p.key, { ...p, space: s, folder: s.folder, threads: [] });
      projects.get(p.key).threads.push(a);
    }
    const order = [];
    const ps = panes();
    this.ticking = m.top.some((a) => a.status === "working" && (Date.now() - (m.tabOf(a)?.working_since ?? 0)) < 3600000);

    const mark = (a) => {
      if (a.status === "blocked") return div().w(14).flex_none().text_size(12).font_semibold().text_color(t.blocked).child("!");
      if (a.status === "working") return div().w(14).flex_none().flex().justify_center().child(div().w(7).h(7).rounded(4).border(2).border_color(t.working));
      return div().w(14).flex_none();
    };

    const row = (a) => {
      order.push(a.address);
      const tab = m.tabOf(a);
      const n = m.kids(a);
      const busy = a.status === "working" || a.status === "blocked";
      const cwd = m.term.get(a.address)?.cwd;
      const w = this.whereOf(cwd, cx);
      const sub = w ? `${w.repo}${w.branch ? ` · ${w.branch}` : ""}` : cwd?.includes("/.scratch/") ? "scratch" : null;
      return h_flex().id(`th-${a.address}`).on_hover((h, cx) => this.hover(`th-${a.address}`, h, cx)).h(sub ? 38 : 30).pl(8).pr(6).gap(6).items_center().rounded(6).cursor_pointer()
        .when(a.focused, (s) => s.bg(t.selected))
        .hover((s) => s.bg(a.focused ? t.selected : t.hover))
        .on_click(() => run("agent.focus", { terminal: a.address }))
        // Unread: finished since you last looked at it ("done" turns "idle" once you do).
        .child(div().w(8).flex_none().flex().justify_center()
          .when(a.status === "done", (s) => s.child(div().w(6).h(6).rounded(3).bg(t.accent))))
        .child(div().w(22).mr(4).flex_none().flex().justify_center().child(w
          ? projectMark("mods/t3-spaces", { id: `repo:${w.root}`, name: w.repo, folder: w.root, tabs: [], machine: null }, 20, t, ps, true)
          : programIcon(a.program, 18, t.muted) ?? div()))
        .child(v_flex().flex_1().min_w(0)
          .child(div().truncate().line_height("16px")
            .text_color(a.status === "idle" ? t.muted : t.foreground).when(a.status === "done", (s) => s.font_semibold())
            .child(this.name(a)))
          .when(sub != null, (s) => s.child(div().truncate().line_height("14px").text_size(11).text_color(t.dim).child(sub))))
        .when(n > 0, (s) => s.child(div().flex_none().text_size(11).text_color(t.dim).child(`+${n}`)))
        .when(a.status === "working" && tab?.working_since, (s) => s.child(div().flex_none().text_size(11).text_color(t.dim).child(since(tab.working_since))))
        .when(a.status !== "blocked", (s) => s.child(div().id(`nap-${a.address}`).flex_none().px(4).rounded(4).text_size(12).text_color(t.dim)
          .when(this.hot !== `th-${a.address}`, (s) => s.invisible()).hover((s) => s.bg(t.raised).text_color(t.foreground))
          .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
          .on_click(() => openOverlay({ mod: "threads", kind: "popup", width: 190, height: 240, props: { snooze: a.address, name: this.name(a) } }))
          .child("⏾")))
        .when(!busy, (s) => s.child(div().id(`settle-${a.address}`).flex_none().px(4).rounded(4).text_size(12).text_color(t.dim)
          .when(this.hot !== `th-${a.address}`, (s) => s.invisible()).hover((s) => s.bg(t.raised).text_color(t.foreground))
          .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
          .on_click(() => this.settle(a, m))
          .child("✓")))
        .child(mark(a));
    };

    const project = (machine, p) => {
      const key = `${machine}/${p.key}`;
      const shut = Boolean(folds[key]);
      const need = p.threads.filter((a) => a.status === "blocked" || a.status === "done").length;
      return v_flex()
        .child(h_flex().id(`pj-${key}`).on_hover((h, cx) => this.hover(`pj-${key}`, h, cx)).h(28).px(8).gap(6).items_center().rounded(6).cursor_pointer().hover((s) => s.bg(t.hover))
          .on_click(() => fold(key))
          .child(div().w(12).flex_none().text_size(10).text_color(t.dim).child(shut ? "▸" : "▾"))
          .child(div().flex_1().min_w(0).truncate().font_semibold().text_color(t.foreground).child(p.name))
          .when(shut && need > 0, (s) => s.child(div().flex_none().w(7).h(7).rounded(4).bg(t.done)))
          .child(div().id(`new-${key}`).flex_none().px(4).rounded(4).text_color(t.dim).when(this.hot !== `pj-${key}`, (s) => s.invisible())
            .hover((s) => s.bg(t.raised).text_color(t.foreground))
            .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
            .on_click(() => openOverlay({ mod: "launch", kind: "dialog", width: 680, height: 600, props: { repo: p.folder } }))
            .child("+")))
        .when(!shut, (s) => s.children(p.threads.map(row)));
    };

    const body = [];
    for (const [machine, projects] of tree) {
      body.push(div().px(8).pt(10).pb(2).text_size(11).text_color(t.dim).child(machine));
      for (const p of projects.values()) body.push(project(machine, p));
    }
    if (!tree.size) body.push(div().px(12).py(10).text_color(t.dim).child("Keine offenen Threads."));

    // The shelves: what is put away, folded, at the bottom.
    const napped = m.top.filter(m.napping).sort((x, y) => m.napUntil(x) - m.napUntil(y));
    const done = m.top.filter(m.settled);
    const shelf = (id, title, list, line, undo) => v_flex()
      .child(h_flex().id(`shelf-${id}`).h(26).px(8).gap(6).items_center().rounded(6).cursor_pointer().hover((s) => s.bg(t.hover))
        .on_click((_e, cx) => { this.openShelf = this.openShelf === id ? null : id; cx.notify(); })
        .child(div().w(12).text_size(10).text_color(t.dim).child(this.openShelf === id ? "▾" : "▸"))
        .child(div().flex_1().text_size(12).text_color(t.muted).child(title))
        .child(div().text_size(11).text_color(t.dim).child(String(list.length))))
      .when(this.openShelf === id, (s) => s.children(list.map((a) =>
        h_flex().id(`${id}-${a.address}`).h(26).pl(26).pr(6).gap(6).items_center().rounded(6).cursor_pointer().hover((s) => s.bg(t.hover))
          .on_click(() => run("agent.focus", { terminal: a.address }))
          .child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(this.name(a)))
          .child(div().flex_none().text_size(11).text_color(t.dim).child(line(a)))
          .child(div().id(`${id}-undo-${a.address}`).flex_none().px(4).rounded(4).text_size(12).text_color(t.dim).hover((s) => s.bg(t.raised).text_color(t.foreground))
            .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
            .on_click(() => undo(a)).child("↺")))));

    if (!checking()) setAgentOrder(order);
    return v_flex().id("threads").size_full().min_h(0).bg(t.chrome).text_size(13)
      .child(v_flex().flex_1().min_h(0).px(6).overflow_y_scrollbar().children(body))
      .when(napped.length || done.length, (s) => s.child(v_flex().px(6).py(4).border_t(1).border_color(t.border)
        .when(napped.length > 0, (s) => s.child(shelf("nap", "Pausiert", napped, (a) => clock(m.napUntil(a)), (a) => label(a.address, "snoozed", ""))))
        .when(done.length > 0, (s) => s.child(shelf("done", "Erledigt", done, () => "", (a) => label(a.address, "settled", ""))))));
  }

  snoozeMenu(cx) {
    const t = theme();
    const p = props();
    return v_flex().size_full().p(6).gap(2).rounded(8).bg(t.popover).text_size(13)
      .child(div().px(8).py(4).text_size(11).text_color(t.dim).truncate().child(`Pausieren: ${p.name ?? ""}`))
      .children(PRESETS().map(([text, until], i) =>
        h_flex().id(`p-${i}`).h(28).px(8).items_center().rounded(6).cursor_pointer().hover((s) => s.bg(t.hover))
          .on_click(() => { label(p.snooze, "snoozed", String(until)); closeOverlay(p.overlay); })
          .child(div().flex_1().text_color(t.foreground).child(text))
          .child(div().text_size(11).text_color(t.dim).child(clock(until)))));
  }
}
