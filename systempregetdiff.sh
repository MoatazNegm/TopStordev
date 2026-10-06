#!/bin/sh
#
# systempregetdiff.sh
# ===================
#
# Preview a merge BEFORE doing it, then write down what you want done and let
# the script carry it out.
#
#     systempregetdiff.sh <from-branch> <into-branch>            preview + plan
#     systempregetdiff.sh <from> <into> --plan                  show the plan
#     systempregetdiff.sh <from> <into> --apply                 merge, then apply
#
#   <from>  the branch that would be merged IN   (left column,  green)
#   <into>  the branch that would receive it    (right column, cyan)
#
# Nothing is checked out while you preview.  The collision test is a real
# three way merge done by "git merge-tree --write-tree", which runs entirely
# inside git's object store, so no branch, HEAD, file or index is touched.
#
# THE INSTRUCTION FILE
#   Everything you decide is written to one plain text file PER BRANCH PAIR,
#   so a plan made for A->B is never applied to C->D.  The files live in
#   /root/.systempregetdiff_plans, named <from>__<into>.plan.  The file is
#   tab separated and meant to be read:
#
#       <repo> <action> <file> <arg1> <arg2>
#
#       TopStor  keep       sub/gen.py  from
#       TopStor  delete     sub/old.sh  -
#       TopStor  del-line   sub/cfg.py  CACHE = 1
#       TopStor  rep-line   sub/cfg.py  PORT = 80   PORT = 9090
#       TopStor  add-line   sub/cfg.py  CACHE = 1   VERBOSE = 1
#
#   keep       take the file from the 'from' or 'into' side instead of the
#              merged result
#   delete     remove the file after merging
#   del-line   drop every line equal to arg1
#   rep-line   replace those lines with arg2
#   add-line   insert arg2 after every line equal to arg1
#
#   Line rules match on CONTENT, not line number, so they still land in the
#   right place after the merge has moved every line.
#
# KEYS
#   summary       a file number opens it, p shows the plan, q next directory
#   file view     q back | space/b page | e edit the result | m mark file
#   edit screen   d delete a line | c change it | a add after it
#                 u undo | q or Esc when you are done
#
# COLOUR
#   The column tells you the branch; the colour only says added vs replaced.
#     left  column: green  = added      blue  = the other branch replaced it
#     right column: magenta= added      red   = the other branch replaced it
#   Cyan and yellow were dropped: cyan sat too close to green, yellow to orange.
#   The viewer is built into this script rather than using "less", because a
#   less with no terminfo entry silently strips every colour code.
#

REPOS="${SYSTEM_REPOS:-TopStor pace topstorweb}"
ROOT="${SYSTEM_ROOT:-}"
WIDTH="${SYSTEMDIFF_WIDTH:-170}"
# The instruction file belongs to ONE pair of branches, never to the tool.
# A single shared file made a plan for A->B look like it applied to C->D.
PLAN_DIR="${PREGETDIFF_PLANDIR:-/root/.systempregetdiff_plans}"
PLAN_FILE=""                 # filled in once the branch pair is known
PLAN_EXPLICIT=0              # 1 = --plan-file / PREGETDIFF_PLAN was given
LEGACY_PLAN="${PREGETDIFF_LEGACY_PLAN:-/root/.systempregetdiff_plan}"
OPT_FETCH=0
OPT_SUMMARY=0
OPT_PLAN=0
OPT_PLANS=0
OPT_APPLY=0
PAGER_MODE=builtin

# ---------------------------------------------------------------------------
# Paths that are never worth comparing.
#
# systempush.sh stopped committing these a while ago: they are build caches,
# archives, source maps and vendored libraries that arrive with the deployment
# image and get regenerated on the server.  But older branches were pushed
# before that, so they still carry thousands of them, and comparing such a
# branch used to walk every single one of them -- which is what made a preview
# of topstorweb appear to hang.
#
# The lists below are the same ones systempush.sh uses.  Keep them in step.
# The count of skipped files is always printed, so this never hides anything
# silently.
#
#   PREGETDIFF_SKIP_EXCLUDED=0   compare them anyway
#   PREGETDIFF_SKIP_EXTRA=...     extra patterns, space separated
# ---------------------------------------------------------------------------
SPD_SKIP_EXCLUDED=${PREGETDIFF_SKIP_EXCLUDED:-1}
SPD_EXCLUDE_COMMON=${SPD_EXCLUDE_COMMON:-'quickstor-ui.tar.gz'}
SPD_EXCLUDE_TOPSTORWEB=${SPD_EXCLUDE_TOPSTORWEB:-'node_modules/ build_react/ build_react.bak/ .vite/ dist/ plugins/ dashboarddev3/ public/ assets/ ar/ js/ css/ img/ fonts/ netdata/ Data/ *.zip *.tar *.tar.gz *.map'}
SPD_EXCLUDE_EXTRA=${PREGETDIFF_SKIP_EXTRA:-'__py* __pycache__'}

# the patterns that apply to one project
excludes_for() {
	case $1 in
	topstorweb) echo "$SPD_EXCLUDE_COMMON $SPD_EXCLUDE_TOPSTORWEB $SPD_EXCLUDE_EXTRA" ;;
	*)          echo "$SPD_EXCLUDE_COMMON $SPD_EXCLUDE_EXTRA" ;;
	esac
}
MERGED_BRANCH=""

usage() {
	cat <<'EOF'
usage: systempregetdiff.sh [options] <from-branch> <into-branch>

  preview the merge and write instructions for it.  Nothing is changed
  until you run --apply.

options:
  --plan          just show the instruction file and exit
  --apply         refresh the base branch from origin, then perform the
                  merge and apply the instructions.  It asks nothing: firing
                  it does the whole thing.  The one exception is a merge
                  branch name that already exists - it stops and asks for a
                  different name rather than resetting it.
  --plans         list the instruction files of every branch pair
  --plan-file P   use P for this pair, instead of the automatic name
  --branch NAME   the merged branch to create (default <from>_<into>)
  --fetch         run "git fetch --prune" first.  Off by default.
                  (A branch that is neither local nor already tracked is looked
                  up on origin and fetched by itself, with or without --fetch.)
  --summary       summaries only, no file browser
  --pager X       builtin (default) | none | less
  --width N       viewer width (default 170, or $SYSTEMDIFF_WIDTH)
  -h,--help       this text

environment:
  NO_COLOR=1      plain text          FORCE_COLOR=1  always colour

  Each branch pair gets its own instruction file, so switching the branches
  switches the plan.  They live in:
      $PREGETDIFF_PLANDIR   (default /root/.systempregetdiff_plans)
  named <from>__<into>.plan.  --plan-file or PREGETDIFF_PLAN overrides that.
EOF
}

nbranches=0
while [ $# -gt 0 ]; do
	case "$1" in
	--fetch)   OPT_FETCH=1; shift ;;
	--summary) OPT_SUMMARY=1; shift ;;
	--plan)    OPT_PLAN=1; shift ;;
	--plans)   OPT_PLANS=1; shift ;;
	--apply)   OPT_APPLY=1; shift ;;
	--plan-file)
		shift; PLAN_FILE=$1; PLAN_EXPLICIT=1
		[ -n "$PLAN_FILE" ] || { echo "--plan-file needs a path" >&2; exit 1; }
		shift ;;
	--branch)
		shift; MERGED_BRANCH=$1
		[ -n "$MERGED_BRANCH" ] || { echo "--branch needs a name" >&2; exit 1; }
		shift ;;
	--pager)
		shift; PAGER_MODE=$1
		case "$PAGER_MODE" in
		builtin|none|less) ;;
		*) echo "--pager takes builtin, none or less" >&2; exit 1 ;;
		esac
		shift ;;
	--width)
		shift; WIDTH=$1
		[ -n "$WIDTH" ] || { echo "--width needs a number" >&2; exit 1; }
		shift ;;
	-h|--help) usage; exit 0 ;;
	--*) echo "unknown option '$1'" >&2; usage; exit 1 ;;
	*)
		nbranches=`expr $nbranches + 1`
		case $nbranches in
		1) P_FROM=$1 ;;
		2) P_INTO=$1 ;;
		*) echo "too many branch names - expected exactly two" >&2; usage; exit 1 ;;
		esac
		shift ;;
	esac
done

if [ "$OPT_PLANS" != 1 ] && [ "$nbranches" -lt 2 ]; then
	echo "two branch names are needed (you gave $nbranches)." >&2
	usage
	exit 1
fi

TMPD=`mktemp -d /tmp/systempregetdiff.XXXXXX` || exit 1
trap 'rm -rf "$TMPD"' EXIT INT TERM

say()  { printf '%s\n' "$*"; }
rule() { printf -- '---------------------------------------------------------------------------\n'; }

C_OFF=''; C_FROM_ADD=''; C_INTO_ADD=''; C_FROM_REP=''; C_INTO_REP=''
C_WARN=''; C_OK=''; C_BOLD=''; C_DIM=''
if [ -z "$NO_COLOR" ] && { [ -t 1 ] || [ "$FORCE_COLOR" = 1 ]; }; then
	C_OFF=`printf '\033[0m'`;       C_FROM_ADD=`printf '\033[1;32m'`
	C_INTO_ADD=`printf '\033[1;35m'`; C_FROM_REP=`printf '\033[34m'`
	C_INTO_REP=`printf '\033[31m'`;  C_WARN=`printf '\033[1;31m'`
	C_OK=`printf '\033[1;32m'`;      C_BOLD=`printf '\033[1;37m'`
	C_DIM=`printf '\033[2;37m'`
fi

# ===========================================================================
# which instruction file belongs to this branch pair
# ===========================================================================
plan_slug() {
	# a branch name can hold anything, including "/".  Keep it readable, but
	# never let it escape the directory or collide with another branch.
	_s=`printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'`
	_s=`printf '%s' "$_s" | cut -c1-60`
	if [ "$_s" != "$1" ] || [ "${#_s}" -ge 60 ]; then
		_h=`printf '%s' "$1" | cksum | cut -d' ' -f1`
		_s=`printf '%s' "$_s" | cut -c1-45`
		_s="${_s}-${_h}"
	fi
	printf '%s' "$_s"
}

plan_list() {
	# every plan on disk, one line per branch pair
	[ -d "$PLAN_DIR" ] || { say "  no plans yet in $PLAN_DIR"; return 0; }
	_pl=`ls -1 "$PLAN_DIR"/*.plan 2>/dev/null | sort`
	[ -n "$_pl" ] || { say "  no plans yet in $PLAN_DIR"; return 0; }
	printf '  %s\n' "$PLAN_DIR"
	for _f in $_pl; do
		# read the pair out of the file itself - splitting the FILE NAME on
		# "__" breaks as soon as a branch name contains an underscore
		_from=`awk -F'\t' '$1=="merge.from" { print $2; exit }' "$_f" 2>/dev/null`
		_into=`awk -F'\t' '$1=="merge.into" { print $2; exit }' "$_f" 2>/dev/null`
		[ -n "$_from" ] || _from="?"
		[ -n "$_into" ] || _into="?"
		_c=`awk -F'\t' '!/^merge/ && !/^#/ && NF' "$_f" 2>/dev/null | grep -c . `
		_b=`awk -F'\t' '$1=="merge.branch" { print $2; exit }' "$_f" 2>/dev/null`
		if [ "$_f" = "$PLAN_FILE" ]; then _m="${C_OK}<- this pair${C_OFF}"
		else _m=""; fi
		printf '    %-26s -> %-26s  %2s instr  new branch = %-24s %s\n' \
			"$_from" "$_into" "$_c" "${_b:--}" "$_m"
	done
}

if [ "$OPT_PLANS" = 1 ]; then
	rule
	say "  ${C_BOLD}instruction files, one per branch pair${C_OFF}"
	rule
	plan_list
	say ""
	rule
	exit 0
fi

# derive the file name from the pair being compared
if [ "$PLAN_EXPLICIT" = 0 ]; then
	[ -n "${PREGETDIFF_PLAN:-}" ] && PLAN_FILE=$PREGETDIFF_PLAN && PLAN_EXPLICIT=1
fi
if [ "$PLAN_EXPLICIT" = 0 ]; then
	_sf=`plan_slug "$P_FROM"`
	_si=`plan_slug "$P_INTO"`
	PLAN_FILE="$PLAN_DIR/${_sf}__${_si}.plan"
fi

plan_prepare() {
	# make sure the directory exists, and never lose a plan that was written
	# before plans were split per branch pair
	[ -d "$PLAN_DIR" ] || mkdir -p "$PLAN_DIR" 2>/dev/null
	[ -f "$PLAN_FILE" ] && return 0
	[ "$PLAN_EXPLICIT" = 1 ] && return 0
	[ -f "$LEGACY_PLAN" ] || return 0
	# Only adopt the old single plan for the pair it was actually written for.
	# Adopting it for every pair would hand a plan made for A->B to C->D, and
	# would carry the old merge.branch name - which names the wrong direction.
	_lf=`awk -F'\t' '$1=="merge.from" { print $2; exit }' "$LEGACY_PLAN" 2>/dev/null`
	_li=`awk -F'\t' '$1=="merge.into" { print $2; exit }' "$LEGACY_PLAN" 2>/dev/null`
	if [ -n "$_lf" ] || [ -n "$_li" ]; then
		if [ "$_lf" != "$P_FROM" ] || [ "$_li" != "$P_INTO" ]; then
			return 0
		fi
	fi
	cp "$LEGACY_PLAN" "$PLAN_FILE" 2>/dev/null || return 0
	say "  ${C_WARN}note${C_OFF} the old single plan was written for exactly this pair"
	say "       ($P_FROM -> $P_INTO), so it was copied to:"
	say "         $PLAN_FILE"
	say "       ${C_DIM}the old file $LEGACY_PLAN is left alone;"
	say "       delete it once you are happy${C_OFF}"
	say ""
	return 0
}

# ===========================================================================
# the viewer / editor
# ===========================================================================
cat > "$TMPD/editor.py" <<'EDITOR_PY_EOF'
import os, sys, select, subprocess, difflib, argparse

E = "\x1b["; R = E + "0m"
# The column already tells you which branch a line belongs to, so the colour
# only has to say "added" or "old version".  Within one column the two colours
# are far apart, and across columns the hue families differ:
#     left  column: green (added) / blue  (replaced)
#     right column: magenta (added) / red (replaced)
# No cyan and no yellow - cyan sat too close to green and yellow to orange.
F_ADD = E + "1;32m"     # bright green   - added by <from>
F_REP = E + "34m"       # blue           - <from>'s old version
I_ADD = E + "1;35m"     # bright magenta - added by <into>
I_REP = E + "31m"       # red            - <into>'s old version
EDIT_ADD = E + "1;32m"  # in the editor: you added this line
EDIT_DEL = E + "1;31m"  # you deleted this line
EDIT_CHG = E + "34m"    # you changed this line
BOLD = E + "1;37m"; DIM = E + "2;37m"; WARN = E + "1;31m"
OK = E + "1;32m"; MAG = E + "35m"; REV = E + "7m"
HELP_CMP = "q back | arrows scroll | space/b page | n/N next/prev change | e edit result | m mark file"
HELP_EDT = "d delete | c change | a add after | u undo | q/Esc done"


def git_show(ref, path):
    if not ref:
        return None
    p = subprocess.run(["git", "show", "%s:%s" % (ref, path)],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return None if p.returncode != 0 else p.stdout


def to_lines(raw):
    if raw is None:
        return None
    ls = raw.decode("utf-8", "replace").split("\n")
    if ls and ls[-1] == "":
        ls.pop()
    return ls


def is_binary(raw):
    return raw is not None and b"\x00" in raw[:8000]


def fit(t, n):
    if len(t) <= n:
        return t
    return t[:n - 1] + "\u2026" if n > 1 else t[:n]


def wrap(text, width):
    """Split a line so nothing is ever cut off.  A long line is shown in
    full over several rows instead of being truncated - that truncation is
    what used to make the right hand column look empty."""
    if text is None:
        return [""]
    out = []
    for part in text.split("\n"):
        if part == "":
            out.append("")
            continue
        while len(part) > width:
            out.append(part[:width])
            part = part[width:]
        out.append(part)
    return out or [""]


def esc(s):
    """Make a line safe to store in a tab separated file."""
    return (s.replace("\\", "\\\\").replace("\t", "\\t")
             .replace("\r", "\\r").replace("\n", "\\n"))


def unesc(s):
    """Undo esc().  A real tab in the text you are matching is the whole
    point of this - shell scripts are full of indented lines."""
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            nxt = s[i + 1]
            if nxt == "t":
                out.append("\t"); i += 2; continue
            if nxt == "r":
                out.append("\r"); i += 2; continue
            if nxt == "n":
                out.append("\n"); i += 2; continue
            if nxt == "\\":
                out.append("\\"); i += 2; continue
        out.append(c)
        i += 1
    return "".join(out)


def plan_add(path, repo, action, f, d1, d2=None):
    if not path:
        return
    try:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write("%s\t%s\t%s\t%s%s\n"
                     % (repo, action, esc(f), esc(d1),
                        ("\t" + esc(d2)) if d2 is not None else ""))
    except OSError as e:
        sys.stderr.write("plan: %s\n" % e)


def plan_drop(path, repo, action, f):
    if not path:
        return
    try:
        rows = open(path, encoding="utf-8").read().split("\n")
    except OSError:
        return
    key = "%s\t%s\t%s\t" % (repo, action, f)
    keep = [r for r in rows if not r.startswith(key)]
    open(path, "w", encoding="utf-8").write("\n".join(keep))


def get_size():
    for fd in (1, 0):
        try:
            s = os.get_terminal_size(fd)
            return max(s.lines, 12), max(s.columns, 40)
        except Exception:
            pass
    return 24, 80


def read_key(fd):
    try:
        r, _, _ = select.select([fd], [], [], 3600)
    except (OSError, ValueError):
        return "q"
    if not r:
        return None
    try:
        ch = os.read(fd, 1)
    except OSError:
        return "q"
    if not ch:
        return "q"
    if ch == b"\x1b":
        try:
            r2, _, _ = select.select([fd], [], [], 0.08)
        except OSError:
            return "ESC"
        if r2:
            try:
                seq = os.read(fd, 4)
            except OSError:
                return "ESC"
            two, three = seq[:2], seq[:3]
            if two in (b"[A", b"OA"):
                return "UP"
            if two in (b"[B", b"OB"):
                return "DOWN"
            if three == b"[5~":
                return "PGUP"
            if three == b"[6~":
                return "PGDN"
            if two == b"[H":
                return "HOME"
            if two == b"[F":
                return "END"
            return "ESC"
        return "ESC"
    if ch in (b"\x7f", b"\x08"):
        return "BACK"
    return ch.decode("utf-8", "replace")


def read_text(prompt, fd, oldterm):
    import termios, tty
    try:
        termios.tcsetattr(fd, termios.TCSADRAIN, oldterm)
        tty.setcbreak(fd)
    except Exception:
        pass
    out = sys.stdout
    out.write(prompt)
    out.flush()
    buf = ""
    while True:
        k = read_key(fd)
        if k is None:
            continue
        if k in ("\r", "\n"):
            out.write("\n")
            out.flush()
            break
        if k in ("\x03", "ESC"):
            out.write("\n")
            out.flush()
            buf = None
            break
        if k == "BACK":
            buf = buf[:-1]
            out.write("\b \b")
            out.flush()
            continue
        if len(k) == 1 and ord(k) >= 32:
            buf += k
            out.write(k)
            out.flush()
    try:
        tty.setcbreak(fd)
    except Exception:
        pass
    return buf


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from")
    ap.add_argument("--into")
    ap.add_argument("--tree")
    ap.add_argument("--path")
    ap.add_argument("--from-name")
    ap.add_argument("--into-name")
    ap.add_argument("--repo", default="")
    ap.add_argument("--repo-key", default="")
    ap.add_argument("--verdict", default="")
    ap.add_argument("--conflict", default="")
    ap.add_argument("--width", type=int, default=170)
    ap.add_argument("--plan", default="")
    a = ap.parse_args()

    FROMREF = getattr(a, "from")
    INTOREF = a.into
    FN, IN = a.from_name, a.into_name
    RK = a.repo_key or a.repo
    W = max(a.width, 90)
    # --- one geometry, used by the header, the rule and every data row so the
    # --- "|" always lands in the same column and nothing runs past W.
    NUMW = 5        # "%4d "  - the grey line number
    MARKW = 1       # the + or ~ marker
    GAPW = 1        # space between marker and text
    LUNIT = 2 + NUMW + MARKW + GAPW      # left indent + number + marker + space
    RUNIT = NUMW + MARKW + GAPW          # right side has no extra indent
    DIVW = 3        # " | "
    FRAME = LUNIT + DIVW + RUNIT         # 19 - everything except the text
    marker = NUMW + MARKW + GAPW        # blank gutter, kept for the header rule
    col = max((W - FRAME) // 2, 20)

    L = git_show(FROMREF, a.path)
    Rt = git_show(INTOREF, a.path)
    M = git_show(a.tree, a.path) if a.tree else None

    if is_binary(L) or is_binary(Rt) or is_binary(M):
        print(BOLD + "  binary file - no view" + R)
        return 0

    A = to_lines(L) or []
    B = to_lines(Rt) or []
    merged = to_lines(M)
    marks = any(l.lstrip().startswith(("<<<<<<<", "=======", ">>>>>>>"))
                for l in (merged or []))

    cmp_rows = []
    sm = difflib.SequenceMatcher(None, A, B, autojunk=False)
    li = ri = 0
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            for k in range(i2 - i1):
                li += 1
                ri += 1
                cmp_rows.append((li, A[i1 + k], ri, B[j1 + k], "eq"))
        elif tag == "delete":
            for k in range(i1, i2):
                li += 1
                cmp_rows.append((li, A[k], None, None, "f"))
        elif tag == "insert":
            for k in range(j1, j2):
                ri += 1
                cmp_rows.append((None, None, ri, B[k], "i"))
        else:
            dl, dr = A[i1:i2], B[j1:j2]
            for k in range(max(len(dl), len(dr))):
                lh, rh = k < len(dl), k < len(dr)
                cmp_rows.append((li + 1 if lh else None, dl[k] if lh else None,
                                 ri + 1 if rh else None, dr[k] if rh else None, "r"))
                if lh:
                    li += 1
                if rh:
                    ri += 1

    head = []
    head.append(BOLD + ("-" * W) + R)
    if a.repo:
        head.append(BOLD + a.repo + R + "  " + BOLD + a.path + R)
    head.append("")
    head.append("  " + DIM + "LEFT column " + R + F_ADD + FN + R
                + DIM + "   the branch being merged IN" + R)
    head.append("  " + DIM + "RIGHT column" + R + I_ADD + IN + R
                + DIM + "   the branch that receives it" + R)
    if a.verdict:
        head.append("  " + DIM + "outcome: " + R
                    + (WARN if a.conflict == "1" else OK) + a.verdict + R)
    head.append("")
    head.append(BOLD + "  HOW TO READ THIS" + R)
    head.append("   " + DIM + "|" + R + " the divider.  The two columns are the same file at two commits;"
                + DIM + " every row is one line." + R)
    head.append("   " + F_ADD + "+" + R + "  left only  = " + FN + " ADDED this line, " + IN + " has no such line")
    head.append("   " + F_REP + "~" + R + "  left row   = " + FN + "'s version, " + IN + " CHANGED it")
    head.append("   " + I_ADD + "+" + R + "  right only = " + IN + " ADDED this line, " + FN + " has no such line")
    head.append("   " + I_REP + "~" + R + "  right row  = " + IN + "'s version, " + FN + " CHANGED it")
    head.append("   " + DIM + "grey numbers = that column's own line number, blank where there is none" + R)
    head.append("")
    head.append("  " + " " * (NUMW + MARKW + GAPW) + F_ADD + FN + R
                + DIM + " | " + R + " " * (NUMW + MARKW + GAPW) + I_ADD + IN + R)
    head.append(DIM + "  " + "-" * (NUMW + MARKW + GAPW) + "-" * col + "-+-"
                + "-" * (NUMW + MARKW + GAPW) + "-" * col + R)

    def lnum(ln, first, color=DIM, mark=" "):
        """Left gutter: 2 space indent + number + marker + gap."""
        if first and ln:
            return "  " + color + "%4d " % ln + R + color + mark + R + " "
        return " " * LUNIT

    def rnum(rn, first, color=DIM, mark=" "):
        """Right gutter: number + marker + gap (no extra indent)."""
        if first and rn:
            return color + "%4d " % rn + R + color + mark + R + " "
        return " " * RUNIT

    def paint(text, color):
        """Pad the PLAIN text to the column width first, then colour it.
        Padding a coloured string would count the escape bytes as characters
        and push the right hand column out of place."""
        return color + text.ljust(col) + R

    def cmp_line(r):
        """Single line version, used when nothing needs wrapping."""
        ln, ltxt, rn, rtxt, kind = r
        if kind == "eq":
            return (lnum(ln, True) + ltxt.ljust(col) + DIM + " | " + R
                    + rnum(rn, True) + rtxt)
        if kind == "f":
            return (lnum(ln, True, F_ADD, "+") + F_ADD + ltxt + R
                    + DIM + " | " + R + " " * RUNIT + " " * col)
        if kind == "i":
            return (" " * LUNIT + " " * col + DIM + " | " + R
                    + rnum(rn, True, I_ADD, "+") + I_ADD + rtxt + R)
        left = paint(ltxt or "", F_REP) if ltxt is not None else " " * col
        right = (I_REP + rtxt + R) if rtxt is not None else ""
        return (lnum(ln, True, F_REP, "~") + left + DIM + " | " + R
                + rnum(rn, True, I_REP, "~") + right)

    def cmp_block(r):
        """One diff row expanded into as many screen lines as it needs, so
        that a long line is shown whole instead of being cut at the edge.
        Continuation lines keep the number/marker gutter blank, so the "|" and
        the far edge of both columns stay in exactly the same place."""
        ln, ltxt, rn, rtxt, kind = r
        if kind == "eq":
            lc, rc = wrap(ltxt, col), wrap(rtxt, col)
            out = []
            for i in range(max(len(lc), len(rc))):
                a = lc[i] if i < len(lc) else ""
                b = rc[i] if i < len(rc) else ""
                out.append(lnum(ln, i == 0) + a.ljust(col) + DIM + " | " + R
                           + rnum(rn, i == 0) + b)
            return out
        if kind == "f":
            out = []
            for i, t in enumerate(wrap(ltxt, col)):
                out.append(lnum(ln, i == 0, F_ADD, "+") + F_ADD + t + R
                           + DIM + " | " + R + " " * RUNIT + " " * col)
            return out
        if kind == "i":
            out = []
            for i, t in enumerate(wrap(rtxt, col)):
                out.append(" " * LUNIT + " " * col + DIM + " | " + R
                           + rnum(rn, i == 0, I_ADD, "+") + I_ADD + t + R)
            return out
        lc = wrap(ltxt, col) if ltxt is not None else [None]
        rc = wrap(rtxt, col) if rtxt is not None else [None]
        out = []
        for i in range(max(len(lc), len(rc))):
            a = lc[i] if i < len(lc) else None
            b = rc[i] if i < len(rc) else None
            # a side that has run out of fragments still owes the full column
            # width, otherwise the "|" slides left on that row
            left = paint(a, F_REP) if a is not None else " " * col
            right = (I_REP + b + R) if b is not None else ""
            out.append(lnum(ln, i == 0, F_REP, "~") + left + DIM + " | " + R
                       + rnum(rn, i == 0, I_REP, "~") + right)
        return out

    if not sys.stdout.isatty():
        for l in head:
            print(l)
        for r in cmp_rows:
            for l in cmp_block(r):
                print(l)
        if merged is not None:
            print("")
            print(BOLD + ("=" * W) + R)
            print((WARN if marks else OK) + "  WHAT A REAL MERGE WOULD PRODUCE" + R)
            print(BOLD + ("=" * W) + R)
            for i, line in enumerate(merged, 1):
                t = line.lstrip()
                if t.startswith(("<<<<<<<", "=======", ">>>>>>>")):
                    print("  " + MAG + line + R)
                else:
                    print("  " + DIM + "%4d " % i + R + "  " + line)
        return 0

    try:
        ttyf = open("/dev/tty", "r+b", buffering=0)
    except OSError:
        for l in head:
            print(l)
        return 0

    import termios, tty
    fd = ttyf.fileno()
    oldterm = termios.tcgetattr(fd)
    try:
        tty.setcbreak(fd)
    except Exception:
        pass
    ROWS, COLS = get_size()
    # never paint a line wider than the terminal, otherwise the right hand
    # column is cut off at the edge and looks empty
    if W > COLS:
        W = COLS
    # shrink the text column until a full row - both gutters, the divider and
    # BOTH texts - fits inside the terminal
    col = max((W - FRAME) // 2, 8)
    while FRAME + 2 * col > W and col > 8:
        col -= 1
    body = max(ROWS - 2, 6)
    out = sys.stdout

    # Groups of consecutive CHANGED rows.  "n"/"N" step between these, and
    # consecutive replaced rows count as ONE change rather than several, so a
    # hunk that rewrote five lines is visited once, not five times.
    changes = []
    change_of = {}
    _i = 0
    while _i < len(cmp_rows):
        if cmp_rows[_i][4] == "eq":
            _i += 1
            continue
        _j = _i
        while _j < len(cmp_rows) and cmp_rows[_j][4] != "eq":
            _j += 1
        _ci = len(changes)
        changes.append((_i, _j))
        for _r in range(_i, _j):
            change_of[_r] = _ci
        _i = _j
    cur_change = -1

    base = list(merged) if merged is not None else (list(B) or list(A))
    deleted = set()
    replaced = {}
    added = {}
    undo = []
    top = 0
    sub = 0            # screen lines already scrolled past inside row "top"
    cur = 0
    mode = "cmp"
    next_top = [0]
    prev_top = [0]

    def edt_view():
        v = []
        for i in range(len(base)):
            if i in deleted:
                v.append((i, None, "del"))
                continue
            v.append((i, replaced.get(i, base[i]), "rep" if i in replaced else "same"))
            for extra in added.get(i, []):
                v.append((None, extra, "add"))
        return v

    def draw():
        out.write(E + "H" + E + "2J")
        if mode == "cmp":
            avail = ROWS - 3
            for l in head[:avail]:
                out.write(l[:COLS - 1] + "\n")
            # expand whole diff rows, never cutting one in half
            shown = []
            ri = top
            if ri < len(cmp_rows):
                # top may sit part way into a row that wrapped over several
                # screen lines - "sub" is how far down into it we are
                first = cmp_block(cmp_rows[ri])[sub:]
                for l in first:
                    if len(shown) >= avail:
                        break
                    shown.append((ri, l))
                ri += 1
            while ri < len(cmp_rows) and len(shown) < avail:
                for l in cmp_block(cmp_rows[ri]):
                    if len(shown) >= avail:
                        break
                    shown.append((ri, l))
                ri += 1
            for ridx, l in shown:
                is_cur = cur_change >= 0 and change_of.get(ridx, -1) == cur_change
                if is_cur:
                    # reverse video, so the change you jumped to is obvious
                    l = REV + l
                if len(l) > COLS - 1:
                    l = l[:COLS - 1] + R
                elif is_cur:
                    l = l + R
                out.write(l + "\n")
            next_top[0] = ri
            prev_top[0] = top
            if cur_change >= 0:
                _cs, _ce = changes[cur_change]
                # the change indicator goes FIRST: the bar is cut to the
                # terminal width, and this is the part that must survive
                bar = " ** CHANGE %d of %d ** rows %d-%d | rows %d-%d of %d | %s " % (
                    cur_change + 1, len(changes), _cs + 1, _ce,
                    top + 1, ri, len(cmp_rows), HELP_CMP)
            else:
                bar = " %s | rows %d-%d of %d " % (
                    HELP_CMP, top + 1, ri, len(cmp_rows))
        else:
            v = edt_view()
            hdr = [BOLD + ("=" * W) + R]
            if marks:
                hdr.append(WARN + "  THE RESULTANT FILE  -  UNRESOLVED" + R)
                hdr.append(WARN + "  This is the file the merge WOULD write, but because the two"
                           " branches collide" + R)
                hdr.append(WARN + "  the merge would stop and ask you to choose. Edit it here"
                           " or mark the file with m." + R)
            else:
                hdr.append(OK + "  THE RESULTANT FILE  -  what the merge would actually write" + R)
                hdr.append(DIM + "  the single finished file, both branches combined."
                           "  press e to edit it." + R)
            hdr.append("  " + DIM + "your edits:" + R
                       + "   " + EDIT_ADD + "+ you added this line" + R
                       + "   " + EDIT_DEL + "- you deleted this line" + R
                       + "   " + EDIT_CHG + "~ you changed this line" + R)
            hdr.append(BOLD + ("=" * W) + R)
            avail = ROWS - 3
            for l in hdr:
                out.write(l[:COLS - 1] + "\n")
            for i, txt, kind in v[top:top + avail]:
                num = "%4d " % (i + 1) if i is not None else "     "
                if kind == "del":
                    out.write("  " + DIM + num + R + EDIT_DEL + "- "
                              + fit(base[i], COLS - 10) + R + "\n")
                elif kind == "add":
                    out.write("  " + DIM + num + R + EDIT_ADD + "+ "
                              + fit(txt, COLS - 10) + R + "\n")
                else:
                    t = txt.lstrip()
                    if t.startswith(("<<<<<<<", "=======", ">>>>>>>")):
                        out.write("  " + DIM + num + R + "  "
                                  + MAG + fit(txt, COLS - 10) + R + "\n")
                    elif i == cur:
                        out.write(REV + "  " + DIM + num + R + "  "
                                  + fit(txt, COLS - 10) + R + "\n")
                    elif kind == "rep":
                        out.write("  " + DIM + num + R + EDIT_CHG + "~ "
                                  + fit(txt, COLS - 10) + R + "\n")
                    else:
                        out.write("  " + DIM + num + R + "  " + fit(txt, COLS - 10) + "\n")
            bar = " %s | line %d of %d | %d edit(s) " % (
                HELP_EDT, cur + 1, len(base), len(undo))
        if len(bar) > COLS - 1:
            bar = bar[:COLS - 1]
        out.write(REV + bar + R)
        out.flush()

    def ensure_visible(idx):
        nonlocal top
        av = max(ROWS - 3, 6)
        if idx < top:
            top = idx
        elif idx >= top + av:
            top = idx - av + 1
        if top < 0:
            top = 0

    try:
        while True:
            draw()
            k = read_key(fd)
            if k is None:
                continue
            if mode == "edt":
                if k in ("j", "DOWN"):
                    cur = min(cur + 1, len(base) - 1)
                    ensure_visible(cur)
                elif k in ("k", "UP"):
                    cur = max(cur - 1, 0)
                    ensure_visible(cur)
                elif k in ("q", "Q", "ESC", "\x03", "\x04"):
                    mode = "cmp"
                elif k == "d" and cur not in deleted:
                    old = replaced.get(cur, base[cur])
                    plan_add(a.plan, RK, "del-line", a.path, old)
                    undo.append(("del", cur))
                    deleted.add(cur)
                    cur = min(cur + 1, len(base) - 1)
                elif k == "c":
                    old = replaced.get(cur, base[cur]) if cur < len(base) else ""
                    new = read_text("  new text for line %d: " % (cur + 1), fd, oldterm)
                    if new and new != old:
                        plan_add(a.plan, RK, "rep-line", a.path, old, new)
                        undo.append(("rep", cur))
                        replaced[cur] = new
                elif k == "a":
                    anchor = replaced.get(cur, base[cur]) if cur < len(base) else ""
                    new = read_text("  insert after this line: ", fd, oldterm)
                    if new:
                        plan_add(a.plan, RK, "add-line", a.path, anchor, new)
                        undo.append(("add", cur))
                        added.setdefault(cur, []).append(new)
                elif k == "u" and undo:
                    what, i = undo.pop()
                    if what == "del":
                        deleted.discard(i)
                    elif what == "rep":
                        replaced.pop(i, None)
                    elif what == "add":
                        if added.get(i):
                            added[i].pop()
                            if not added[i]:
                                added.pop(i, None)
                continue

            if k in ("q", "Q", "\x03", "\x04"):
                break
            if k == "e":
                mode = "edt"
                # start on the first line that is on screen right now, rather
                # than jumping back to the top of the document
                anchor = None
                if 0 <= top < len(cmp_rows):
                    first = cmp_rows[top]
                    anchor = first[2] if first[2] else first[0]
                if anchor:
                    cur = max(0, min(anchor - 1, len(base) - 1))
                elif cmp_rows and base:
                    frac = top / float(len(cmp_rows))
                    cur = max(0, min(int(frac * len(base)), len(base) - 1))
                else:
                    cur = 0
                top = cur
            elif k == "m":
                plan_drop(a.plan, RK, "keep", a.path)
                plan_drop(a.plan, RK, "delete", a.path)
                out.write(E + "H" + E + "2J")
                out.write(BOLD + "  mark this file" + R + "\n\n")
                out.write("  " + DIM + "(with no mark at all the merge result is used as it is)" + R + "\n\n")
                out.write("  " + F_ADD + "1" + R + "  use the " + FN + " version")
                out.write(("\n" if A is not None else
                           "  " + DIM + "- but " + FN + " has no such file, so it will not be added") + R + "\n")
                out.write("  " + I_ADD + "2" + R + "  use the " + IN + " version")
                out.write(("\n" if B is not None else
                           "  " + DIM + "- but " + IN + " has no such file, so it will NOT be added") + R + "\n")
                out.write("  " + WARN + "3" + R + "  delete this file after merging\n")
                out.write("  " + DIM + "0" + R + "  clear the mark for this file\n\n")
                out.write(REV + " choose 1-3 or 0: " + R)
                out.flush()
                pick = read_key(fd)
                if pick == "1":
                    plan_add(a.plan, RK, "keep", a.path, "from")
                elif pick == "2":
                    plan_add(a.plan, RK, "keep", a.path, "into")
                elif pick == "3":
                    plan_add(a.plan, RK, "delete", a.path, "-")
            # top counts DIFF ROWS, while the screen holds a fixed number of
            # rows whose height varies with wrapping.  Paging therefore has to
            # be done in row units - never by adding the screen line count.
            elif k in (" ", "PGDN", "\n"):
                top = next_top[0] if next_top[0] > top else min(top + 1, len(cmp_rows) - 1)
                sub = 0
            elif k in ("b", "PGUP"):
                top = prev_top[0] if prev_top[0] < top else max(top - 1, 0)
                sub = 0
            elif k in ("j", "DOWN"):
                # down by ONE SCREEN LINE, so a long line can be read a piece
                # at a time instead of jumping a whole row at once
                if sub + 1 < len(cmp_block(cmp_rows[top])):
                    sub += 1
                elif top < len(cmp_rows) - 1:
                    top += 1
                    sub = 0
            elif k in ("k", "UP"):
                if sub > 0:
                    sub -= 1
                elif top > 0:
                    top -= 1
                    sub = max(len(cmp_block(cmp_rows[top])) - 1, 0)
            elif k in ("n", "N") and changes:
                # step relative to the CURRENT change, not to top - otherwise
                # a change that is already on screen would be picked again and
                # again and n would appear to do nothing
                _want = -1
                if k == "n":
                    for _c2 in range(cur_change + 1, len(changes)):
                        _want = _c2
                        break
                    if _want < 0 and cur_change < 0:
                        for _c2, (_s2, _e2) in enumerate(changes):
                            if _s2 > top:
                                _want = _c2
                                break
                else:
                    for _c2 in range(min(cur_change, len(changes)) - 1, -1, -1):
                        _want = _c2
                        break
                    if _want < 0 and cur_change < 0:
                        for _c2 in range(len(changes) - 1, -1, -1):
                            if changes[_c2][0] < top:
                                _want = _c2
                                break
                if _want >= 0:
                    cur_change = _want
                    _cs, _ce = changes[cur_change]
                    # if it is already on screen, stay put and just highlight;
                    # otherwise bring it to the first line of the page
                    if not (top <= _cs < next_top[0]):
                        top = _cs
                        sub = 0
            elif k in ("g", "HOME"):
                top = 0
                sub = 0
                if k == "g" and top in change_of:
                    cur_change = change_of[top]
            elif k in ("G", "END"):
                top = len(cmp_rows) - 1
                sub = 0
            top = max(0, min(top, len(cmp_rows) - 1))
            sub = max(0, min(sub, max(len(cmp_block(cmp_rows[top])) - 1, 0)))
    finally:
        try:
            termios.tcsetattr(fd, termios.TCSADRAIN, oldterm)
        except Exception:
            pass
        out.write(R + "\n")
        out.flush()
        try:
            ttyf.close()
        except OSError:
            pass
    return 0


sys.exit(main())
EDITOR_PY_EOF

cat > "$TMPD/apply.py" <<'APPLY_PY_EOF'
import os, sys, argparse


def read_lines(path):
    with open(path, "rb") as fh:
        data = fh.read()
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return None, None
    nl = "\r\n" if "\r\n" in text else "\n"
    lines = text.split(nl)
    if lines and lines[-1] == "":
        lines.pop()
    return lines, nl


def write_lines(path, lines, nl):
    with open(path, "wb") as fh:
        fh.write((nl.join(lines) + nl).encode("utf-8"))


def unesc(s):
    """Turn the \\t \\r \\n \\\\ escapes back into real characters, so a line
    that starts with a tab can be matched and written back intact."""
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            nxt = s[i + 1]
            if nxt == "t":
                out.append("\t"); i += 2; continue
            if nxt == "r":
                out.append("\r"); i += 2; continue
            if nxt == "n":
                out.append("\n"); i += 2; continue
            if nxt == "\\":
                out.append("\\"); i += 2; continue
        out.append(c)
        i += 1
    return "".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True)
    ap.add_argument("--del-line")
    ap.add_argument("--rep-line", nargs=2)
    ap.add_argument("--add-line", nargs=2)
    a = ap.parse_args()
    thefile = unesc(a.file)
    rules = []
    if a.del_line is not None:
        rules.append(("del", unesc(a.del_line)))
    if a.rep_line:
        rules.append(("rep", unesc(a.rep_line[0]), unesc(a.rep_line[1])))
    if a.add_line:
        rules.append(("add", unesc(a.add_line[0]), unesc(a.add_line[1])))
    if not rules:
        return 0
    if not os.path.isfile(thefile):
        print("MISSING")
        return 0
    lines, nl = read_lines(thefile)
    if lines is None:
        print("BINARY")
        return 0
    applied = []
    for r in rules:
        if r[0] == "del":
            old = r[1]
            hit = [i for i, l in enumerate(lines) if l == old]
            mode = "exact"
            if not hit and old:
                hit = [i for i, l in enumerate(lines) if old in l]
                mode = "substring"
            for i in reversed(hit):
                del lines[i]
            applied.append("del(%s,%d)" % (mode, len(hit)))
        elif r[0] == "rep":
            old, new = r[1], r[2]
            n = 0
            for i, l in enumerate(lines):
                if l == old:
                    lines[i] = new
                    n += 1
            if n == 0 and old:
                for i, l in enumerate(lines):
                    if old in l:
                        lines[i] = l.replace(old, new, 1)
                        n += 1
            applied.append("rep(%d)" % n)
        elif r[0] == "add":
            after, new = r[1], r[2]
            idxs = [i for i, l in enumerate(lines) if l == after]
            if not idxs and after:
                idxs = [i for i, l in enumerate(lines) if after in l]
            for i in reversed(idxs):
                lines.insert(i + 1, new)
            applied.append("add(%d)" % len(idxs))
    write_lines(thefile, lines, nl)
    print(" ".join(applied))
    return 0


sys.exit(main())
APPLY_PY_EOF

# ===========================================================================
# instruction file helpers
# ===========================================================================
plan_init() {
	[ -f "$PLAN_FILE" ] && return 0
	cat > "$PLAN_FILE" <<EOF
# ------------------------------------------------------------------
# systempregetdiff instruction file - tab separated, yours to edit
#
#   <repo> <action> <file> <arg1> <arg2>
#
# actions on a whole file
#   keep       arg1 = from | into    take the file from that side of the
#                                    merge instead of the merged result
#   delete     arg1 = -              remove the file after merging
#
# actions on single lines
#   del-line   arg1 = the exact line to remove
#   rep-line   arg1 = the old line   arg2 = what to put there instead
#   add-line   arg1 = the anchor line arg2 = the line to add after it
#
# arg2 is only used by rep-line and add-line.
# lines are matched on CONTENT, so they still apply after the merge
# has moved every line.
#
# IMPORTANT: the fields are separated by TABs, so a real tab inside a line
# must be written as  \t   (backslash t).  Same for \r and \n, and a real
# backslash is written as \\.  The script writes these escapes for you when
# you make an edit in the viewer; you only need them when you type by hand.
# An instruction that contains a real tab is refused rather than guessed at.
# ------------------------------------------------------------------
merge.from	$P_FROM
merge.into	$P_INTO
merge.branch	${MERGED_BRANCH:-${P_FROM}_${P_INTO}}
EOF
}

plan_sync() {
	# keep the three merge.* lines in step with the command line, without
	# ever dropping or duplicating one.  An explicit --branch always wins;
	# otherwise whatever branch name the file already carries is kept.
	[ -f "$PLAN_FILE" ] || return 0
	pt_cur=`awk -F'\t' '$1=="merge.branch" { print $2; exit }' "$PLAN_FILE" 2>/dev/null`
	if [ -n "$MERGED_BRANCH" ]; then
		pt_branch=$MERGED_BRANCH
	elif [ -n "$pt_cur" ]; then
		pt_branch=$pt_cur
	else
		pt_branch="${P_FROM}_${P_INTO}"
	fi
	pt_tmp="$PLAN_FILE.tmp.$$"
	{
		printf 'merge.from\t%s\n'   "$P_FROM"
		printf 'merge.into\t%s\n'   "$P_INTO"
		printf 'merge.branch\t%s\n' "$pt_branch"
		# Remember the commit each base branch is AT right now.  The apply
		# step refreshes the base from origin before merging, so this is how
		# we can tell you the plan was worked out against something older.
		# It is rewritten on every preview, so re-running the preview is what
		# marks "I have seen the current base".
		for pt_repo in $REPOS; do
			[ -d "$ROOT/$pt_repo" ] || continue
			(
				cd "$ROOT/$pt_repo" 2>/dev/null || exit 0
				git rev-parse --git-dir >/dev/null 2>&1 || exit 0
				pt_ref=`resolve_ref "$P_INTO"`
				[ -n "$pt_ref" ] || exit 0
				pt_sha=`git rev-parse "$pt_ref" 2>/dev/null`
				[ -n "$pt_sha" ] || exit 0
				printf 'merge.base.%s\t%s\n' "$pt_repo" "$pt_sha"
			)
		done
		grep -v '^merge' "$PLAN_FILE" 2>/dev/null
	} > "$pt_tmp"
	mv "$pt_tmp" "$PLAN_FILE"
}

plan_branch() {
	if [ -f "$PLAN_FILE" ]; then
		awk -F'\t' '$1=="merge.branch" { print $2; exit }' "$PLAN_FILE"
	fi
}

plan_count() {
	# count real instructions only - not the merge.* header lines and not the
	# comment block
	if [ -f "$PLAN_FILE" ]; then
		awk -F'\t' '!/^merge/ && !/^#/ && NF { n++ } END { print n+0 }' "$PLAN_FILE"
	else
		echo 0
	fi
}

plan_show() {
	if [ ! -f "$PLAN_FILE" ]; then
		say "  no instruction file yet at $PLAN_FILE"
		return 0
	fi
	say "  ${C_BOLD}instruction file${C_OFF}  $PLAN_FILE"
	say ""
	say "  ${C_BOLD}merge${C_OFF}"
	awk -F'\t' '$1=="merge.from"   { printf "    from branch     : %s\n", $2 }' "$PLAN_FILE"
	awk -F'\t' '$1=="merge.into"   { printf "    into branch     : %s\n", $2 }' "$PLAN_FILE"
	ps_b=`plan_branch`
	say "    new branch name : ${C_OK}${ps_b}${C_OFF}"
	for pv_repo in $REPOS; do
		pv_n=`awk -F'\t' -v r="$pv_repo" '$1==r' "$PLAN_FILE" 2>/dev/null | wc -l`
		[ "$pv_n" -gt 0 ] || continue
		say ""
		say "  ${C_BOLD}$pv_repo${C_OFF}"
		awk -F'\t' -v r="$pv_repo" -v warn="$C_WARN" \
		    -v f="$C_FROM_ADD" -v i="$C_INTO_ADD" -v rd="$C_FROM_REP" \
		    -v y="$C_INTO_REP" -v off="$C_OFF" '
			$1==r {
				c = $2
				if ($2=="keep")        c = f "keep" off
				else if ($2=="delete") c = warn "delete" off
				else if ($2=="del-line")  c = rd "del-line" off
				else if ($2=="rep-line")  c = y "rep-line" off
				else if ($2=="add-line")  c = i "add-line" off
				printf "    %-14s %-34s %s\n", c, $3, $4
			}' "$PLAN_FILE"
	done
	say ""
}

plan_confirm() {
	printf '\n  %s%s%s  [y/N] ' "$C_BOLD" "$1" "$C_OFF"
	read -r pa
	case "$pa" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# Where would a branch of this name already live?  Echoes a human list.
branch_clash() {
	bc_out=""
	bc_name=$1
	for bc_repo in $REPOS; do
		cd "$ROOT/$bc_repo" 2>/dev/null || continue
		git rev-parse --git-dir >/dev/null 2>&1 || continue
		if ref_exists "refs/heads/$bc_name"; then
			bc_url=`git remote get-url origin 2>/dev/null`
			bc_out="$bc_out
        $bc_repo  already exists locally, and is on origin $bc_url"
		elif ref_exists "refs/remotes/origin/$bc_name"; then
			bc_url=`git remote get-url origin 2>/dev/null`
			bc_out="$bc_out
        $bc_repo  already exists on origin $bc_url"
		fi
	done
	[ -n "$bc_out" ] && printf '%s\n' "$bc_out"
	return 0
}

# plan_mark_of used to look an instruction up here, one awk per file.  It is
# gone: the classification awk in preview_repo() now joins the whole
# instruction file in a single pass and hands back the action and the side
# as their own fields, so nothing has to be looked up per file any more.

# ===========================================================================
# helpers
# ===========================================================================
ref_exists() { git rev-parse --verify --quiet "$1^{commit}" >/dev/null 2>&1; }

# fetch_from_origin <branch>: the branch is not here, so ask origin (abdopuppet).
# Only that one branch is fetched, into refs/remotes/origin/<branch>: no local
# branch, HEAD, index or file is touched, so the "nothing is checked out while
# you preview" promise holds.  Returns 0 when origin has it and it is now here.
fetch_from_origin() {
	ff_to=""; command -v timeout >/dev/null 2>&1 && ff_to="timeout 30"
	[ -n "`$ff_to git ls-remote --heads origin "refs/heads/$1" 2>/dev/null`" ] || return 1
	$ff_to git fetch --quiet origin "+refs/heads/$1:refs/remotes/origin/$1" >/dev/null 2>&1 || return 1
	ref_exists "refs/remotes/origin/$1"
}

resolve_ref() {
	if ref_exists "refs/heads/$1";            then printf '%s\n' "$1"
	elif ref_exists "refs/remotes/origin/$1"; then printf '%s\n' "origin/$1"
	elif fetch_from_origin "$1"; then
		printf '  %s: branch %s not local, fetched from origin\n' "${PWD##*/}" "$1" >&2
		printf '%s\n' "origin/$1"
	fi
	return 0
}

show_file() {
	# show_file <fromref> <intoref> <tree> <path> <verdict> <conflict> <repokey>
	# The editor draws straight to the terminal - writing it to a file first
	# would hide the tty from it and silently disable the interactive keys.
	if [ "$PAGER_MODE" = less ] && command -v less >/dev/null 2>&1; then
		python3 "$TMPD/editor.py" \
			--from "$1" --into "$2" --tree "$3" --path "$4" \
			--from-name "$P_FROM" --into-name "$P_INTO" \
			--repo "$7" --repo-key "$7" \
			--verdict "$5" --conflict "$6" --plan "$PLAN_FILE" \
			--width "$WIDTH" | less -R -S -X
	else
		python3 "$TMPD/editor.py" \
			--from "$1" --into "$2" --tree "$3" --path "$4" \
			--from-name "$P_FROM" --into-name "$P_INTO" \
			--repo "$7" --repo-key "$7" \
			--verdict "$5" --conflict "$6" --plan "$PLAN_FILE" \
			--width "$WIDTH"
	fi
	return 0
}

# ===========================================================================
# preview one directory
# ===========================================================================
preview_repo() {
	pr_repo=$1
	pr_path="$ROOT/$pr_repo"
	cd "$pr_path" 2>/dev/null || return 1
	git rev-parse --git-dir >/dev/null 2>&1 || return 1
	[ "$OPT_FETCH" = 1 ] && git fetch --prune --quiet origin >/dev/null 2>&1

	pr_fromref=`resolve_ref "$P_FROM"`
	pr_intoref=`resolve_ref "$P_INTO"`
	if [ -z "$pr_fromref" ] || [ -z "$pr_intoref" ]; then
		printf '\n'; rule; printf ' %s\n' "$pr_path"; rule
		[ -z "$pr_fromref" ] && say "  branch '$P_FROM' does not exist here or on origin"
		[ -z "$pr_intoref" ] && say "  branch '$P_INTO' does not exist here or on origin"
		return 0
	fi

	pr_out="$TMPD/$pr_repo.mt"
	git merge-tree --write-tree --name-only "$pr_fromref" "$pr_intoref" >"$pr_out" 2>/dev/null
	pr_rc=$?
	pr_tree=`head -1 "$pr_out"`
	[ -n "$pr_tree" ] || { pr_tree=""; pr_rc=1; }
	tail -n +2 "$pr_out" | sed 's/\t.*//' | grep -v '^$' \
		| grep -v -e '^Auto-merging' -e '^CONFLICT' -e '^warning:' -e '^note:' -e '^[0-9]' \
		> "$TMPD/$pr_repo.conflicts"
	[ -s "$TMPD/$pr_repo.conflicts" ] || : > "$TMPD/$pr_repo.conflicts"

	pr_rec="$TMPD/$pr_repo.rec"
	# Classify every changed file and fold in the instruction file in ONE
	# pass.  This used to run, PER FILE, two git cat-file probes, a grep, an
	# awk and two cuts -- roughly seven process spawns for every path.  With
	# a handful of changed files that is invisible; with the ~8000 paths that
	# excluding the topstorweb build directories produces it is ~55000
	# spawns, which is indistinguishable from a hang.  Below this point there
	# is a single git call and a single awk, and the shell loops that follow
	# use builtins only.
	#
	# --name-status already says which side has the file, so no probing:
	#   D = present in FROM, gone in INTO  -> only-from, the merge adds it
	#   A = present in INTO, gone in FROM  -> only-into, kept as it is
	#   anything else                      -> present on both sides
	git diff --name-status --no-renames "$pr_fromref" "$pr_intoref" 2>/dev/null \
		> "$TMPD/$pr_repo.ns"
	pr_skiprep="$TMPD/$pr_repo.skipped"
	: > "$pr_skiprep"
	awk -F'\t' -v repo="$pr_repo" -v plan="$PLAN_FILE" \
	    -v conf="$TMPD/$pr_repo.conflicts" \
	    -v skip="$SPD_SKIP_EXCLUDED" -v pats="`excludes_for "$pr_repo"`" \
	    -v report="$pr_skiprep" '
		# turn one ignore pattern into a regexp that matches the same paths
		# git would ignore.  A trailing slash means a directory, a pattern
		# with a slash inside is anchored, a bare name matches at any depth.
		function glob2re(p,   r, i, c, last) {
			r = ""
			for (i = 1; i <= length(p); i++) {
				c = substr(p, i, 1)
				if      (c == "*") r = r "[^/]*"
				else if (c == "?") r = r "[^/]"
				else if (c == ".") r = r "\\."
				else              r = r c
			}
			last = substr(p, length(p), 1)
			if (last == "/") {
				sub(/\/$/, "", r)
				return "(^|.*/)" r "/.*"
			}
			if (p ~ /\//) return "^" r "$"
			return "(^|.*/)" r "$"
		}
		function isexcluded(p,   k) {
			for (k = 1; k <= nre; k++) if (p ~ re[k]) return 1
			return 0
		}
		BEGIN {
			if (skip == "1") {
				n = split(pats, plist, " ")
				for (i = 1; i <= n; i++) {
					if (plist[i] == "") continue
					nre++
					re[nre] = glob2re(plist[i])
				}
			}
			if (plan != "") {
				while ((getline pl < plan) > 0) {
					n = split(pl, a, "\t")
					if (n >= 4) pm[a[1] SUBSEP a[3]] = a[2] "\t" a[4]
				}
				close(plan)
			}
			while ((getline cl < conf) > 0) if (cl != "") conflict[cl] = 1
			close(conf)
		}
		{
			st = $1; path = $2
			if (st == "") next
			if (nre > 0 && isexcluded(path)) { skipped++; next }
			if (st ~ /^D/)      { kind = "only-from"; verdict = "added" }
			else if (st ~ /^A/) { kind = "only-into"; verdict = "kept" }
			else {
				kind = "both"
				if (path in conflict) verdict = "conflict"; else verdict = "clean"
			}
			act = ""; side = ""
			if ((repo SUBSEP path) in pm) {
				split(pm[repo SUBSEP path], b, "\t")
				act = b[1]; side = b[2]
			}
			printf "%s|%s|%s|%s|%s\n", kind, path, verdict, act, side
		}
		END {
			if (skipped > 0) print skipped > report
		}
	' "$TMPD/$pr_repo.ns" > "$pr_rec"

	while :; do
		printf '\n'; rule; printf ' %s\n' "$pr_path"; rule
		say "  ${C_BOLD}previewing${C_OFF} : ${C_FROM_ADD}$P_FROM${C_OFF} ${C_DIM}(from)${C_OFF}  ->  ${C_INTO_ADD}$P_INTO${C_OFF} ${C_DIM}(into)${C_OFF}"
		say "  checked out: `git rev-parse --abbrev-ref HEAD`  ${C_DIM}(nothing below uses it)${C_OFF}"
		say ""
		if [ "$pr_rc" = 0 ]; then
			say "  RESULT: ${C_OK}the two branches MERGE CLEANLY - no conflicts.${C_OFF}"
		else
			say "  RESULT: ${C_WARN}THE MERGE WOULD STOP - some files collide.${C_OFF}"
			say "          ${C_WARN}for those, NEITHER update wins; you must choose.${C_OFF}"
		fi
		say ""
		if [ ! -s "$pr_rec" ]; then
			say "  ${C_DIM}These two branches are identical.${C_OFF}"
		else
			if [ -s "$pr_skiprep" ]; then
				say "  ${C_DIM}skipped `cat "$pr_skiprep"` file(s) that systempush no longer commits --${C_OFF}"
				say "  ${C_DIM}build caches, archives, source maps and vendored libraries that arrive${C_OFF}"
				say "  ${C_DIM}with the deployment image.  PREGETDIFF_SKIP_EXCLUDED=0 to compare them.${C_OFF}"
				say ""
			fi
			sort -t'|' -k1,1 -k3,3 "$pr_rec" > "$pr_rec.s"
			pr_n=0
			pr_last=""
			while IFS='|' read -r pr_kind pr_pth pr_verdict pr_mact pr_mside; do
				[ -n "$pr_kind" ] || continue
				pr_n=$((pr_n + 1))
				if [ "$pr_kind" != "$pr_last" ]; then
					pr_last=$pr_kind
					case "$pr_kind" in
					only-from) say "  ${C_FROM_ADD}--- only in $P_FROM : the merge would ADD these ---${C_OFF}" ;;
					only-into) say "  ${C_INTO_ADD}--- only in $P_INTO : kept as they are ---${C_OFF}" ;;
					both)      say "  ${C_BOLD}--- changed on both sides ---${C_OFF}" ;;
					esac
				fi
				printf '   %3d  %s\n' "$pr_n" "$pr_pth"
				# Say what will ACTUALLY happen to this file, not just what the
				# merge alone would do.  A "delete" instruction beats the
				# merge, and before this the list still said "would be
				# created" for files the plan was about to remove.
				# pr_mact and pr_mside arrive already joined in from the awk
				# above; looking them up per file with an awk of its own is
				# what used to make this unusable on a large diff.
				case "$pr_mact" in
				keep)
					case "$pr_mside" in
					into) say "        ${C_INTO_ADD}<- your plan: use the $P_INTO version${C_OFF}"
					       [ "$pr_kind" = only-from ] && \
					       say "           ${C_INTO_ADD}$P_INTO has no such file, so it will NOT be added${C_OFF}" ;;
					*)    say "        ${C_FROM_ADD}<- your plan: use the $P_FROM version${C_OFF}" ;;
					esac ;;
				delete) say "        ${C_WARN}<- your plan: DELETE it, so the merge result will not have it${C_OFF}" ;;
				esac
				if [ -z "$pr_mact" ]; then
					case "$pr_kind" in
					only-from) say "        ${C_OK}<- no instruction: the merge WILL ADD this file${C_OFF}" ;;
					only-into) say "        ${C_DIM}<- no instruction: the merge leaves this file alone${C_OFF}" ;;
					esac
					case "$pr_verdict" in
					clean)    say "                 ${C_OK}<- both changes merge${C_OFF}" ;;
					conflict) say "                 ${C_WARN}<- COLLISION, neither wins - choose with m${C_OFF}" ;;
					esac
				fi
			done < "$pr_rec.s"
		fi
		say ""
		rule
		say "  ${C_BOLD}how to read a file:${C_OFF} ${C_DIM}left column${C_OFF} = $P_FROM ${C_DIM}(being merged in)${C_OFF}"
		say "                             ${C_DIM}right column${C_OFF} = $P_INTO ${C_DIM}(receiving it)${C_OFF}"
		say "    ${C_FROM_ADD}green${C_OFF}   $P_FROM ADDED this line          ${C_FROM_REP}blue${C_OFF}    $P_FROM's old version, replaced"
		say "    ${C_INTO_ADD}magenta${C_OFF} $P_INTO ADDED this line          ${C_INTO_REP}red${C_OFF}     $P_INTO's old version, replaced"
		say "    ${C_DIM}press e on a file to edit what the merge would produce (the resultant file)${C_OFF}"
		rule
		[ -f "$PLAN_FILE" ] && say "  ${C_DIM}instructions so far: `plan_count`  (in $PLAN_FILE)${C_OFF}"
		say ""

		[ "$OPT_SUMMARY" = 1 ] && return 0

		printf '\n  file number, [p]lan, or [q] for the next directory > '
		read -r pr_choice
		[ -n "$pr_choice" ] || continue
		case "$pr_choice" in
		q|Q) return 0 ;;
		p|P) plan_sync; plan_show; continue ;;
		esac
		case "$pr_choice" in
		''|*[!0-9]*) say "  '$pr_choice' is not a file number."; continue ;;
		esac

		pr_want=`expr $pr_choice + 0`
		pr_i=0
		pr_pick=""
		while IFS='|' read -r pr_kind pr_pth pr_verdict pr_act pr_side; do
			[ -n "$pr_kind" ] || continue
			pr_i=$((pr_i + 1))
			if [ "$pr_i" = "$pr_want" ]; then
				pr_pkind=$pr_kind
				pr_ppath=$pr_pth
				pr_pverd=$pr_verdict
				pr_pick=1
				break
			fi
		done < "$pr_rec.s"
		[ -z "$pr_pick" ] && { say "  there is no file number $pr_want."; continue; }
		pr_conf=0
		case "$pr_pkind" in
		only-from) pr_verdict="only in $P_FROM - the merge would create it" ;;
		only-into) pr_verdict="only in $P_INTO - the merge leaves it alone" ;;
		both)
			if [ "$pr_pverd" = conflict ]; then
				pr_verdict="CHANGED BY BOTH AND THEY COLLIDE - neither update wins"
				pr_conf=1
			else
				pr_verdict="CHANGED BY BOTH - the two changes merge cleanly"
			fi ;;
		esac
		say ""
		plan_init
		show_file "$pr_fromref" "$pr_intoref" "$pr_tree" "$pr_ppath" \
			"$pr_verdict" "$pr_conf" "$pr_repo"
		say ""
	done
}

# ===========================================================================
# apply
# ===========================================================================
apply_all() {
	if [ ! -f "$PLAN_FILE" ]; then
		say "  ${C_WARN}no instruction file at $PLAN_FILE - nothing to apply${C_OFF}"
		return 1
	fi
	# Read the base commits the PLAN was built against BEFORE plan_sync runs.
	# plan_sync refreshes them to the current base, which is right for a
	# preview but would erase the very thing we want to compare against.
	ap_base_was=""
	ap_bw_repo=`awk -F'\t' '$1 ~ /^merge\.base\./ { print $1; exit }' "$PLAN_FILE" 2>/dev/null`
	[ -n "$ap_bw_repo" ] && ap_base_was=`grep "^$ap_bw_repo" "$PLAN_FILE" 2>/dev/null`
	plan_sync
	ap_branch=`plan_branch`
	[ -n "$ap_branch" ] || ap_branch="${P_FROM}_${P_INTO}"

	# ---- never reset a branch that already exists ------------------
	# "git checkout -B" silently moves an existing branch, which would throw
	# away whatever is on it.  Refuse and ask for a different name.
	ap_try=0
	while :; do
		ap_clash=`branch_clash "$ap_branch"`
		[ -z "$ap_clash" ] && break
		ap_try=`expr $ap_try + 1`
		say ""
		say "  ${C_WARN}refusing to merge into an existing branch.${C_OFF}"
		say "  '${ap_branch}' already exists:$ap_clash"
		say ""
		say "  merging into it would reset it and lose whatever is on it now."
		if [ "$ap_try" -ge 3 ]; then
			say "  ${C_WARN}too many attempts - nothing was changed${C_OFF}"
			return 1
		fi
		printf '\n  %snew branch name for the merge (or ENTER to stop)%s > ' "$C_BOLD" "$C_OFF"
		read -r ap_new
		if [ -z "$ap_new" ]; then
			say "  stopped - nothing was changed"
			return 1
		fi
		ap_branch=$ap_new
		# record the new name so the file and the merge agree
		ap_tmp="$PLAN_FILE.tmp.$$"
		{
			grep '^merge\.from' "$PLAN_FILE" 2>/dev/null
			grep '^merge\.into' "$PLAN_FILE" 2>/dev/null
			printf 'merge.branch\t%s\n' "$ap_branch"
			grep -v '^merge'  "$PLAN_FILE" 2>/dev/null
		} > "$ap_tmp"
		mv "$ap_tmp" "$PLAN_FILE"
		say "  will merge into ${C_OK}${ap_branch}${C_OFF}"
	done

	say ""
	plan_show
	# No confirmation is asked for: firing --apply means do it.  The only
	# thing that still stops is the guard against clobbering an existing
	# branch, further down.

	# ---- remember where the user was, so we can put them back ----------
	ap_was_on=""
	cd "$ROOT/TopStor" 2>/dev/null
	ap_was_on=`git rev-parse --abbrev-ref HEAD 2>/dev/null`
	[ "$ap_was_on" = "HEAD" ] && ap_was_on=""

	# ---- step 0: bring the BASE branch up to date ---------------------
	# The whole plan was worked out against $P_INTO, so merging without
	# refreshing it first would merge into a branch that is behind origin.
	# systempull.sh recreates that branch in every repository, so it runs once,
	# here, and not per directory.
	ap_pull=""
	[ -x "$ROOT/TopStor/systempull.sh" ] && ap_pull="$ROOT/TopStor/systempull.sh"
	[ -z "$ap_pull" ] && [ -x /TopStor/systempull.sh ] && ap_pull=/TopStor/systempull.sh
	printf '\n'; rule; printf ' step 0  refresh the base branch %s\n' "$P_INTO"; rule
	if [ -z "$ap_pull" ]; then
		say "  ${C_DIM}no systempull.sh found - merging with the local $P_INTO as it stands.${C_OFF}"
		say "  ${C_DIM}if that is not what you want, refresh it yourself and run --apply again:${C_OFF}"
		say "    /TopStor/systempull.sh $P_INTO"
	else
		# Its output is shown as it happens - nothing is captured or hidden.
		say "  ${C_DIM}running systempull.sh $P_INTO - its output follows:${C_OFF}"
		say "  ${C_DIM}----------------------------------------${C_OFF}"
		"$ap_pull" "$P_INTO"
		ap_prc=$?
		say "  ${C_DIM}----------------------------------------${C_OFF}"
		if [ "$ap_prc" -eq 0 ]; then
			say "  ${C_OK}base branch $P_INTO refreshed.${C_OFF}"
		else
			say "  ${C_WARN}systempull.sh exited $ap_prc - stopping, nothing was merged.${C_OFF}"
			rule
			return 1
		fi
	fi

	# ---- did the base move under the plan? ---------------------------
	# The preview recorded the commit each base branch was at.  If the
	# refresh moved it, the comparison this plan came from was made against
	# something older than what we are about to merge into.
	ap_moved=""
	for ap_repo in $REPOS; do
		ap_path="$ROOT/$ap_repo"
		[ -d "$ap_path" ] || continue
		cd "$ap_path" 2>/dev/null || continue
		git rev-parse --git-dir >/dev/null 2>&1 || continue
		ap_was=`printf '%s\n' "$ap_base_was" | awk -F'\t' -v k="merge.base.$ap_repo" '$1==k { print $2; exit }'`
		[ -n "$ap_was" ] || continue
		ap_now=`git rev-parse "$P_INTO" 2>/dev/null`
		[ -n "$ap_now" ] || continue
		[ "$ap_was" = "$ap_now" ] && continue
		ap_moved="$ap_moved $ap_repo"
	done
	if [ -n "$ap_moved" ]; then
		say ""
		say "  ${C_WARN}the base branch has MOVED since this plan was written:${C_OFF}"
		for ap_repo in $ap_moved; do
			say "     $ap_repo  $P_INTO is no longer the commit the preview used"
		done
		say "  ${C_DIM}the plan may no longer describe what the merge will produce.${C_OFF}"
	fi

	ap_conflicts=0
	ap_merged=0
	for ap_repo in $REPOS; do
		ap_path="$ROOT/$ap_repo"
		cd "$ap_path" 2>/dev/null || continue
		git rev-parse --git-dir >/dev/null 2>&1 || continue
		ap_from=`resolve_ref "$P_FROM"`
		ap_into=`resolve_ref "$P_INTO"`
		if [ -z "$ap_from" ] || [ -z "$ap_into" ]; then
			say "  ${C_WARN}$ap_repo : one of the branches is missing here - skipped${C_OFF}"
			continue
		fi
		ap_n=`awk -F'\t' -v r="$ap_repo" '$1==r' "$PLAN_FILE" 2>/dev/null | wc -l`

		printf '\n'; rule; printf ' %s\n' "$ap_path"; rule
		say "  ${C_BOLD}step 1${C_OFF}  create $ap_branch and merge $ap_from into it"

		if [ -f "`git rev-parse --git-dir`/MERGE_HEAD" ]; then
			say "  ${C_WARN}a merge is already in progress here - resolve it first${C_OFF}"
			ap_conflicts=`expr $ap_conflicts + 1`
			continue
		fi
		# No stashing.  Uncommitted work simply travels with the checkout and
		# is committed later by systempush.sh, which is the one that commits
		# and pushes all three repositories.
		if ! git checkout -q -B "$ap_branch" "$ap_into"; then
			say "  ${C_WARN}could not create $ap_branch${C_OFF}"
			say "  ${C_DIM}uncommitted files that would be overwritten by the checkout:${C_OFF}"
			git status --porcelain 2>/dev/null | head -8 | sed 's/^/     /'
			say "  ${C_DIM}commit or discard them, then run --apply again.${C_OFF}"
			continue
		fi
		git merge --no-ff --no-edit "$ap_from" -m "merge $ap_from into $ap_into" \
			> "$TMPD/$ap_repo.merge" 2>&1
		ap_mrc=$?
		if [ "$ap_mrc" -ne 0 ]; then
			sed 's/^/     /' "$TMPD/$ap_repo.merge" | head -10
			say ""
			say "  ${C_WARN}the branches collide. Checking whether your 'keep'"
			say "  instructions resolve it:${C_OFF}"
			ap_unres=""
			ap_fixed=0
			for cf in `git diff --name-only --diff-filter=U 2>/dev/null`; do
				ap_k=`awk -F'\t' -v r="$ap_repo" -v p="$cf" \
					'$1==r && $2=="keep" && $3==p { print $4; exit }' "$PLAN_FILE" 2>/dev/null`
				if [ -n "$ap_k" ]; then
					ap_src="$ap_from"
					[ "$ap_k" = into ] && ap_src="$ap_into"
					if git checkout "$ap_src" -- "$cf" 2>/dev/null && git add "$cf" 2>/dev/null; then
						say "    ${C_FROM_ADD}keep${C_OFF} $cf  ${C_DIM}-> the $ap_k version${C_OFF}"
						ap_fixed=`expr $ap_fixed + 1`
					else
						ap_unres="$ap_unres $cf"
					fi
				else
					ap_unres="$ap_unres $cf"
				fi
			done
			if [ -z "$ap_unres" ]; then
				git commit --no-edit -q >/dev/null 2>&1
				say "  ${C_OK}all conflicts resolved by your instructions - merge completed.${C_OFF}"
				say "  now on $ap_branch"
				ap_merged=`expr $ap_merged + 1`
			else
				say ""
				say "  ${C_WARN}these files still collide and have no 'keep' instruction:${C_OFF}"
				for cf in $ap_unres; do say "     $cf"; done
				say ""
				say "  ${C_WARN}open the file in the preview, press m, and choose which"
				say "  side to keep - then run --apply again.${C_OFF}"
				say "  nothing else was touched."
				ap_conflicts=`expr $ap_conflicts + 1`
				continue
			fi
		else
			say "  ${C_OK}merged.${C_OFF} now on $ap_branch"
			ap_merged=`expr $ap_merged + 1`
		fi

		if [ "$ap_n" -eq 0 ]; then
			say "  ${C_DIM}no instructions for $ap_repo${C_OFF}"
			continue
		fi
		say ""
		say "  ${C_BOLD}step 2${C_OFF}  apply the $ap_n instruction(s)"

		# the instruction list goes on fd 3, so stdin stays free for the
		# one prompt that is still asked: the "a different name" reply when
		# the merge branch already exists somewhere
		# A line that holds a real tab arrives with more fields than it
		# should.  Catch it here, while the fields are still visible, and
		# hand it on as __BADFIELDS__ rather than silently truncating it.
		awk -F'\t' -v r="$ap_repo" '
			$1==r {
				if (NF > 5)
					printf "__BADFIELDS__\t%s\t%s\t%s\n", $3, $2, $6
				else
					printf "%s\t%s\t%s\t%s\n", $2, $3, $4, $5
			}' "$PLAN_FILE" 2>/dev/null > "$TMPD/$ap_repo.instr"

		while IFS='	' read -r ap_act ap_f ap_d1 ap_d2 ap_extra <&3; do
			[ -n "$ap_act" ] || continue
			if [ "$ap_act" = "__BADFIELDS__" ]; then
				say "  ${C_WARN}REFUSED${C_OFF}  $ap_d1 on $ap_f"
				say "     its text contains a REAL tab, so the fields run together"
				say "     and it would be applied wrongly.  Write the tab as"
				say "     ${C_BOLD}\\t${C_OFF} instead, for example:"
				say "       $ap_d1	$ap_f	<old text>	<new text>"
				say "     nothing was changed in that file."
				continue
			fi
			case "$ap_act" in
			merge.*|'#'*) continue ;;
			keep|delete|del-line|rep-line|add-line) ;;
			*)
				say "  ${C_WARN}SKIPPED${C_OFF} unknown action '$ap_act' on $ap_f"
				continue ;;
			esac
			case "$ap_act" in
			keep)
				ap_src="$ap_from"
				[ "$ap_d1" = into ] && ap_src="$ap_into"
				say "  ${C_FROM_ADD}keep${C_OFF} $ap_f  ${C_DIM}(the $ap_d1 side)${C_OFF}"
				if git cat-file -e "$ap_src:$ap_f" 2>/dev/null; then
					if git checkout "$ap_src" -- "$ap_f" 2>/dev/null; then
						say "    ${C_OK}done${C_OFF}"
					else
						say "    ${C_WARN}failed - is the file in $ap_src?${C_OFF}"
					fi
				else
					# The chosen side has no such file, so "keep that side"
					# means the result must not have it either.  Otherwise a
					# file that only exists in the from branch could never be
					# left out.
					say "    ${C_DIM}$ap_d1 has no such file, so it will NOT be in the result${C_OFF}"
					if git ls-files --error-unmatch -- "$ap_f" >/dev/null 2>&1; then
						if git rm -q -- "$ap_f" 2>/dev/null; then
							say "    ${C_OK}removed${C_OFF}"
						else
							say "    ${C_WARN}could not remove it${C_OFF}"
						fi
					else
						say "    ${C_DIM}it is not in the merge result anyway - nothing to do${C_OFF}"
					fi
				fi ;;
			delete)
				say "  ${C_WARN}delete${C_OFF} $ap_f"
				if git rm -q -- "$ap_f" 2>/dev/null; then
					say "    ${C_OK}done${C_OFF}"
				else
					say "    ${C_WARN}failed${C_OFF}"
				fi ;;
			del-line|rep-line|add-line)
				say "  ${C_FROM_REP}$ap_act${C_OFF} $ap_f"
				if [ "$ap_act" = rep-line ] || [ "$ap_act" = add-line ]; then
					say "       ${C_DIM}$ap_d1${C_OFF}"
					say "    -> ${C_DIM}$ap_d2${C_OFF}"
				else
					say "       ${C_DIM}$ap_d1${C_OFF}"
				fi
				ap_opt=""
				[ "$ap_act" = del-line ] && ap_opt="--del-line"
				[ "$ap_act" = rep-line ] && ap_opt="--rep-line"
				[ "$ap_act" = add-line ] && ap_opt="--add-line"
				if [ "$ap_opt" = "--del-line" ]; then
					ap_out=`python3 "$TMPD/apply.py" --file "$ap_f" --del-line "$ap_d1"`
				else
					ap_out=`python3 "$TMPD/apply.py" --file "$ap_f" "$ap_opt" "$ap_d1" "$ap_d2"`
				fi
				say "    ${C_OK}$ap_out${C_OFF}"
				;;
			esac
		done 3< "$TMPD/$ap_repo.instr"
	done

	# ---- step 3: hand over to systempush.sh --------------------------
	# It is the script that commits the new branch and pushes all three
	# repositories, including any uncommitted work that came along with the
	# checkout.  Nothing is committed or pushed from here.
	ap_push=""
	[ -x "$ROOT/TopStor/systempush.sh" ] && ap_push="$ROOT/TopStor/systempush.sh"
	[ -z "$ap_push" ] && [ -x /TopStor/systempush.sh ] && ap_push=/TopStor/systempush.sh
	printf '\n'; rule; printf ' step 3  commit and push %s\n' "$ap_branch"; rule
	if [ "$ap_conflicts" -gt 0 ]; then
		say "  ${C_WARN}$ap_conflicts directory/directories still have unresolved conflicts.${C_OFF}"
		say "  ${C_WARN}not pushing - fix them first, then run --apply again.${C_OFF}"
		rule
		return 1
	fi
	if [ "$ap_merged" -eq 0 ]; then
		# Nothing was merged, so there is no new branch to push.  Running
		# systempush.sh here would commit whatever happens to be in the
		# working tree onto whatever branch each repo happens to be on.
		say "  ${C_WARN}no directory was merged, so there is nothing to push.${C_OFF}"
		say "  ${C_DIM}systempush.sh was NOT run - it would have committed to the${C_OFF}"
		say "  ${C_DIM}wrong branches. Fix the problem above and run --apply again.${C_OFF}"
		rule
		return 1
	fi
	if [ -z "$ap_push" ]; then
		say "  ${C_WARN}no systempush.sh found - nothing was committed or pushed.${C_OFF}"
		say "  commit and push by hand, for example:"
		say "    /TopStor/systempush.sh $ap_branch"
	else
		say "  ${C_DIM}running systempush.sh $ap_branch - its output follows:${C_OFF}"
		say "  ${C_DIM}----------------------------------------${C_OFF}"
		"$ap_push" "$ap_branch"
		ap_sprc=$?
		say "  ${C_DIM}----------------------------------------${C_OFF}"
		if [ "$ap_sprc" -eq 0 ]; then
			say "  ${C_OK}$ap_branch committed and pushed.${C_OFF}"
		else
			say "  ${C_WARN}systempush.sh exited $ap_sprc - check the output above.${C_OFF}"
		fi
	fi

	printf '\n'
	rule
	if [ -n "$ap_was_on" ]; then
		say "  ${C_DIM}you were on${C_OFF} $ap_was_on ${C_DIM}before this ran.${C_OFF}"
		say "  ${C_DIM}that branch was NOT modified - $ap_branch was created from"
		say "  ${C_DIM}$P_INTO and you are now standing on $ap_branch.${C_OFF}"
		say "  ${C_DIM}to go back:${C_OFF}  git checkout $ap_was_on"
	fi
	rule
	return 0
}

# ===========================================================================
# main
# ===========================================================================
if [ "$OPT_PLAN" = 1 ]; then
	plan_sync
	plan_show
	exit 0
fi

if [ "$OPT_APPLY" = 1 ]; then
	apply_all
	exit $?
fi

plan_prepare
plan_init
# An existing plan keeps whatever merge.branch it already carries, so
# --branch must still be honoured here - otherwise the flag is silently
# ignored on every run after the first.
plan_sync
n_done=0
for repo in $REPOS; do
	[ -d "$ROOT/$repo" ] || continue
	( cd "$ROOT/$repo" 2>/dev/null && git rev-parse --git-dir >/dev/null 2>&1 ) || continue
	preview_repo "$repo"
	n_done=`expr $n_done + 1`
done
cd "${ROOT:-/}/TopStor" 2>/dev/null

if [ "$OPT_SUMMARY" = 0 ]; then
	printf '\n'
	rule
	say " preview finished for $n_done directory/directories."
	say ""
	plan_show
	say "  to carry this out:   systempregetdiff.sh $P_FROM $P_INTO --apply"
	say "  to just read it:     systempregetdiff.sh $P_FROM $P_INTO --plan"
	say ""
	say "  ${C_DIM}to name the merged branch something else, add --branch NAME to either"
	say "  command, or edit the 'merge.branch' line in the instruction file above."
	say "  The name it will use now is:${C_OFF} `plan_branch`${C_DIM}."
	say "  If that name is already taken locally, on origin or on abdopuppet,"
	say "  the apply step asks for another one and never resets what is there."
	rule
fi
[ "$n_done" -gt 0 ] || exit 1
exit 0
