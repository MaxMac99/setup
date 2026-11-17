// Open pull requests from GitHub (gh's sign-in): the person's own and those
// waiting for their review, with CI and review state. Opened as a dialog
// (cmd-shift-o). Enter puts Claude on the selected PR in a worktree under
// <repo>/.work (the `wt` convention), o opens it in the browser.

import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, run, props, closeOverlay, theme, shared, setShared, home, notify, checking } from "herdr";

const CACHE = "prs.cache";
const FIELDS = `... on PullRequest {
  number title url isDraft updatedAt headRefName reviewDecision
  repository { name nameWithOwner }
  commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
}`;
const QUERY = `query {
  mine: search(query: "is:pr is:open author:@me archived:false sort:updated-desc", type: ISSUE, first: 50) { nodes { ${FIELDS} } }
  review: search(query: "is:pr is:open review-requested:@me archived:false sort:updated-desc", type: ISSUE, first: 50) { nodes { ${FIELDS} } }
}`;

// Finds the local checkout by name under ~/projects, reuses a worktree that
// already has the branch, else makes one with `wt new` from origin's branch.
// Prints the folder to start Claude in.
const WORKTREE = `set -e
name="$1" branch="$2"
repo=$(find "$HOME/projects" -maxdepth 3 -type d -name "$name" -exec test -e {}/.git \\; -print -quit)
[ -n "$repo" ] || { echo "no checkout of $name under ~/projects" >&2; exit 2; }
existing=$(git -C "$repo" worktree list --porcelain | awk -v b="refs/heads/$branch" '/^worktree /{p=substr($0,10)} $0=="branch "b{print p; exit}')
[ -n "$existing" ] && { echo "$existing"; exit 0; }
git -C "$repo" fetch --quiet origin "$branch" >&2
if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
  wt new "$repo" "$branch"
else
  dir=$(wt new "$repo" "$branch" "origin/$branch")
  git -C "$dir" branch --quiet --set-upstream-to "origin/$branch" >&2
  echo "$dir"
fi`;

const ago = (iso) => {
  const m = Math.max(0, Math.round((Date.now() - Date.parse(iso)) / 60000));
  if (m < 60) return `${m}m`;
  if (m < 60 * 24) return `${Math.round(m / 60)}h`;
  return `${Math.round(m / 1440)}d`;
};

export default class Prs extends View {
  init(_props, cx) {
    this.data = shared(CACHE) ?? null;
    this.error = null;
    this.loading = false;
    this.busy = null;
    this.sel = 0;
    this.handle = cx.focus_handle();
    this.handle.focus();
    if (checking()) return;
    this.refresh(cx);
    cx.timer.every(60000, (cx) => this.refresh(cx));
  }

  rows() {
    const d = this.data ?? { mine: [], review: [] };
    return [...d.review.map((pr) => ({ pr, review: true })), ...d.mine.map((pr) => ({ pr, review: false }))];
  }

  refresh(cx) {
    if (this.loading) return;
    this.loading = true;
    cx.notify();
    cx.spawn(async (cx) => {
      const r = await exec("gh", ["api", "graphql", "-f", `query=${QUERY}`], { timeout: 30000 }).catch((e) => ({ code: 1, stderr: String(e) }));
      this.loading = false;
      if (r.code === 0) {
        const d = JSON.parse(r.stdout).data;
        this.data = { mine: d.mine.nodes.filter((n) => n.number), review: d.review.nodes.filter((n) => n.number), at: Date.now() };
        this.error = null;
        setShared(CACHE, this.data);
      } else {
        this.error = (r.stderr || "gh failed").trim().split("\n")[0];
      }
      this.sel = Math.min(this.sel, Math.max(0, this.rows().length - 1));
      cx.notify();
    });
  }

  browse(pr) {
    exec("open", [pr.url]);
  }

  claude(pr, cx) {
    if (this.busy) return;
    this.busy = pr.url;
    cx.notify();
    cx.spawn(async (cx) => {
      const r = await exec("sh", ["-c", WORKTREE, "prs", pr.repository.name, pr.headRefName], { cwd: home(), timeout: 120000 }).catch((e) => ({ code: 1, stderr: String(e) }));
      this.busy = null;
      if (r.code !== 0) {
        notify({ title: `#${pr.number}: no worktree`, body: (r.stderr || "").trim().split("\n").pop(), level: "error" });
        cx.notify();
        return;
      }
      const folder = r.stdout.trim().split("\n").pop();
      closeOverlay(props().overlay);
      run("space.new", { folder, argv: ["claude"] });
    });
  }

  render(cx) {
    const t = theme();
    const rows = this.rows();
    const ci = (pr) => pr.commits?.nodes?.[0]?.commit?.statusCheckRollup?.state ?? null;
    const ciColor = (s) => ({ SUCCESS: t.done, FAILURE: t.blocked, ERROR: t.blocked, PENDING: t.working, EXPECTED: t.working })[s] ?? t.dim;
    const review = { APPROVED: ["approved", t.done], CHANGES_REQUESTED: ["changes", t.blocked], REVIEW_REQUIRED: ["review", t.muted] };

    const row = ({ pr }, i) => {
      const lit = i === this.sel;
      const rd = review[pr.reviewDecision];
      return h_flex()
        .id(`pr-${i}`)
        .h(44)
        .px(12)
        .gap(10)
        .items_center()
        .rounded(6)
        .cursor_pointer()
        .when(lit, (s) => s.bg(t.selected))
        .hover((s) => s.bg(lit ? t.selected : t.hover))
        .on_click((_e, cx) => { this.sel = i; this.claude(pr, cx); })
        .child(div().w(8).h(8).rounded(4).flex_none().bg(ciColor(ci(pr))))
        .child(
          v_flex().flex_1().min_w(0)
            .child(h_flex().gap(6).items_center()
              .child(div().truncate().text_color(t.foreground).child(pr.title))
              .when(pr.isDraft, (s) => s.child(div().flex_none().px(5).rounded(4).border(1).border_color(t.border).text_size(10).text_color(t.dim).child("draft"))))
            .child(h_flex().gap(6).text_size(11).text_color(t.dim)
              .child(div().child(`${pr.repository.name} #${pr.number}`))
              .child(div().truncate().child(pr.headRefName))))
        .when(rd, (s) => s.child(div().flex_none().text_size(11).text_color(rd[1]).child(rd[0])))
        .child(div().flex_none().w(28).text_size(11).text_color(t.dim).child(ago(pr.updatedAt)))
        .child(div().id(`open-${i}`).flex_none().text_size(11).text_color(t.muted).px(6).rounded(4).hover((s) => s.bg(t.raised))
          .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
          .on_click(() => this.browse(pr)).child("↗"))
        .when(this.busy === pr.url, (s) => s.child(div().flex_none().text_size(11).text_color(t.working).child("…")));
    };

    const section = (label, count) =>
      div().px(12).pt(10).pb(4).text_size(11).text_color(t.dim).child(`${label} · ${count}`);

    const d = this.data ?? { mine: [], review: [] };
    const list = [];
    let i = 0;
    if (d.review.length) { list.push(section("Review angefragt", d.review.length)); d.review.forEach((pr) => list.push(row({ pr, review: true }, i++))); }
    list.push(section("Deine PRs", d.mine.length));
    d.mine.forEach((pr) => list.push(row({ pr, review: false }, i++)));
    if (!d.mine.length && this.data) list.push(div().px(12).py(8).text_color(t.dim).child("Keine offenen PRs."));

    return v_flex()
      .id("prs")
      .track_focus(this.handle)
      .on_key_down((e, cx) => {
        const n = rows.length;
        if (e.key === "escape") closeOverlay(props().overlay);
        else if (e.key === "down" && n) this.sel = (this.sel + 1) % n;
        else if (e.key === "up" && n) this.sel = (this.sel - 1 + n) % n;
        else if (e.key === "enter" && n) this.claude(rows[this.sel].pr, cx);
        else if (e.key === "o" && n) this.browse(rows[this.sel].pr);
        else if (e.key === "r") this.refresh(cx);
        else return;
        cx.stop_propagation();
        cx.notify();
      })
      .size_full()
      .min_h(0)
      .p(8)
      .rounded(8)
      .bg(t.popover)
      .text_size(13)
      .child(h_flex().px(12).h(36).items_center().gap(8)
        .child(div().flex_1().text_size(15).font_semibold().text_color(t.foreground).child("Pull Requests"))
        .when(this.loading, (s) => s.child(div().text_size(11).text_color(t.working).child("lädt…")))
        .child(div().text_size(11).text_color(t.dim).child("Esc")))
      .when(this.error, (s) => s.child(div().px(12).py(6).text_size(12).text_color(t.blocked).child(this.error)))
      .child(v_flex().flex_1().min_h(0).overflow_y_scrollbar().children(list))
      .child(h_flex().px(12).h(28).items_center().gap(14).text_size(11).text_color(t.dim)
        .child("↵ Claude im Worktree").child("o Browser").child("r neu laden")
        .child(div().flex_1())
        .child(h_flex().gap(4).items_center().child(div().w(6).h(6).rounded(3).bg(t.done)).child("CI ok"))
        .child(h_flex().gap(4).items_center().child(div().w(6).h(6).rounded(3).bg(t.blocked)).child("CI rot")));
  }
}
