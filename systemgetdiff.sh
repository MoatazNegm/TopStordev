#!/bin/sh
#
# systemgetdiff.sh
# ================
#
# Shows, for each of the three TopStor repositories, exactly what each side of
# a merge contributed - and in a way that can actually be read.
#
# The old version ran
#
#     git diff --color=always -U3 <current> <run> | less -R
#
# once per directory, which has three problems:
#
#   * it only ever showed ONE side of the comparison, so a line that was
#     added by the argument branch and a line that was added by the current
#     branch came out in the same colour and were impossible to tell apart;
#   * "git diff A B" is a two-way diff, so files that only exist in A look
#     identical to files that only exist in B unless you already know which
#     is which;
#   * it refused to do anything at all unless HEAD happened to be named
#     RunningBranch_ToTestbranch.
#
# This version, per repository:
#
#   1. prints a SUMMARY: which files were ADDED and by which branch, which
#      were DELETED and by which branch, which were MODIFIED and - where both
#      branches touched the same file - which side's version the merge kept;
#   2. you type a file number and it opens a two column, colour coded view of
#      that file, with a distinct colour for "added by the argument branch",
#      "added by the current branch", and one for each side of a replaced
#      line;
#   3. press 'q' inside that view to come back to the summary;
#   4. press 'q' at the summary to move on to the next directory;
#   5. after the last directory it prints a wrap up and exits.
#
# COLOUR
#   Everything that carries meaning is coloured: added lines, replaced lines,
#   the branch names, the verdict and the file list.  The four line colours are
#     green   added by the argument branch (left)
#     cyan    added by the current branch  (right)
#     red     the argument's version, replaced
#     yellow  the current's version, replaced
#   The viewer is a pager built into this script rather than "less", because
#   a less with no terminfo entry silently strips every colour code - which
#   is exactly the case in this container.
#
# usage:  systemgetdiff.sh [--summary] [--repo NAME] [--pager X] [--width N]
#

REPOS="${SYSTEM_REPOS:-TopStor pace topstorweb}"
ROOT="${SYSTEM_ROOT:-}"
MANIFEST="${MERGE_MANIFEST:-/root/.systemmerge_manifest}"
WIDTH="${SYSTEMDIFF_WIDTH:-170}"

OPT_SUMMARY=0
OPT_REPO=""
PAGER_MODE=builtin

while [ $# -gt 0 ]; do
	case "$1" in
	--summary) OPT_SUMMARY=1; shift ;;
	--repo)    OPT_REPO=$2; shift 2 ;;
	--width)   WIDTH=$2; shift 2 ;;
	--pager)
		PAGER_MODE=$2; shift 2
		case "$PAGER_MODE" in
		builtin|none|less) ;;
		*) echo "--pager takes builtin, none or less" >&2; exit 1 ;;
		esac ;;
	-h|--help)
		sed -n '3,50p' "$0" | sed 's/^# \{0,1\}//'
		exit 0 ;;
	*) echo "unknown option '$1'" >&2; exit 1 ;;
	esac
done

TMPD=`mktemp -d /tmp/systemgetdiff.XXXXXX` || exit 1
trap 'rm -rf "$TMPD"' EXIT INT TERM

say()  { printf '%s\n' "$*"; }
rule() { printf -- '---------------------------------------------------------------------------\n'; }

# ---------------------------------------------------------------------------
# terminal colours for the legend.  Same four colours the file viewer uses, so
# the word "green" on screen really is green.
#   green  added by the argument branch (left)
#   cyan   added by the current branch  (right)
#   red    the argument's version, replaced
#   yellow the current's version, replaced
# Switched off automatically when the output is not a terminal, or when
# NO_COLOR is set, so redirected output stays clean.
# ---------------------------------------------------------------------------
C_OFF=''
C_ARG_ADD=''
C_CUR_ADD=''
C_ARG_REP=''
C_CUR_REP=''
C_WARN=''
C_OK=''
C_BOLD=''
C_DIM=''

if [ -z "$NO_COLOR" ] && { [ -t 1 ] || [ "$FORCE_COLOR" = 1 ]; }; then
	C_OFF=`printf '\033[0m'`
	C_ARG_ADD=`printf '\033[32m'`   # green
	C_CUR_ADD=`printf '\033[36m'`   # cyan
	C_ARG_REP=`printf '\033[31m'`   # red
	C_CUR_REP=`printf '\033[33m'`   # yellow
	C_WARN=`printf '\033[1;31m'`   # bold red   - unresolved
	C_OK=`printf '\033[1;32m'`     # bold green - clean
	C_BOLD=`printf '\033[1;37m'`
	C_DIM=`printf '\033[2;37m'`
fi

legend() {
	say ""
	rule
	say "  ${C_ARG_ADD}green${C_OFF}  = added by $P_LEGEND_ARG ${C_DIM}(left column)${C_OFF}"
	say "  ${C_CUR_ADD}cyan${C_OFF}   = added by $P_LEGEND_CUR ${C_DIM}(right column)${C_OFF}"
	say "  ${C_ARG_REP}red${C_OFF}    = $P_LEGEND_ARG's version, replaced by the other branch"
	say "  ${C_CUR_REP}yellow${C_OFF} = $P_LEGEND_CUR's version, replaced by the other branch"
	rule
}

# ===========================================================================
# the pager - keeps colour, reads keys from /dev/tty
# ===========================================================================
cat > "$TMPD/pager.py" <<'PYEOF'
import os, sys, select

HELP = "q quit | space next | b back | j/k line | g/G top/bottom"

def get_size():
    for fd in (1, 0):
        try:
            sz = os.get_terminal_size(fd)
            return max(sz.lines, 10), max(sz.columns, 40)
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
            if two in (b"[A", b"OA"): return "UP"
            if two in (b"[B", b"OB"): return "DOWN"
            if three == b"[5~": return "PGUP"
            if three == b"[6~": return "PGDN"
            if two == b"[H": return "HOME"
            if two == b"[F": return "END"
            return "ESC"
        return "ESC"
    return ch.decode("utf-8", "replace")

def main():
    if len(sys.argv) < 2:
        sys.stderr.write("pager: no file given\n"); return 1
    try:
        with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as fh:
            data = fh.read()
    except OSError as exc:
        sys.stderr.write("pager: %s\n" % exc); return 1

    lines = data.split("\n")
    if lines and lines[-1] == "":
        lines.pop()

    out = sys.stdout
    if not out.isatty():
        out.write(data); out.flush(); return 0
    try:
        tty_in = open("/dev/tty", "r+b", buffering=0)
    except OSError:
        out.write(data); out.flush(); return 0

    old = None
    try:
        import termios, tty
        fd = tty_in.fileno()
        old = termios.tcgetattr(fd)
        tty.setcbreak(fd)
    except Exception:
        out.write(data); out.flush(); return 0

    rows, cols = get_size()
    body = max(rows - 2, 5)
    top = 0
    try:
        while True:
            out.write("\x1b[H\x1b[2J")
            for ln in lines[top:top + body]:
                out.write(ln[:cols - 1] if len(ln) > cols - 1 else ln)
                out.write("\n")
            last = min(top + body, len(lines))
            pct = 100 if len(lines) <= body else int(top * 100 / max(len(lines) - body, 1))
            bar = " %s | lines %d-%d of %d (%d%%) " % (HELP, top + 1, last, len(lines), pct)
            if len(bar) > cols - 1:
                bar = bar[:cols - 1]
            out.write("\x1b[7m" + bar + "\x1b[0m")
            out.flush()

            k = read_key(fd)
            if k is None:
                continue
            if k in ("q", "Q", "ESC", "\x03", "\x04"):
                break
            if k in (" ", "PGDN", "\n", "j", "DOWN"):
                top += body if k in (" ", "PGDN", "\n") else 1
            elif k in ("b", "PGUP", "k", "UP"):
                top -= body if k in ("b", "PGUP") else 1
            elif k == "g":
                top = 0
            elif k == "G":
                top = max(len(lines) - body, 0)
            top = max(0, min(top, max(len(lines) - body, 0)))
    finally:
        if old is not None:
            try:
                import termios
                termios.tcsetattr(fd, termios.TCSADRAIN, old)
            except Exception:
                pass
        out.write("\x1b[0m\n"); out.flush()
        try:
            tty_in.close()
        except OSError:
            pass
    return 0

sys.exit(main())
PYEOF

# ===========================================================================
# the side by side renderer
# ===========================================================================
cat > "$TMPD/render.py" <<'PYEOF'
import argparse, difflib, subprocess, sys, os

ESC = "\x1b["
RST = ESC + "0m"

# two colours per branch: one for lines the branch ADDED, one for the branch's
# version of a line the other branch REPLACED
C_ARG_ADD   = ESC + "32m"      # green   - only in the argument branch
C_ARG_REP   = ESC + "31m"      # red     - argument's version, replaced
C_CUR_ADD   = ESC + "36m"      # cyan    - only in the current branch
C_CUR_REP   = ESC + "33m"      # yellow  - current's version, replaced
C_HEAD      = ESC + "1;37m"
C_DIM       = ESC + "2;37m"
C_MAG       = ESC + "35m"

def git_show(ref, path):
    p = subprocess.run(["git", "show", "%s:%s" % (ref, path)],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode != 0:
        return None
    return p.stdout

def git_blob(ref, path):
    p = subprocess.run(["git", "rev-parse", "%s:%s" % (ref, path)],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode != 0:
        return None
    return p.stdout.decode().strip()

def to_lines(raw):
    if raw is None:
        return None
    txt = raw.decode("utf-8", "replace")
    lines = txt.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return lines

def is_binary(raw):
    return raw is not None and b"\x00" in raw[:8000]

def fit(text, n):
    if len(text) <= n:
        return text
    if n <= 1:
        return text[:n]
    return text[:n - 1] + "\u2026"

def wrap(text, width):
    """Show the WHOLE line.  Anything longer than the column is continued on
    the next screen row instead of being cut off after the "|", so a cell can
    never look empty just because its text was too long."""
    if text is None:
        return [None]
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

def paint(text, colour, width):
    if text is None:
        return " " * width
    return colour + fit(text, width) + RST

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--left");  ap.add_argument("--right"); ap.add_argument("--merged")
    ap.add_argument("--path")
    ap.add_argument("--left-name");  ap.add_argument("--right-name")
    ap.add_argument("--repo", default="")
    ap.add_argument("--state", default="")
    ap.add_argument("--by", default="")
    ap.add_argument("--width", type=int, default=170)
    a = ap.parse_args()

    W = a.width
    if W < 90:
        W = 90
    # never paint wider than the terminal, or the right hand column runs off
    # the edge and looks empty.  stdout is a file here, so fall back to
    # /dev/tty - otherwise the real terminal width is never seen.
    def term_cols():
        for fd in (1, 0, 2):
            try:
                c = os.get_terminal_size(fd).columns
                if c:
                    return c
            except Exception:
                pass
        try:
            with open("/dev/tty") as tf:
                return os.get_terminal_size(tf.fileno()).columns
        except Exception:
            return 0
    _cols = term_cols()
    if _cols and W > _cols:
        W = max(_cols, 40)
    # One geometry for the header, the rule and every data row, so the "|"
    # always lands in the same column and no row runs past W.
    NUMW = 5        # "%4d "
    MARKW = 2       # the marker is two characters: "+A" "~A" "+C" "~C"
    GAPW = 1
    LUNIT = 2 + NUMW + MARKW + GAPW
    RUNIT = NUMW + MARKW + GAPW
    FRAME = LUNIT + 3 + RUNIT
    marker = NUMW + MARKW + GAPW
    col = (W - FRAME) // 2
    if col < 20:
        col = 20
    while FRAME + 2 * col > W and col > 8:
        col -= 1

    left_raw  = git_show(a.left,  a.path)
    right_raw = git_show(a.right, a.path)
    merged_blob = git_blob(a.merged, a.path)

    rule = "-" * W
    out = []
    out.append(C_HEAD + rule + RST)
    if a.repo:
        out.append("%s%s%s" % (C_HEAD, a.repo, RST) + ("  " + a.path if a.path else ""))
    out.append("  file    : " + a.path)
    out.append("  left    : " + C_ARG_ADD + a.left_name + RST + "   (" + a.left + ")")
    out.append("  right   : " + C_CUR_ADD + a.right_name + RST + "   (" + a.right + ")")

    if a.state:
        tag = "%s by %s" % (a.state, a.by)
        out.append("  summary : " + tag)
    if merged_blob:
        lb, rb = git_blob(a.left, a.path), git_blob(a.right, a.path)
        if merged_blob == rb and lb != rb:
            out.append("  result  : " + C_ARG_REP + "the merge kept the RIGHT (current) version"
                       + RST + " - the left branch's change is NOT in the merge")
        elif merged_blob == lb and rb != lb:
            out.append("  result  : " + C_ARG_ADD + "the merge kept the LEFT (argument) version"
                       + RST + " - the right branch's change is NOT in the merge")
        elif lb and rb and lb != rb:
            out.append("  result  : both sides' changes are present in the merged branch")

    out.append(C_HEAD + rule + RST)
    out.append("  legend  : " + C_ARG_ADD + "+A " + a.left_name + " added this line" + RST
               + "   " + C_ARG_REP + "~A " + a.left_name + "'s version (replaced)" + RST)
    out.append("            " + C_CUR_ADD + "+C " + a.right_name + " added this line" + RST
               + "   " + C_CUR_REP + "~C " + a.right_name + "'s version (replaced)" + RST)
    out.append(C_HEAD + rule + RST)

    if is_binary(left_raw) or is_binary(right_raw):
        out.append("")
        out.append(C_MAG + "  binary file - no line by line view is possible" + RST)
        for nm, raw in (("left", left_raw), ("right", right_raw)):
            if raw is None:
                out.append("  %-8s: not present in this branch" % nm)
            else:
                out.append("  %-8s: %d bytes" % (nm, len(raw)))
        sys.stdout.write("\n".join(out) + "\n")
        return

    A = to_lines(left_raw)
    B = to_lines(right_raw)

    if A is None and B is None:
        out.append("")
        out.append("  this file is not present in either branch.")
    elif A is None:
        out.append("")
        out.append(C_CUR_ADD + "  this file exists ONLY in " + a.right_name + RST)
        out.append("")
    elif B is None:
        out.append("")
        out.append(C_ARG_ADD + "  this file exists ONLY in " + a.left_name + RST)
        out.append("")

    # ---- row helpers -----------------------------------------------------
    def lgut(n, first, colour, mark):
        """Left gutter: 2 space indent + number + marker + gap."""
        if first and n:
            return "  " + colour + "%4d " % n + RST + colour + mark + RST + " "
        return " " * LUNIT

    def rgut(n, first, colour, mark):
        """Right gutter: number + marker + gap (no extra indent)."""
        if first and n:
            return colour + "%4d " % n + RST + colour + mark + RST + " "
        return " " * RUNIT

    def lcell(text, colour):
        # pad the PLAIN text first, then colour it - padding a coloured string
        # would count the escape bytes as characters
        if text is None:
            return " " * col
        return colour + text.ljust(col) + RST

    def row(ln, ltxt, lcol, lmark, rn, rtxt, rcol, rmark):
        """One logical line -> as many screen rows as the text needs."""
        lc = wrap(ltxt, col)
        rc = wrap(rtxt, col)
        res = []
        for i in range(max(len(lc), len(rc))):
            a = lc[i] if i < len(lc) else None
            b = rc[i] if i < len(rc) else None
            res.append(lgut(ln, i == 0, lcol, lmark) + lcell(a, lcol)
                       + C_DIM + " | " + RST
                       + rgut(rn, i == 0, rcol, rmark)
                       + ((rcol + b + RST) if b is not None else ""))
        return res

    # gutter
    hdr = "  " + " " * (NUMW + MARKW + GAPW) + a.left_name \
          + C_DIM + " | " + RST + " " * (NUMW + MARKW + GAPW) + a.right_name
    out.append(C_DIM + hdr + RST)
    out.append(C_DIM + "  " + "-" * (NUMW + MARKW + GAPW) + "-" * col + "-+-"
               + "-" * (NUMW + MARKW + GAPW) + "-" * col + RST)

    if A is None or B is None:
        # the file only exists on one side - show it in THAT side's column
        only = B if A is None else A
        if A is None:
            colour, mark = C_CUR_ADD, "+C"
        else:
            colour, mark = C_ARG_ADD, "+A"
        for i, ln in enumerate(only, 1):
            if A is None:
                out += row(None, None, C_DIM, "  ", i, ln, colour, mark)
            else:
                out += row(i, ln, colour, mark, None, None, C_DIM, "  ")
        sys.stdout.write("\n".join(out) + "\n")
        return

    sm = difflib.SequenceMatcher(None, A, B, autojunk=False)
    li = ri = 0
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            for k in range(i2 - i1):
                li += 1; ri += 1
                out += row(li, A[i1 + k], C_DIM, "  ", ri, B[j1 + k], C_DIM, "  ")
        elif tag == "delete":
            for k in range(i1, i2):
                li += 1
                out += row(li, A[k], C_ARG_ADD, "+A", None, None, C_DIM, "  ")
        elif tag == "insert":
            for k in range(j1, j2):
                ri += 1
                out += row(None, None, C_DIM, "  ", ri, B[k], C_CUR_ADD, "+C")
        else:  # replace - pair them up so the two versions sit next to each other
            dl = A[i1:i2]
            dr = B[j1:j2]
            n = max(len(dl), len(dr))
            for k in range(n):
                lhas = k < len(dl)
                rhas = k < len(dr)
                if lhas and rhas:
                    li += 1; ri += 1
                    out += row(li, dl[k], C_ARG_REP, "~A", ri, dr[k], C_CUR_REP, "~C")
                elif lhas:
                    li += 1
                    out += row(li, dl[k], C_ARG_ADD, "+A", None, None, C_DIM, "  ")
                else:
                    ri += 1
                    out += row(None, None, C_DIM, "  ", ri, dr[k], C_CUR_ADD, "+C")

    out.append(C_DIM + "  " + "-" * (NUMW + MARKW + GAPW) + "-" * col + "-+-"
               + "-" * (NUMW + MARKW + GAPW) + "-" * col + RST)
    out.append("")
    out.append(C_DIM + "  press q to go back to the summary" + RST)
    sys.stdout.write("\n".join(out) + "\n")

main()
PYEOF

# ===========================================================================
# helpers
# ===========================================================================

ref_exists() { git rev-parse --verify --quiet "$1^{commit}" >/dev/null 2>&1; }

resolve_ref() {
	if ref_exists "refs/heads/$1";        then printf '%s\n' "$1"
	elif ref_exists "refs/remotes/origin/$1"; then printf '%s\n' "origin/$1"
	fi
	return 0
}

# pull one key out of a manifest line for a given repo
manifest_get() {
	[ -f "$MANIFEST" ] || return 1
	awk -v r="$1" -v k="$2" '
		{ repo=""; val=""
		  for (i = 1; i <= NF; i++) {
			p = index($i, "=")
			if (p > 0) {
				key = substr($i, 1, p - 1)
				v   = substr($i, p + 1)
				if (key == "repo") repo = v
				if (key == k)    val  = v
			}
		  }
		  if (repo == r && val != "") { print val; exit }
		}' "$MANIFEST"
}

# same classify_repo as systemmerge.sh, so both scripts agree on the summary
#
# The 5th argument is 1 when the directory still has an UNRESOLVED merge.  In
# that state there is no merge commit yet, so the "merged" ref is really just
# the current branch tip.  Reporting a winner there would be a lie, so every
# modified file is reported as 'unresolved' instead.
classify_repo() {
	cl_cur=$1; cl_arg=$2; cl_merged=$3; cl_out=$4
	cl_unres=${5:-0}

	: > "$cl_out"
	: > "$cl_out.cand"
	ref_exists "$cl_cur"    || return 0
	ref_exists "$cl_arg"    || return 0
	ref_exists "$cl_merged" || return 0

	{ git diff --name-only "$cl_cur" "$cl_merged"
	  git diff --name-only "$cl_arg" "$cl_merged"
	  git diff --name-only "$cl_cur" "$cl_arg"; } 2>/dev/null \
		| sort -u > "$cl_out.cand"

	while IFS= read -r cl_f; do
		[ -n "$cl_f" ] || continue
		cl_in_cur=N; cl_in_arg=N; cl_in_mrg=N
		git cat-file -e "$cl_cur:$cl_f"    2>/dev/null && cl_in_cur=Y
		git cat-file -e "$cl_arg:$cl_f"    2>/dev/null && cl_in_arg=Y
		git cat-file -e "$cl_merged:$cl_f" 2>/dev/null && cl_in_mrg=Y

		if [ "$cl_in_mrg" = N ]; then
			if   [ "$cl_in_cur" = Y ] && [ "$cl_in_arg" = Y ]; then
				printf 'deleted|BOTH|%s|%s\n' "$cl_f" gone >> "$cl_out"
			elif [ "$cl_in_cur" = Y ]; then
				printf 'deleted|ARG|%s|%s\n'  "$cl_f" gone >> "$cl_out"
			else
				printf 'deleted|CUR|%s|%s\n'  "$cl_f" gone >> "$cl_out"
			fi
			continue
		fi
		if [ "$cl_in_cur" = N ] && [ "$cl_in_arg" = N ]; then
			printf 'added|BOTH|%s|%s\n' "$cl_f" gone >> "$cl_out"
		elif [ "$cl_in_cur" = N ]; then
			printf 'added|ARG|%s|%s\n' "$cl_f" gone >> "$cl_out"
		elif [ "$cl_in_arg" = N ]; then
			printf 'added|CUR|%s|%s\n' "$cl_f" gone >> "$cl_out"
		else
			cl_b_cur=`git rev-parse "$cl_cur:$cl_f"    2>/dev/null`
			cl_b_arg=`git rev-parse "$cl_arg:$cl_f"    2>/dev/null`
			cl_b_mrg=`git rev-parse "$cl_merged:$cl_f" 2>/dev/null`
			if [ "$cl_unres" = 1 ]; then
				printf 'modified|BOTH|%s|unresolved\n' "$cl_f" >> "$cl_out"
			elif [ "$cl_b_cur" = "$cl_b_mrg" ] && [ "$cl_b_arg" = "$cl_b_mrg" ]; then
				continue
			elif [ "$cl_b_cur" = "$cl_b_mrg" ]; then
				printf 'modified|BOTH|%s|kept-CUR\n'    "$cl_f" >> "$cl_out"
			elif [ "$cl_b_arg" = "$cl_b_mrg" ]; then
				printf 'modified|BOTH|%s|kept-ARG\n'    "$cl_f" >> "$cl_out"
			else
				printf 'modified|BOTH|%s|both-merged\n' "$cl_f" >> "$cl_out"
			fi
		fi
	done < "$cl_out.cand"
	rm -f "$cl_out.cand"
}

banner() {
	printf '\n'
	rule
	printf ' %s\n' "$1"
	rule
}

# ===========================================================================
# per repository view
# ===========================================================================
show_repo() {
	sr_repo=$1
	sr_path="$ROOT/$sr_repo"
	cd "$sr_path" 2>/dev/null || return 1
	git rev-parse --git-dir >/dev/null 2>&1 || return 1

	sr_arg=`manifest_get "$sr_repo" arg`
	sr_cur=`manifest_get "$sr_repo" current`
	sr_mrg=`manifest_get "$sr_repo" merged`
	sr_status=`manifest_get "$sr_repo" status`

	# --- fall back to the branch-name convention when there is no manifest
	if [ -z "$sr_arg" ] || [ -z "$sr_cur" ]; then
		sr_head=`git rev-parse --abbrev-ref HEAD 2>/dev/null`
		case "$sr_head" in
		*_*)
			sr_mrg=${sr_mrg:-$sr_head}
			sr_arg=`echo "$sr_head" | sed 's/_.*$//'`
			sr_cur=`echo "$sr_head" | sed 's/^[^_]*_//'`
			;;
		esac
		if [ -z "$sr_arg" ] || [ -z "$sr_cur" ]; then
			banner "$sr_path"
			say "  No merged branch found for this directory."
			say "  It is currently on: ${sr_head:-<unknown>}"
			say ""
			say "  Expected either:"
			say "    * the branch checked out to be named <argument>_<current>, or"
			say "    * a manifest from a systemmerge.sh run at $MANIFEST"
			say ""
			say "  Run systemmerge.sh <branch> first, or check out the merged branch."
			return 0
		fi
	fi

	sr_argref=`resolve_ref "$sr_arg"`
	sr_curref=`resolve_ref "$sr_cur"`
	[ -z "$sr_mrg" ] && sr_mrg=$sr_mrg
	if ! ref_exists "$sr_mrg"; then
		sr_mrg=`git rev-parse --abbrev-ref HEAD 2>/dev/null`
	fi
	if ! ref_exists "$sr_mrg"; then
		banner "$sr_path"
		say "  merged branch '$sr_mrg' does not exist here - skipped"
		return 0
	fi
	[ -z "$sr_argref" ] && sr_argref=$sr_arg
	[ -z "$sr_curref" ] && sr_curref="origin/$sr_cur"

	sr_rec="$TMPD/$sr_repo.rec"

	sr_unres=0
	if [ -f "`git rev-parse --git-dir`/MERGE_HEAD" ]; then
		sr_unres=1
	fi

	# --- the summary --------------------------------------------------
	while :; do
		classify_repo "$sr_curref" "$sr_argref" "$sr_mrg" "$sr_rec" "$sr_unres"
		sort -t'|' -k1,1 -k2,2 -k3,3 "$sr_rec" > "$sr_rec.s" 2>/dev/null
		[ -s "$sr_rec.s" ] || : > "$sr_rec.s"

		banner "$sr_path"
		say "  merged branch   : $sr_mrg"
		say "  left  (argument): $sr_arg   [$sr_argref]"
		say "  right (current) : $sr_cur   [$sr_curref]"
		[ -n "$sr_status" ] && say "  merge status    : $sr_status"

		if [ "$sr_unres" = 1 ]; then
			say ""
			printf '  %s\n' "*** THE MERGE IN THIS DIRECTORY IS NOT FINISHED ***"
			say "  There is no merge commit here yet, so nothing below has been"
			say "  decided - it is the difference BETWEEN the two branches only."
			say "  These files are still in conflict:"
			git diff --name-only --diff-filter=U 2>/dev/null | sed 's/^/     /'
			say "  Resolve them first, then run this again:"
			say "     cd $sr_path && git status"
		fi
		say ""

		if [ ! -s "$sr_rec.s" ]; then
			say "  There are no differences between the two branches here."
		else
			sr_n=0
			sr_last=""
			while IFS='|' read -r sr_state sr_by sr_path2 sr_detail; do
				[ -n "$sr_state" ] || continue
				sr_n=`expr $sr_n + 1`
				if [ "$sr_state|$sr_by" != "$sr_last" ]; then
					sr_last="$sr_state|$sr_by"
					case "$sr_by" in
					ARG) sr_who="$sr_arg" ;;
					CUR) sr_who="$sr_cur" ;;
					*)   sr_who="both branches" ;;
					esac
					sr_cnt=`grep -c "^$sr_state|$sr_by|" "$sr_rec" 2>/dev/null`
					[ -n "$sr_cnt" ] || sr_cnt=0
					case "$sr_state" in
					added)   sr_word="${C_ARG_ADD}FILES ADDED by $sr_who${C_OFF}"    ;;
					deleted) sr_word="${C_ARG_REP}FILES DELETED by $sr_who${C_OFF}"  ;;
					*)       sr_word="${C_CUR_REP}FILES MODIFIED - both branches${C_OFF}" ;;
					esac
					if [ "$sr_unres" = 1 ]; then
						case "$sr_state" in
						added)   sr_word="${C_ARG_ADD}ONLY IN $sr_who${C_OFF}"          ;;
						deleted) sr_word="${C_ARG_REP}MISSING FROM $sr_who${C_OFF}"     ;;
						*)       sr_word="${C_WARN}CHANGED ON BOTH SIDES ($sr_who)${C_OFF}" ;;
						esac
					fi
					say "  --- $sr_word  ($sr_cnt file(s)) ---"
				fi
				case "$sr_detail" in
				kept-CUR)    sr_note="${C_CUR_ADD}  <- current version won${C_OFF}"  ;;
				kept-ARG)    sr_note="${C_ARG_ADD}  <- argument version won${C_OFF}" ;;
				both-merged) sr_note="${C_OK}  <- both changes merged${C_OFF}"       ;;
				unresolved)  sr_note="${C_WARN}  <- CONFLICT, not decided${C_OFF}"    ;;
				*)           sr_note=""                                                 ;;
				esac
				printf '   %3d  %s%s\n' "$sr_n" "$sr_path2" "$sr_note"
			done < "$sr_rec.s"
			say ""
			say "  $sr_n file(s) in total."
		fi

		say ""
		P_LEGEND_ARG=$sr_arg
		P_LEGEND_CUR=$sr_cur
		legend

		if [ "$OPT_SUMMARY" = 1 ]; then
			return 0
		fi

		printf '\n  file number, [h]elp, or [q] for the next directory > '
		read -r sr_choice
		[ -n "$sr_choice" ] || continue

		case "$sr_choice" in
		q|Q)
			return 0 ;;
		h|H)
			say ""
			say "  Type the number of a file to open it side by side."
			say "  Inside that view press 'q' to come back to this summary."
			say "  Press 'q' here to move to the next directory."
			say ""
			continue ;;
		esac

		case "$sr_choice" in
		''|*[!0-9]*) say "  '$sr_choice' is not a file number - type q to move on."; continue ;;
		esac

		sr_want=`expr $sr_choice + 0`
		sr_i=0
		sr_pick=""
		while IFS='|' read -r sr_state sr_by sr_path2 sr_detail; do
			[ -n "$sr_state" ] || continue
			sr_i=`expr $sr_i + 1`
			if [ "$sr_i" = "$sr_want" ]; then
				sr_pick="$sr_state|$sr_by|$sr_path2|$sr_detail"
				break
			fi
		done < "$sr_rec.s"

		if [ -z "$sr_pick" ]; then
			say "  there is no file number $sr_want - type q to move on."
			continue
		fi

		sr_pstate=`echo "$sr_pick" | cut -d'|' -f1`
		sr_pby=`echo "$sr_pick"    | cut -d'|' -f2`
		sr_ppath=`echo "$sr_pick"  | cut -d'|' -f3`
		sr_pdet=`echo "$sr_pick"   | cut -d'|' -f4`

		say ""
		# render to a file, then page it - never through less, which strips
		# every colour code when the terminal has no terminfo entry
		sr_view="$TMPD/view.txt"
		python3 "$TMPD/render.py" \
			--left "$sr_argref" --right "$sr_curref" --merged "$sr_mrg" \
			--path "$sr_ppath" \
			--left-name "$sr_arg" --right-name "$sr_cur" \
			--repo "$sr_path" --state "$sr_pstate" --by "$sr_pby" \
			--width "$WIDTH" > "$sr_view" 2>&1

		case "$PAGER_MODE" in
		builtin)
			python3 "$TMPD/pager.py" "$sr_view" ;;
		none)
			cat "$sr_view" ;;
		less)
			if command -v less >/dev/null 2>&1; then
				less -R -S -X "$sr_view"
			else
				cat "$sr_view"
			fi ;;
		esac
		say ""
	done
}

# ===========================================================================
# main
# ===========================================================================
if [ ! -f "$MANIFEST" ]; then
	say "no manifest at $MANIFEST"
	say "falling back to the <argument>_<current> branch name convention."
	say ""
fi

n_done=0
for repo in $REPOS; do
	if [ -n "$OPT_REPO" ] && [ "$OPT_REPO" != "$repo" ]; then
		continue
	fi
	[ -d "$ROOT/$repo" ] || continue
	show_repo "$repo"
	n_done=`expr $n_done + 1`
done

cd "${ROOT:-/}/TopStor" 2>/dev/null

if [ "$OPT_SUMMARY" = 0 ]; then
	printf '\n'
	rule
	say " end of the $n_done directory/directories."
	say ""
	say " if every merge was clean you can now push the merged branch."
	say " if a directory reported a conflict, resolve it first - systemmerge.sh"
	say " printed the exact command for that directory."
	rule
fi

[ "$n_done" -gt 0 ] || exit 1
exit 0
