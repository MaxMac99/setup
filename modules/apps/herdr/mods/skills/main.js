// The skills Claude Code loads, grouped by where they come from (list.sh),
// with a filter. Opened as a dialog (cmd-shift-k). Enter or a click opens the
// thread launcher with `/<skill> ` as the first message; ↗ shows its SKILL.md.

import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input, ScrollHandle } from "gpui-base";
import { exec, props, closeOverlay, openOverlay, theme, appHome, checking } from "herdr";

const ORDER = ["Eigene", "Plugins", "Anthropic"];

export default class Skills extends View {
  init(_props, cx) {
    this.skills = [];
    this.sel = 0;
    this.loading = true;
    this.scroll = ScrollHandle.new();
    this.filter = InputState.new({ placeholder: "Skills suchen" });
    this.filter.on("change", (_e, cx) => { this.sel = 0; cx.notify(); });
    this.filter.on("submit", () => { const s = this.shown()[this.sel]; if (s) this.use(s); });
    if (checking()) return;
    this.filter.focus();
    cx.spawn(async (cx) => {
      const r = await exec("sh", [`${appHome()}/mods/skills/list.sh`]).catch(() => null);
      this.skills = (r?.stdout ?? "").split("\n").filter(Boolean).map((l) => {
        const [source, name, description, file] = l.split("\t");
        return { source, name, description: description ?? "", file };
      });
      this.loading = false;
      cx.notify();
    });
  }

  shown() {
    const q = this.filter.value().trim().toLowerCase();
    const hit = (s) => !q || s.name.toLowerCase().includes(q) || s.description.toLowerCase().includes(q);
    // Name matches first within each group, then by name.
    return ORDER.flatMap((src) => this.skills.filter((s) => s.source === src && hit(s))
      .sort((a, b) => Number(!a.name.includes(q)) - Number(!b.name.includes(q)) || a.name.localeCompare(b.name)));
  }

  use(s) {
    closeOverlay(props().overlay);
    openOverlay({ mod: "launch", kind: "dialog", width: 680, height: 600, props: { prompt: `/${s.name} ` } });
  }

  render(cx) {
    const t = theme();
    const list = this.shown();
    this.sel = Math.min(this.sel, Math.max(0, list.length - 1));
    const rows = [];
    let group = null;
    list.forEach((s, i) => {
      if (s.source !== group) {
        group = s.source;
        rows.push(div().px(10).pt(10).pb(4).text_size(11).text_color(t.dim)
          .child(`${group} · ${list.filter((x) => x.source === group).length}`));
      }
      const lit = i === this.sel;
      rows.push(h_flex().id(`sk-${i}`).px(10).py(6).gap(10).items_start().rounded(6).cursor_pointer()
        .when(lit, (e) => e.bg(t.selected)).hover((e) => e.bg(lit ? t.selected : t.hover))
        .on_click(() => this.use(s))
        .child(v_flex().flex_1().min_w(0).gap(2)
          .child(div().font_semibold().text_color(t.foreground).child(`/${s.name}`))
          .child(div().text_size(12).text_color(t.muted).max_h(38).overflow_hidden().child(s.description)))
        .child(div().id(`sk-open-${i}`).flex_none().px(6).rounded(4).text_size(12).text_color(t.dim)
          .hover((e) => e.bg(t.raised).text_color(t.foreground))
          .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
          .on_click(() => exec("open", ["-t", s.file]))
          .child("↗")));
    });
    if (!list.length) rows.push(div().px(10).py(10).text_color(t.dim).child(this.loading ? "Lädt…" : "Kein Skill passt."));

    return v_flex().id("skills")
      .on_key_down((e, cx) => {
        const n = list.length;
        if (e.key === "escape") closeOverlay(props().overlay);
        else if (e.key === "down" && n) this.sel = (this.sel + 1) % n;
        else if (e.key === "up" && n) this.sel = (this.sel - 1 + n) % n;
        else if (e.key === "enter" && n) this.use(list[this.sel]);
        else return;
        cx.stop_propagation();
        cx.notify();
      })
      .size_full().min_h(0).p(14).gap(10).rounded(8).bg(t.popover).text_size(13)
      .child(h_flex().items_center()
        .child(div().flex_1().text_size(15).font_semibold().text_color(t.foreground).child("Skills"))
        .child(div().text_size(11).text_color(t.dim).child(`${this.skills.length} geladen · Esc`)))
      .child(div().px(10).py(6).rounded(6).border(1).border_color(t.input).bg(t.background).child(Input.new(this.filter)))
      .child(v_flex().flex_1().min_h(0).overflow_y_scrollbar().track_scroll(this.scroll).children(rows))
      .child(h_flex().gap(14).text_size(11).text_color(t.dim)
        .child("↵ neuer Thread mit diesem Skill").child("↗ SKILL.md öffnen").child("↑↓ wählen"));
  }
}
