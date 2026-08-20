#!/usr/bin/env bash
#
# tmux-worktreeizer -- pick a git worktree and open a tmux session for it.
#
# Two modes, toggled with the backtick key:
#
#   repos       one row per repo. Enter opens that folder:
#
#                 ~/work/ctm            [master]   pushed   2 worktrees
#                 ~/work/ctm-chat       [master]   pushed
#
#               enter on ~/work/ctm gives its own worktrees, and this is
#               the only place the create row lives:
#
#                 ~/work/ctm            [master]   pushed
#                 |- create new worktree (ctm)
#                 |- ctm/hal-1234-thing [hal-1234-thing]  +2  PR #10717 open
#
#   worktrees   every worktree in every repo, flattened into one list, with
#               no group headers and no create rows:
#
#                 ctm                   [master]   pushed
#                 ctm/hal-1234-thing    [hal-1234-thing]  +2  PR #10717 open
#                 ctm-ui/busy-gould     [(detached)]      detached  agent
#
# ctrl-t creates a worktree in whichever repo the cursor is on, from either
# mode, so you never have to walk into a folder just to make one.
#
# Searching:
#   Type any part of a repo name to pull up that repo and everything in it.
#   Every row carries its repo name for this reason -- fzf can only match on
#   what it displays, so a bare worktree name would not be enough.
#
# Columns:
#   *          a tmux session is already open for this worktree
#   name       repo/worktree (the repo path itself on a group header)
#   [branch]   what is checked out, shown when it differs from the directory
#   status     see below
#   PR #n      from the cached pull request list, empty if nothing matched
#   tags       agent, locked, prunable, bare
#
# Status:
#   pushed     has an upstream and matches it
#   +2 / -1    commits ahead of / behind the upstream
#   no-remote  a branch with no upstream set, so nothing has been pushed
#   gone       had an upstream, but that remote branch is gone now
#   detached   not on a branch at all, just parked on a commit
#
# Tags:
#   agent      lives under .claude/worktrees or .codex/worktrees
#   locked     git worktree lock was used, removal needs the force prompt
#   prunable   git thinks this one is stale and can be pruned
#
# Usage:
#   tmux-worktreeizer          the picker
#   tmux-worktreeizer --new    skip the picker, create a worktree in this repo
#
# Keys:
#   enter      in the repo list, open that folder; anywhere else, open (or
#              switch to) the tmux session, or start the create flow
#   `          swap between the repo list and the flat worktree list, or
#              step back out of a folder you opened
#   backspace  step out of a folder, once the query is empty. While there is
#              something typed it deletes characters as usual.
#   ctrl-t     create a worktree in the repo the cursor is on
#   tab        jump to the next repo, wrapping at the end
#   shift-tab  jump back to the previous repo
#   ctrl-x     remove the selected worktree and kill its tmux session
#   ctrl-r     refresh the pull request cache for the selected repo
#   ctrl-s     git fetch --prune the selected repo
#   ctrl-o     open the pull request for the selected worktree in a browser
#
# These stay off the keys fzf already uses to move and edit: ctrl-a b c d e
# f g h i j l m n p q u w y and ctrl-/. Only tab is reused, and only because
# its default (toggle+down) needs --multi, which this does not use.
#
# Environment:
#   TW_ROOT            where new worktrees go   (default ~/work/.worktrees)
#   TW_ROOTS           colon separated dirs scanned for repos
#   TW_REPOS           colon separated extra repo paths
#   TW_BRANCH_PREFIX   pre-filled prefix when naming a brand new branch
#   TW_PR_TTL          seconds before the pull request cache goes stale
#   TW_NO_FETCH        set to skip the fetch in the create flow
#
# A post-create hook at ~/.config/tmux-worktreeizer/post-create (executable)
# is run as: post-create <repo> <worktree-path> <branch>

set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
TAB=$'\t'

TW_ROOT="${TW_ROOT:-$HOME/work/.worktrees}"
TW_ROOTS="${TW_ROOTS:-$HOME/work:$HOME/Code/work:$HOME/Code/lrn:$HOME/Code/seth}"
TW_REPOS="${TW_REPOS:-$HOME/dotfiles}"
TW_PR_TTL="${TW_PR_TTL:-900}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-worktreeizer"
HOOK="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-worktreeizer/post-create"

# ---------------------------------------------------------------- helpers

die() {
  printf 'tmux-worktreeizer: %s\n' "$*" >&2
  exit 1
}

pause() {
  [[ -t 0 ]] || return 0
  read -rsn1 -p "press any key to continue..." _ || true
  printf '\n'
}

slug() {
  printf '%s' "$1" |
    tr 'A-Z/ ' 'a-z--' |
    sed -e 's/[^a-z0-9._-]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'
}

# Turn typed-in text into something git will accept as a branch name.
sanitize_branch() {
  printf '%s' "$1" |
    tr -s ' \t' '--' |
    sed -e 's|^/*||' -e 's|/*$||' -e 's|//*|/|g'
}

# Ask for a value with an editable default already filled in.
prompt_default() {
  local prompt=$1 def=$2 out=""
  if [[ -t 0 ]]; then
    read -r -e -i "$def" -p "$prompt" out || return 1
  else
    read -r -p "$prompt[$def] " out || return 1
    out="${out:-$def}"
  fi
  printf '%s' "$out"
}

repo_of() {
  local common
  common="$(git -C "${1:-$PWD}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  (cd "$common/.." && pwd)
}

main_worktree() {
  git -C "$1" worktree list --porcelain 2>/dev/null |
    awk '/^worktree /{print substr($0,10); exit}'
}

# Why a worktree is locked, empty when it is not. Agent tooling locks the
# worktrees it makes so git will not prune them while a session is running.
lock_reason() {
  git -C "$1" worktree list --porcelain 2>/dev/null |
    awk -v want="$2" '
      /^worktree /{ cur = substr($0, 10) }
      /^locked/ {
        if (cur != want) next
        reason = substr($0, 7)
        sub(/^ /, "", reason)
        print (reason == "" ? "(no reason given)" : reason)
        exit
      }'
}

default_branch() {
  local repo=$1 ref
  ref="$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  if [[ -n $ref ]]; then
    printf '%s' "$ref"
    return
  fi
  for ref in origin/master origin/main; do
    if git -C "$repo" rev-parse --verify --quiet "refs/remotes/$ref" >/dev/null; then
      printf '%s' "$ref"
      return
    fi
  done
  git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null
}

# Light or dark, so the highlighted row is readable either way. Prefers the
# symlink tmux-dark-notify keeps, since that is what tmux itself follows.
appearance() {
  local link
  link="$(readlink "${XDG_STATE_HOME:-$HOME/.local/state}/tmux/tmux-dark-notify-theme.conf" 2>/dev/null)"
  case $link in
  *light*)
    printf 'light'
    return
    ;;
  *dark*)
    printf 'dark'
    return
    ;;
  esac
  if [[ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" == Dark ]]; then
    printf 'dark'
  else
    printf 'light'
  fi
}

sessions_at() {
  tmux list-sessions -F "#{session_path}${TAB}#{session_name}" 2>/dev/null |
    awk -F"$TAB" -v p="$1" '$1 == p {print $2}'
}

# ---------------------------------------------------------------- repos

repo_list() {
  local roots=() extra=() root dir
  IFS=: read -ra roots <<<"$TW_ROOTS"
  IFS=: read -ra extra <<<"$TW_REPOS"
  for root in "${roots[@]}"; do
    [[ -d $root ]] || continue
    for dir in "$root"/*/; do
      dir="${dir%/}"
      [[ -d "$dir/.git" ]] && printf '%s\n' "$dir"
    done
  done
  for dir in "${extra[@]}"; do
    [[ -n $dir && -d "$dir/.git" ]] && printf '%s\n' "$dir"
  done
}

has_extra_worktrees() {
  compgen -G "$1/.git/worktrees/*" >/dev/null 2>&1
}

# ---------------------------------------------------------------- pull requests

pr_cache_file() {
  printf '%s/pr%s.tsv' "$CACHE_DIR" "$(printf '%s' "$1" | tr '/ ' '__')"
}

refresh_prs() {
  local repo=$1 file tmp
  command -v gh >/dev/null 2>&1 || return 0
  file="$(pr_cache_file "$repo")"
  tmp="$file.$$"
  mkdir -p "$CACHE_DIR"
  if (cd "$repo" && gh pr list --state all --limit 200 \
    --json number,headRefName,state,isDraft,url \
    --jq '.[] | [.headRefName, (.number|tostring),
                 (if .state == "OPEN" and .isDraft then "draft"
                  else (.state|ascii_downcase) end), .url] | @tsv') >"$tmp" 2>/dev/null; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
  fi
}

pr_cache_stale() {
  local file age
  file="$(pr_cache_file "$1")"
  [[ -f $file ]] || return 0
  age=$(($(date +%s) - $(stat -f %m "$file")))
  ((age > TW_PR_TTL))
}

# Kick off cache refreshes for the repos that actually have worktrees.
refresh_prs_in_background() {
  local repo
  command -v gh >/dev/null 2>&1 || return 0
  while read -r repo; do
    has_extra_worktrees "$repo" || continue
    pr_cache_stale "$repo" || continue
    (refresh_prs "$repo" &) >/dev/null 2>&1
  done < <(repo_list)
}

# ---------------------------------------------------------------- listing

PORCELAIN_AWK='
function emit() { print p "\t" b "\t" f }
/^worktree /   { if (p != "") emit(); p = substr($0, 10); b = ""; f = "" }
/^branch /     { b = substr($0, 8); sub(/^refs\/heads\//, "", b) }
/^detached$/   { b = "(detached)" }
/^locked/      { f = f (f ? "," : "") "locked" }
/^prunable/    { f = f (f ? "," : "") "prunable" }
/^bare$/       { f = f (f ? "," : "") "bare" }
END            { if (p != "") emit() }
'

RENDER_AWK='
function tildify(p) {
  if (index(p, HOME) == 1) return "~" substr(p, length(HOME) + 1)
  return p
}
function pad(s, w) {
  if (length(s) > w) return substr(s, 1, w - 1) ">"
  while (length(s) < w) s = s " "
  return s
}
function spaces(k, s) { s = ""; while (k-- > 0) s = s " "; return s }
# Pad by the width of the plain text, so ANSI codes do not break alignment.
function padkeep(plain, w, colored) {
  if (length(plain) > w) return substr(plain, 1, w - 1) ">"
  return colored spaces(w - length(plain))
}
function paint(s, c) {
  if (!color || c == "" || s == "") return s
  return "\033[" c "m" s "\033[0m"
}
function base(p, a, k) { k = split(p, a, "/"); return a[k] }
# Some tools nest worktrees as <hash>/<repo-name>, so the last component
# alone tells you nothing. Fall back to the parent in that case.
function label(p, a, k) {
  k = split(p, a, "/")
  if (k > 1 && a[k] == base(repo)) return a[k - 1] "/" a[k]
  return a[k]
}
function isagent(p) {
  return (index(p, "/.claude/worktrees/") || index(p, "/.codex/worktrees/")) ? 1 : 0
}
function statustxt(b, t) {
  if (b == "" || b == "(detached)") return "detached"
  if (up[b] == "") return "no-remote"
  t = track[b]
  if (t == "") return "pushed"
  gsub(/[\[\]]/, "", t)
  if (t == "gone") return "gone"
  gsub(/ahead /, "+", t); gsub(/behind /, "-", t); gsub(/, /, "/", t)
  return t
}
function statuscolor(s) {
  if (s == "pushed")    return "32"
  if (s == "no-remote") return "33"
  if (s == "gone")      return "31"
  if (s == "detached")  return "35"
  return "36"
}
function prtxt(b) {
  if (b == "" || !(b in prnum)) return ""
  return "PR #" prnum[b] " " prstate[b]
}
function prcolor(b, s) {
  s = prstate[b]
  if (s == "open")   return "32"
  if (s == "draft")  return "33"
  if (s == "merged") return "35"
  if (s == "closed") return "31"
  return ""
}
function mark(p) { return (p in sess) ? "*" : " " }
function prurlof(b) { return (b in prurl) ? prurl[b] : "" }

$1 == "B" { up[$2] = $3; track[$2] = $4 }
$1 == "P" { if (!($2 in prnum)) { prnum[$2] = $3; prstate[$2] = $4; prurl[$2] = $5 } }
$1 == "S" { sess[$2] = $3 }
$1 == "W" { n++; wpath[n] = $2; wbranch[n] = $3; wflags[n] = $4 }

END {
  if (n == 0) exit
  rname = base(repo)
  hb = wbranch[1]
  hst = statustxt(hb)

  # One row per repo. Enter on it drills into that repo.
  if (view == "repos") {
    extra = n - 1
    print "repo", repo, wpath[1], hb, prurlof(hb), \
          paint(mark(wpath[1]), "36") " " \
          paint(pad(tildify(wpath[1]), 40), REPO_C) " " \
          paint(pad("[" hb "]", 24), "90") " " \
          paint(pad(hst, 10), statuscolor(hst)) " " \
          paint(pad(prtxt(hb), 17), prcolor(hb)) " " \
          paint(extra > 0 ? extra " worktree" (extra == 1 ? "" : "s") : "", "90")
    exit
  }

  if (view == "flat") {
    # The main checkout is a worktree too, so it belongs in the flat list.
    print "repo", repo, wpath[1], hb, prurlof(hb), \
          paint(mark(wpath[1]), "36") " " \
          paint(pad(rname, 40), REPO_C) " " \
          paint(pad("[" hb "]", 24), "90") " " \
          paint(pad(hst, 10), statuscolor(hst)) " " \
          paint(pad(prtxt(hb), 17), prcolor(hb))
  } else {
    print "repo", repo, wpath[1], hb, prurlof(hb), \
          paint(mark(wpath[1]), "36") " " \
          paint(pad(tildify(wpath[1]), 40), REPO_C) " " \
          paint(pad("[" hb "]", 24), "90") " " \
          paint(pad(hst, 10), statuscolor(hst)) " " \
          paint(prtxt(hb), prcolor(hb))
    print "new", repo, "", "", "", \
          "  " paint(pad("|- create new worktree", 40), "32") " " \
          paint("(" rname ")", "90")
  }

  for (agent = 0; agent < 2; agent++) {
    for (i = 2; i <= n; i++) {
      if (isagent(wpath[i]) != agent) continue
      b = wbranch[i]
      st = statustxt(b)
      name = label(wpath[i])
      shown = (b == "" || b == name) ? "" : "[" b "]"
      tag = wflags[i]
      if (agent) tag = tag (tag ? "," : "") "agent"
      # The repo name rides along on every row so that typing it filters the
      # whole group -- fzf can only search what it displays.
      pre = (view == "flat") ? "" : "|- "
      print "wt", repo, wpath[i], b, prurlof(b), \
            paint(mark(wpath[i]), "36") " " \
            padkeep(pre rname "/" name, 40, \
                    pre paint(rname "/", "90") name) " " \
            paint(pad(shown, 24), "90") " " \
            paint(pad(st, 10), statuscolor(st)) " " \
            paint(pad(prtxt(b), 17), prcolor(b)) " " \
            paint(tag, "90")
    }
  }
  if (view == "group") print "sep", repo, "", "", "", " "
}
'

render_repo() {
  local repo=$1 sess_file=$2 view=${3:-group} pr_file
  pr_file="$(pr_cache_file "$repo")"
  {
    git -C "$repo" for-each-ref \
      --format="B${TAB}%(refname:short)${TAB}%(upstream:short)${TAB}%(upstream:track)" \
      refs/heads 2>/dev/null
    [[ -f $pr_file ]] && sed "s|^|P${TAB}|" "$pr_file"
    cat "$sess_file"
    git -C "$repo" worktree list --porcelain 2>/dev/null |
      awk "$PORCELAIN_AWK" | sed "s|^|W${TAB}|"
  } | awk -F"$TAB" -v OFS="$TAB" -v repo="$repo" -v HOME="$HOME" -v color=1 \
    -v view="$view" -v REPO_C="1;34" "$RENDER_AWK"
}

list_view() {
  local view=$1 only=${2:-} tmpdir sess_file here repo key i=0
  tmpdir="$(mktemp -d)"
  sess_file="$tmpdir/sessions"
  tmux list-sessions -F "S${TAB}#{session_path}${TAB}#{session_name}" 2>/dev/null >"$sess_file" || :
  touch "$sess_file"

  if [[ -n $only ]]; then
    render_repo "$only" "$sess_file" "$view"
    rm -rf "$tmpdir"
    return
  fi

  here="$(repo_of "$PWD" 2>/dev/null)" || here=""

  # The repo you are standing in first, then repos that already have
  # worktrees, then the rest.
  while read -r repo; do
    if [[ -n $here && $repo == "$here" ]]; then
      key=0
    elif has_extra_worktrees "$repo"; then
      key=1
    else
      key=2
    fi
    printf '%s\t%s\t%s\n' "$key" "$(basename "$repo")" "$repo"
  done < <(repo_list) | sort -t"$TAB" -k1,1 -k2,2 >"$tmpdir/repos"

  while IFS="$TAB" read -r _ _ repo; do
    i=$((i + 1))
    render_repo "$repo" "$sess_file" "$view" >"$tmpdir/out.$(printf '%04d' "$i")" &
  done <"$tmpdir/repos"
  wait

  cat "$tmpdir"/out.* 2>/dev/null
  rm -rf "$tmpdir"
}

# ---------------------------------------------------------------- views

# Which view the picker is showing, kept in one fixed file so that fzf's
# reload and transform bindings all see the same thing. A fixed path rather
# than a temp dir, because ctrl-t replaces this process and would never get
# the chance to clean a temp one up.
state_file() { printf '%s/view' "${TW_STATE:-$CACHE_DIR}"; }

view_read() {
  local file
  file="$(state_file)"
  if [[ -f $file ]]; then
    cat "$file"
  else
    printf 'repos\t\n'
  fi
}

view_write() { printf '%s\t%s\n' "$1" "$2" >"$(state_file)"; }

# The actions fzf should run to show the current view.
view_actions() {
  local mode=$1 drill=$2 prompt
  if [[ -n $drill ]]; then
    prompt="$(basename "$drill")> "
  elif [[ $mode == flat ]]; then
    prompt='worktrees> '
  else
    prompt='repos> '
  fi
  printf 'reload(%s --view-list)+change-prompt(%s)+first' "$SELF" "$prompt"
}

do_view_list() {
  local mode drill
  IFS="$TAB" read -r mode drill <<<"$(view_read)"
  if [[ -n $drill ]]; then
    list_view tree "$drill"
  elif [[ $mode == flat ]]; then
    list_view flat
  else
    list_view repos
  fi
}

# The backtick key: leave a drilled-in repo, or flip between the two modes.
do_view_toggle() {
  local mode drill
  IFS="$TAB" read -r mode drill <<<"$(view_read)"
  if [[ -n $drill ]]; then
    drill=""
  elif [[ $mode == repos ]]; then
    mode=flat
  else
    mode=repos
  fi
  view_write "$mode" "$drill"
  view_actions "$mode" "$drill"
}

# Backspace steps out of a folder, but only once the query is empty --
# otherwise it has to keep deleting characters like it normally would.
do_view_back() {
  local query=${1:-} mode drill
  if [[ -n $query ]]; then
    printf 'backward-delete-char'
    return 0
  fi
  IFS="$TAB" read -r mode drill <<<"$(view_read)"
  if [[ -n $drill ]]; then
    view_write "$mode" ""
    view_actions "$mode" ""
  else
    printf 'ignore'
  fi
}

# Enter drills into a repo when browsing repos, and otherwise just accepts.
do_view_enter() {
  local kind=${1:-} repo=${2:-} mode drill
  IFS="$TAB" read -r mode drill <<<"$(view_read)"
  if [[ -z $drill && $mode == repos && $kind == repo && -n $repo ]]; then
    view_write "$mode" "$repo"
    view_actions "$mode" "$repo"
  else
    printf 'accept'
  fi
}

# Every repo with its worktrees under it, the old grouped listing.
list_all() { list_view group; }

# ---------------------------------------------------------------- preview

C_OFF=$'\033[0m'
C_DIM=$'\033[90m'
C_BOLD=$'\033[1m'
C_TITLE=$'\033[1;34m'

pv_field() { printf '%s%-9s%s %s\n' "$C_DIM" "$1" "$C_OFF" "$2"; }
pv_section() { printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_OFF"; }
pv_paint() { printf '\033[%sm%s%s' "$1" "$2" "$C_OFF"; }

pv_status_color() {
  case $1 in
  pushed) printf '32' ;;
  no-remote) printf '33' ;;
  gone) printf '31' ;;
  detached) printf '35' ;;
  *) printf '36' ;;
  esac
}

pv_pr_color() {
  case $1 in
  open) printf '32' ;;
  draft) printf '33' ;;
  merged) printf '35' ;;
  closed) printf '31' ;;
  *) printf '90' ;;
  esac
}

do_preview() {
  local kind=${1:-} repo=${2:-} path=${3:-} branch=${4:-}
  local rname pr_file upstream track sessions locked
  local changed untracked stat state num url

  case $kind in
  sep | '') return 0 ;;
  new)
    rname="$(basename "$repo")"
    printf '%screate a new worktree in %s%s\n\n' "$C_TITLE" "$rname" "$C_OFF"
    pv_field 'base' 'an existing branch, or a new one off the default branch'
    pv_field 'path' "${TW_ROOT/#$HOME/~}/$rname/$C_DIM<name>$C_OFF"
    pv_field 'name' 'you get a prompt with a suggestion already filled in'
    pv_section 'worktrees that exist now'
    git -C "$repo" worktree list 2>/dev/null | sed "s|^|  |;s|$HOME|~|"
    return 0
    ;;
  esac

  rname="$(basename "$repo")"

  # Title: which worktree this is, then where it lives.
  if [[ $path == "$repo" ]]; then
    printf '%s%s%s %s(the repo itself)%s\n' "$C_TITLE" "$rname" "$C_OFF" "$C_DIM" "$C_OFF"
  else
    printf '%s%s/%s%s\n' "$C_TITLE" "$rname" "$(basename "$path")" "$C_OFF"
  fi
  printf '%s%s%s\n\n' "$C_DIM" "${path/#$HOME/~}" "$C_OFF"

  if [[ -n $branch ]]; then
    pv_field 'branch' "$branch"
  else
    pv_field 'branch' "$(pv_paint 35 'detached head')"
  fi

  # Upstream, and how far from it.
  if [[ -n $branch ]]; then
    upstream="$(git -C "$repo" for-each-ref --format='%(upstream:short)' \
      "refs/heads/$branch" 2>/dev/null)"
    track="$(git -C "$repo" for-each-ref --format='%(upstream:track)' \
      "refs/heads/$branch" 2>/dev/null)"
    if [[ -z $upstream ]]; then
      pv_field 'upstream' "$(pv_paint 33 'none, nothing pushed yet')"
    elif [[ $track == '[gone]' ]]; then
      pv_field 'upstream' "$upstream $(pv_paint 31 'gone from the remote')"
    elif [[ -z $track ]]; then
      pv_field 'upstream' "$upstream $(pv_paint 32 'in sync')"
    else
      pv_field 'upstream' "$upstream $(pv_paint 36 "$track")"
    fi
  fi

  # Working tree state.
  if [[ -d $path ]]; then
    changed="$(git -C "$path" status --porcelain --untracked-files=no 2>/dev/null | wc -l | tr -d ' ')"
    untracked="$(git -C "$path" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')"
    stat="$(git -C "$path" diff --shortstat 2>/dev/null | sed 's/^ *//')"
    if ((changed == 0 && untracked == 0)); then
      pv_field 'files' "$(pv_paint 32 'clean')"
    else
      pv_field 'files' "$(pv_paint 33 "$changed changed, $untracked untracked")${stat:+  $C_DIM$stat$C_OFF}"
    fi
  else
    pv_field 'files' "$(pv_paint 31 'the directory is missing')"
  fi

  sessions="$(sessions_at "$path" | paste -sd, -)"
  if [[ -n $sessions ]]; then
    pv_field 'session' "$(pv_paint 32 "$sessions")"
  else
    pv_field 'session' "$(pv_paint 90 'none open')"
  fi

  # Pull request, from the cache.
  pr_file="$(pr_cache_file "$repo")"
  if [[ -z $branch ]]; then
    pv_field 'pr' "$(pv_paint 90 'no branch, so no pull request')"
  elif [[ ! -f $pr_file ]]; then
    pv_field 'pr' "$(pv_paint 90 'not fetched yet, ctrl-r to look')"
  else
    IFS="$TAB" read -r num state url < <(awk -F"$TAB" -v b="$branch" \
      '$1 == b {print $2 "\t" $3 "\t" $4; exit}' "$pr_file")
    if [[ -n ${num:-} ]]; then
      pv_field 'pr' "$(pv_paint "$(pv_pr_color "$state")" "#$num $state")  $C_DIM$url$C_OFF"
    else
      pv_field 'pr' "$(pv_paint 90 'none found for this branch')"
    fi
  fi

  locked="$(lock_reason "$repo" "$path")"
  [[ -n $locked ]] && pv_field 'locked' "$(pv_paint 33 "$locked")"

  [[ -d $path ]] || return 0

  # Commits that only exist here are the ones worth seeing first.
  if [[ -n $branch ]] && git -C "$path" rev-parse --verify --quiet '@{u}' >/dev/null 2>&1; then
    if [[ -n "$(git -C "$path" log --oneline '@{u}..HEAD' 2>/dev/null)" ]]; then
      pv_section 'not pushed yet'
      git -C "$path" log --color=always --oneline --decorate '@{u}..HEAD' 2>/dev/null |
        head -10 | sed 's|^|  |'
    fi
  fi

  if ((changed > 0 || untracked > 0)); then
    pv_section 'changes'
    git -C "$path" -c color.status=always status --short 2>/dev/null | head -20 | sed 's|^|  |'
  fi

  pv_section 'recent commits'
  git -C "$path" log --color=always --oneline --decorate -8 2>/dev/null | sed 's|^|  |'
}

# ---------------------------------------------------------------- jumping

# Print an fzf action that moves the cursor to the next or previous repo
# header. Arguments are the kind of every row fzf is currently showing, in
# order, and FZF_POS says which one the cursor is on.
do_jump() {
  local direction=$1 pos=${FZF_POS:-1} count i
  shift
  count=$#
  ((count > 0)) || return 0

  if [[ $direction == next ]]; then
    for ((i = pos + 1; i <= count; i++)); do
      [[ ${!i} == repo ]] && {
        printf 'pos(%d)' "$i"
        return 0
      }
    done
    for ((i = 1; i <= pos; i++)); do
      [[ ${!i} == repo ]] && {
        printf 'pos(%d)' "$i"
        return 0
      }
    done
  else
    for ((i = pos - 1; i >= 1; i--)); do
      [[ ${!i} == repo ]] && {
        printf 'pos(%d)' "$i"
        return 0
      }
    done
    for ((i = count; i > pos; i--)); do
      [[ ${!i} == repo ]] && {
        printf 'pos(%d)' "$i"
        return 0
      }
    done
  fi
}

# ---------------------------------------------------------------- sessions

session_name_for() {
  local repo=$1 path=$2 name
  if [[ $path == "$repo" ]]; then
    name="$(basename "$repo")"
  else
    name="$(basename "$repo")/$(basename "$path")"
  fi
  printf '%s' "${name//[.:]/_}"
}

open_session() {
  local repo=$1 path=$2 name
  [[ -d $path ]] || {
    printf 'worktree directory is gone: %s\n' "$path"
    pause
    return 1
  }

  name="$(sessions_at "$path" | head -1)"
  [[ -n $name ]] || name="$(session_name_for "$repo" "$path")"

  if ! tmux has-session -t "=$name" 2>/dev/null; then
    tmux new-session -ds "$name" -c "$path" -n editor "nvim; exec $SHELL"
    tmux new-window -t "=$name:" -c "$path" -n server
    tmux new-window -t "=$name:" -c "$path" -n shell
    tmux select-window -t "=$name:editor"
  fi

  if [[ -n ${TMUX:-} ]]; then
    tmux switch-client -t "=$name"
  else
    tmux attach-session -t "=$name"
  fi
}

# ---------------------------------------------------------------- create

branch_choices() {
  local repo=$1
  {
    git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null
    comm -23 \
      <(git -C "$repo" for-each-ref --format='%(refname:short)' refs/remotes 2>/dev/null |
        sed 's|^[^/]*/||' | grep -v '^HEAD$' | sort -u) \
      <(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null | sort -u) |
      sed 's|^|remote: |'
  } | grep -v '^$'
}

create_worktree() {
  local repo=$1 rname base branch name path defbranch remote_ref out
  rname="$(basename "$repo")"
  defbranch="$(default_branch "$repo")"

  if [[ -z ${TW_NO_FETCH:-} ]]; then
    printf 'fetching %s...\n' "$rname"
    git -C "$repo" fetch --quiet --prune 2>/dev/null
  fi

  base="$(
    {
      printf 'new branch from %s\n' "$defbranch"
      branch_choices "$repo"
    } | fzf --reverse --prompt="base for new worktree in $rname> " --height='100%'
  )" || return 0
  [[ -n $base ]] || return 0

  if [[ $base == "new branch from "* ]]; then
    branch="$(prompt_default "new branch name> " "${TW_BRANCH_PREFIX:-}")" || return 0
    [[ -n $branch ]] || return 0
    branch="$(sanitize_branch "$branch")"
    if [[ -z $branch ]] || ! git check-ref-format "refs/heads/$branch" 2>/dev/null; then
      printf 'git will not accept that as a branch name: %s\n' "$branch"
      pause
      return 1
    fi
    name="$(slug "$branch")"
    path="$TW_ROOT/$rname/$name"
    [[ -e $path ]] && {
      printf 'already exists: %s\n' "$path"
      pause
      return 1
    }
    mkdir -p "$(dirname "$path")"
    # --no-track, or git points the new branch's upstream at the base branch
    # and the status column would call it "pushed" before it ever is.
    if ! out="$(git -C "$repo" worktree add --no-track -b "$branch" "$path" "$defbranch" 2>&1)"; then
      printf '%s\n' "$out"
      pause
      return 1
    fi
  else
    branch="${base#remote: }"
    name="$(prompt_default "worktree name> " "$(slug "$branch")")" || return 0
    name="$(slug "$name")"
    [[ -n $name ]] || return 0
    path="$TW_ROOT/$rname/$name"
    [[ -e $path ]] && {
      printf 'already exists: %s\n' "$path"
      pause
      return 1
    }
    mkdir -p "$(dirname "$path")"
    if git -C "$repo" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
      out="$(git -C "$repo" worktree add "$path" "$branch" 2>&1)" || {
        printf '%s\n' "$out"
        pause
        return 1
      }
    else
      remote_ref="$(git -C "$repo" for-each-ref --format='%(refname:short)' \
        "refs/remotes/*/$branch" 2>/dev/null | head -1)"
      [[ -n $remote_ref ]] || remote_ref="origin/$branch"
      out="$(git -C "$repo" worktree add --track -b "$branch" "$path" "$remote_ref" 2>&1)" || {
        printf '%s\n' "$out"
        pause
        return 1
      }
    fi
  fi

  printf 'created %s\n' "$path"
  [[ -x $HOOK ]] && "$HOOK" "$repo" "$path" "$branch"

  open_session "$repo" "$path"
}

# ---------------------------------------------------------------- remove

do_remove() {
  local kind=${1:-} repo=${2:-} path=${3:-} branch=${4:-} main answer out changed current locked
  if [[ $kind != wt ]]; then
    printf 'nothing to remove here -- pick a worktree line (this is a "%s" line).\n' "${kind:-blank}"
    pause
    return 0
  fi

  main="$(main_worktree "$repo")"
  if [[ $path == "$main" ]]; then
    printf 'refusing to remove the main checkout: %s\n' "$path"
    pause
    return 0
  fi

  changed="$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  locked="$(lock_reason "$repo" "$path")"
  printf 'remove worktree\n'
  printf '  path    %s\n' "$path"
  printf '  branch  %s\n' "${branch:-(detached)}"
  printf '  dirty   %s file(s)\n' "$changed"
  printf '  session %s\n' "$(sessions_at "$path" | paste -sd, - || true)"
  [[ -n $locked ]] && printf '  locked  %s\n' "$locked"
  printf 'the branch itself is kept.\n'
  read -rp "remove it? [y/N] " answer || return 0
  [[ $answer == [yY]* ]] || return 0

  if ! out="$(git -C "$repo" worktree remove "$path" 2>&1)"; then
    printf '%s\n' "$out"
    read -rp "force removal (throws away changes, ignores the lock)? [y/N] " answer || return 0
    [[ $answer == [yY]* ]] || return 0
    # Twice: git wants a second --force before it will touch a locked worktree.
    if ! out="$(git -C "$repo" worktree remove --force --force "$path" 2>&1)"; then
      printf '%s\n' "$out"
      pause
      return 1
    fi
  fi
  git -C "$repo" worktree prune 2>/dev/null

  # Move the client off the session before killing it, so this popup survives.
  current="$(tmux display-message -p '#{session_name}' 2>/dev/null)"
  while read -r session; do
    [[ -n $session ]] || continue
    if [[ $session == "$current" ]]; then
      tmux switch-client -l 2>/dev/null || tmux switch-client -n 2>/dev/null
    fi
    tmux kill-session -t "=$session" 2>/dev/null
  done < <(sessions_at "$path")

  rmdir "$(dirname "$path")" 2>/dev/null
  printf 'removed %s\n' "$path"
}

# ---------------------------------------------------------------- ui

usage() {
  sed -n '2,/^set -uo/p' "$SELF" | sed -e 's/^# \{0,1\}//' -e '/^set -uo/d'
}

main_ui() {
  local line kind repo path backtick row_bg match
  command -v fzf >/dev/null 2>&1 || die "fzf is not installed"
  command -v tmux >/dev/null 2>&1 || die "tmux is not installed"

  refresh_prs_in_background

  mkdir -p "$CACHE_DIR"
  view_write repos ""
  backtick="$(printf '\140')"

  if [[ "$(appearance)" == dark ]]; then
    row_bg=237
    match=cyan
  else
    row_bg=254
    match=blue
  fi

  line="$(
    do_view_list | fzf \
      --ansi \
      --delimiter="$TAB" \
      --with-nth=6 \
      --reverse \
      --no-sort \
      --height='100%' \
      --prompt='repos> ' \
      --info=inline \
      --highlight-line \
      --pointer='>' \
      --scrollbar='|' \
      --ellipsis='>' \
      --color="bg+:$row_bg,fg+:-1:bold,hl:$match:bold,hl+:$match:bold" \
      --color='pointer:blue,prompt:blue:bold,gutter:-1' \
      --color='info:bright-black,header:bright-black,separator:bright-black' \
      --color='border:bright-black,scrollbar:bright-black,query:-1:bold' \
      --header='enter open   ` repos/worktrees   ctrl-t new   ctrl-x remove   ctrl-r prs   ctrl-s fetch   ctrl-o pr' \
      --preview "$SELF --preview {1} {2} {3} {4}" \
      --preview-window='right,50%,border-left,wrap' \
      --preview-label=' details ' \
      --color='preview-border:bright-black,preview-label:bold' \
      --bind "ctrl-x:execute($SELF --remove {1} {2} {3} {4})+reload($SELF --view-list)" \
      --bind "ctrl-r:execute($SELF --refresh {2})+reload($SELF --view-list)" \
      --bind "ctrl-s:execute($SELF --fetch {2})+reload($SELF --view-list)" \
      --bind "ctrl-o:execute-silent($SELF --open-pr {5})" \
      --bind "$backtick:transform:$SELF --view-toggle" \
      --bind "bspace:transform:$SELF --view-back {q}" \
      --bind "ctrl-t:become($SELF --new {2})" \
      --bind "enter:transform:$SELF --view-enter {1} {2}" \
      --bind "tab:transform:$SELF --jump next {*1}" \
      --bind "btab:transform:$SELF --jump prev {*1}"
  )" || return 0
  [[ -n $line ]] || return 0

  IFS="$TAB" read -r kind repo path _ <<<"$line"
  case $kind in
  repo | wt) open_session "$repo" "$path" ;;
  new) create_worktree "$repo" ;;
  *) return 0 ;;
  esac
}

case "${1:-}" in
--list) list_all ;;
--preview)
  shift
  do_preview "$@"
  ;;
--remove)
  shift
  do_remove "$@"
  ;;
--new)
  shift
  repo="$(repo_of "${1:-$PWD}")" || die "not inside a git repository"
  create_worktree "$repo"
  ;;
--refresh)
  shift
  [[ -n ${1:-} ]] || exit 0
  printf 'refreshing pull requests for %s...\n' "$(basename "$1")"
  refresh_prs "$1"
  ;;
--view-list) do_view_list ;;
--view-toggle) do_view_toggle ;;
--view-back)
  shift
  do_view_back "$@"
  ;;
--view-enter)
  shift
  do_view_enter "$@"
  ;;
--jump)
  shift
  do_jump "$@"
  ;;
--open-pr)
  shift
  [[ -n ${1:-} ]] || exit 0
  open "$1"
  ;;
--fetch)
  shift
  [[ -n ${1:-} ]] || exit 0
  printf 'fetching %s...\n' "$(basename "$1")"
  git -C "$1" fetch --prune
  ;;
-h | --help) usage ;;
'') main_ui ;;
*) die "unknown argument: $1" ;;
esac
