// Concepts and their milestones, as the /concept skill writes them
// (docs/planning/concepts/<slug>.md), from every repo under ~/projects and
// from ~/.scratch. Opened as a dialog (cmd-shift-m). A milestone's state is
// worked out, never stored: its PRs on GitHub, its plan's checkboxes and what
// it depends on. ▶ starts it as a thread through the launcher.

import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, readTextFile, props, closeOverlay, openOverlay, theme, home, shared, setShared, checking } from "herdr";

const PICKED = "board.concept";

// Concept files, and each repo's GitHub name (from origin) for bare #<n> PRs.
const FIND = `find "$HOME/projects" "$HOME/.scratch" -maxdepth 6 -path '*/.work' -prune -o -path '*/node_modules' -prune \\
  -o -path '*/docs/planning/concepts/*.md' -print 2>/dev/null | sort`;
const ORIGIN = `git -C "$1" remote get-url origin 2>/dev/null | sed -E 's#^(git@[^:]+:|https?://[^/]+/)##; s#\\.git$##'`;
const REPOS = `find "$HOME/projects" -maxdepth 4 -name .git -not -path '*/.work/*' 2>/dev/null | sed 's|/.git$||'`;

// The concept format: a Status line, the title, then one "### M<n>: …" per milestone with "- Key: value" lines.
function parse(text, file) {
  const lines = text.split("\n");
  const concept = { file, status: "", title: "", milestones: [] };
  let m = null;
  for (const line of lines) {
    const status = line.match(/^Status:\s*(.+)$/);
    if (status && !m) { concept.status = status[1].trim(); continue; }
    const title = line.match(/^# (.+)$/);
    if (title && !concept.title) { concept.title = title[1].trim(); continue; }
    const head = line.match(/^### (M\d+):\s*(.+?)\s*(\[multi-repo\])?\s*$/);
    if (head) { m = { id: head[1], title: head[2], multi: Boolean(head[3]), fields: {} }; concept.milestones.push(m); continue; }
    if (/^## /.test(line)) { m = null; continue; }
    const field = m && line.match(/^- ([A-Za-z -]+):\s*(.*)$/);
    if (field) m.fields[field[1].trim().toLowerCase()] = field[2].trim();
  }
  return concept;
}

const none = (v) => !v || /^[—–-]$/.test(v.trim());
const list = (v) => none(v) ? [] : v.split(",").map((x) => x.trim()).filter(Boolean);

export default class Board extends View {
  init(_props, cx) {
    this.concepts = [];
    this.loading = true;
    this.picked = shared(PICKED) ?? null;
    this.prs = new Map(); // url -> {state, isDraft}
    this.plans = new Map(); // abs path -> {done, total} | null
    this.local = new Map(); // owner/name -> local checkout
    if (checking()) return;
    cx.spawn(async (cx) => {
      const found = (await exec("sh", ["-c", FIND]).catch(() => null))?.stdout.split("\n").filter(Boolean) ?? [];
      for (const r of (await exec("sh", ["-c", REPOS]).catch(() => null))?.stdout.split("\n").filter(Boolean) ?? []) {
        const name = (await exec("sh", ["-c", ORIGIN, "o", r]).catch(() => null))?.stdout.trim();
        if (name && !this.local.has(name)) this.local.set(name, r);
      }
      for (const file of found) {
        const text = await readTextFile(file);
        if (!text) continue;
        const c = parse(text, file);
        c.root = file.replace(/\/docs\/planning\/concepts\/[^/]+$/, "");
        c.slug = file.split("/").pop().replace(/\.md$/, "");
        c.repo = (await exec("sh", ["-c", ORIGIN, "o", c.root]).catch(() => null))?.stdout.trim() || null;
        this.concepts.push(c);
      }
      if (!this.concepts.some((c) => c.file === this.picked)) this.picked = this.concepts[0]?.file ?? null;
      this.loading = false;
      cx.notify();
      await this.details(cx);
    });
  }

  prUrl(c, m, ref) {
    if (/^https?:\/\//.test(ref)) return ref;
    const full = ref.match(/^([\w.-]+\/[\w.-]+)#(\d+)$/);
    if (full) return `https://github.com/${full[1]}/pull/${full[2]}`;
    const bare = ref.match(/^#(\d+)$/);
    const repo = list(m.fields.repos)[0] ?? c.repo;
    return bare && repo ? `https://github.com/${repo}/pull/${bare[1]}` : null;
  }

  // PR states (one GraphQL call) and plan progress, after the list is up.
  async details(cx) {
    const urls = new Set();
    for (const c of this.concepts) for (const m of c.milestones) {
      for (const ref of list(m.fields.prs)) { const u = this.prUrl(c, m, ref); if (u) urls.add(u); }
      if (!none(m.fields.plan)) {
        const path = `${c.root}/${m.fields.plan}`;
        const text = await readTextFile(path).catch(() => null);
        const done = (text?.match(/^\s*- \[x\]/gim) ?? []).length, open = (text?.match(/^\s*- \[ \]/gm) ?? []).length;
        this.plans.set(path, text == null ? null : { done, total: done + open });
      }
    }
    const all = [...urls];
    if (all.length) {
      const q = all.map((u, i) => `p${i}: resource(url: ${JSON.stringify(u)}) { ... on PullRequest { state isDraft } }`).join("\n");
      const r = await exec("gh", ["api", "graphql", "-f", `query=query { ${q} }`], { timeout: 30000 }).catch(() => null);
      const data = r?.code === 0 ? JSON.parse(r.stdout).data : {};
      all.forEach((u, i) => this.prs.set(u, data[`p${i}`] ?? null));
    }
    cx.notify();
  }

  // What a milestone is now: done, review, working, planned, waiting or open.
  state(c, m) {
    const prs = list(m.fields.prs).map((ref) => this.prs.get(this.prUrl(c, m, ref) ?? ""));
    if (prs.length && prs.every((p) => p?.state === "MERGED")) return { key: "done", text: "fertig" };
    if (prs.some((p) => p?.state === "OPEN")) return { key: "review", text: prs.some((p) => p?.isDraft) ? "PR-Entwurf" : "Review" };
    const plan = none(m.fields.plan) ? undefined : this.plans.get(`${c.root}/${m.fields.plan}`);
    const waits = list(m.fields["depends on"]).filter((d) => {
      const dep = c.milestones.find((x) => x.id === d);
      return dep && this.state(c, dep).key !== "done";
    });
    if (plan?.done) return { key: "working", text: `in Arbeit ${plan.done}/${plan.total}` };
    if (waits.length) return { key: "waiting", text: `wartet auf ${waits.join(", ")}` };
    if (plan) return { key: "planned", text: "geplant" };
    return { key: "open", text: "offen" };
  }

  start(c, m) {
    const repos = list(m.fields.repos).map((r) => this.local.get(r)).filter(Boolean);
    const rel = c.file.slice(c.root.length + 1);
    closeOverlay(props().overlay);
    openOverlay({ mod: "launch", kind: "dialog", width: 680, height: 600,
      props: { prompt: `/milestone ${rel} ${m.id}`, repos: repos.length ? repos : [c.root], vorhaben: c.title } });
  }

  render(cx) {
    const t = theme();
    const c = this.concepts.find((x) => x.file === this.picked);
    const color = { done: t.done, review: t.accent, working: t.working, planned: t.muted, waiting: t.dim, open: t.dim };
    const short = (p) => p.replace(home() + "/projects/", "").replace(home() + "/", "~/");

    const conceptRow = (x) => {
      const total = x.milestones.length, done = x.milestones.filter((m) => this.state(x, m).key === "done").length;
      const lit = x.file === this.picked;
      return v_flex().id(`c-${x.file}`).px(10).py(8).gap(2).rounded(6).cursor_pointer()
        .when(lit, (e) => e.bg(t.selected)).hover((e) => e.bg(lit ? t.selected : t.hover))
        .on_click((_e, cx) => { this.picked = x.file; setShared(PICKED, x.file); cx.notify(); })
        .child(div().truncate().font_semibold().text_color(t.foreground).child(x.title || x.slug))
        .child(h_flex().gap(6).text_size(11).text_color(t.dim)
          .child(div().truncate().child(short(x.root)))
          .child(div().flex_none().child(`· ${x.status || "?"} · ${done}/${total}`)));
    };

    const card = (m) => {
      const s = this.state(c, m);
      const prs = list(m.fields.prs);
      return v_flex().id(`m-${m.id}`).p(12).gap(6).rounded(8).border(1).border_color(t.border).bg(t.background)
        .child(h_flex().gap(8).items_center()
          .child(div().flex_none().font_semibold().text_color(t.dim).child(m.id))
          .child(div().flex_1().min_w(0).truncate().font_semibold().text_color(t.foreground).child(m.title))
          .when(m.multi, (e) => e.child(div().flex_none().px(6).rounded(4).border(1).border_color(t.border).text_size(10).text_color(t.muted).child("multi-repo")))
          .child(h_flex().flex_none().gap(5).items_center()
            .child(div().w(7).h(7).rounded(4).bg(color[s.key]))
            .child(div().text_size(12).text_color(s.key === "done" ? t.done : t.muted).child(s.text))))
        .when(!none(m.fields.outcome), (e) => e.child(div().text_size(12).text_color(t.muted).child(m.fields.outcome)))
        .child(h_flex().gap(10).items_center().text_size(11).text_color(t.dim)
          .child(div().flex_1().min_w(0).truncate().child(list(m.fields.repos).join(", ") || "—"))
          .children(prs.map((ref, i) => {
            const url = this.prUrl(c, m, ref), p = this.prs.get(url ?? "");
            return div().id(`pr-${m.id}-${i}`).px(6).rounded(4).cursor_pointer().hover((e) => e.bg(t.raised).text_color(t.foreground))
              .on_click(() => url && exec("open", [url]))
              .child(`${ref}${p ? ` ${p.state === "MERGED" ? "✓" : p.state === "OPEN" ? "●" : "✕"}` : ""} ↗`);
          }))
          .when(!none(m.fields.plan), (e) => e.child(div().id(`plan-${m.id}`).px(6).rounded(4).cursor_pointer()
            .hover((e) => e.bg(t.raised).text_color(t.foreground))
            .on_click(() => exec("open", ["-t", `${c.root}/${m.fields.plan}`])).child("Plan ↗")))
          .when(s.key !== "done", (e) => e.child(div().id(`go-${m.id}`).px(10).h(24).flex().items_center().rounded(6).cursor_pointer()
            .bg(s.key === "waiting" ? t.raised : t.solid).text_color(s.key === "waiting" ? t.muted : t.solid_foreground)
            .hover((e) => e.opacity(0.88)).on_click(() => this.start(c, m))
            .child("▶ Umsetzen"))));
    };

    return v_flex().id("board")
      .on_key_down((e, cx) => { if (e.key === "escape") { closeOverlay(props().overlay); cx.stop_propagation(); } })
      .size_full().min_h(0).rounded(8).bg(t.popover).text_size(13)
      .child(h_flex().px(16).h(48).items_center().gap(10)
        .child(div().flex_1().text_size(15).font_semibold().text_color(t.foreground).child("Meilensteine"))
        .child(div().id("new").px(10).h(28).flex().items_center().rounded(6).border(1).border_color(t.border).cursor_pointer()
          .text_color(t.muted).hover((e) => e.bg(t.hover).text_color(t.foreground))
          .on_click(() => { closeOverlay(props().overlay); openOverlay({ mod: "launch", kind: "dialog", width: 680, height: 600, props: { prompt: "/concept " } }); })
          .child("+ Neues Konzept"))
        .child(div().text_size(11).text_color(t.dim).child("Esc")))
      .child(h_flex().flex_1().min_h(0).border_t(1).border_color(t.border)
        .child(v_flex().w(280).flex_none().min_h(0).p(8).gap(2).overflow_y_scrollbar().border_r(1).border_color(t.border)
          .children(this.concepts.map(conceptRow))
          .when(!this.concepts.length, (e) => e.child(div().p(10).text_color(t.dim)
            .child(this.loading ? "Sucht Konzepte…" : "Noch keine Konzepte. „+ Neues Konzept“ startet /concept."))))
        .child(v_flex().flex_1().min_w(0).min_h(0).p(14).gap(10).overflow_y_scrollbar()
          .when(c != null, (e) => e
            .child(h_flex().gap(8).items_center()
              .child(div().flex_1().min_w(0).truncate().text_size(16).font_semibold().text_color(t.foreground).child(c.title || c.slug))
              .child(div().id("open-concept").px(6).rounded(4).cursor_pointer().text_size(12).text_color(t.dim)
                .hover((e) => e.bg(t.raised).text_color(t.foreground)).on_click(() => exec("open", ["-t", c.file])).child("Konzept ↗")))
            .children(c.milestones.map(card)))));
  }
}
