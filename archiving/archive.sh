#!/usr/bin/env bash
#
# archive – create or restore .tar.gz archives
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
TAR_OPTS=(--owner=0 --group=0)   # extra options for both create and extract
COMPRESSION_LEVEL=6              # gzip level: 1 (fast) … 9 (smallest)
VERBOSE=0                        # 1 = show tar's -v listing

# ── Helpers ───────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
Usage: archive [options] <source> <destination>

   -r, --restore   Extract the archive into the destination directory
                   (created if it does not exist).
   -v              Verbose.
   -h, --help      Show this help and exit.

Without  -r :  source = directory,     destination = .tar.gz file
With     -r :  source = .tar.gz file,  destination = directory
EOF
}
die() { echo "error: $*" >&2; exit 1; }

# ── Parse flags ───────────────────────────────────────────────────────────────
RESTORE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--restore) RESTORE=1; shift ;;
        -v)           VERBOSE=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        --)           shift; break ;;
        -*)           die "unknown option: $1" ;;
        *) break ;; # first positional arg → stop parsing
    esac
done

[[ $# -eq 2 ]] || { usage >&2; die "expected 2 positional args, got $#"; }
source="$1"
dest="$2"

# -v only when verbose; written as an if to avoid a `set -e` gotcha.
if [[ $VERBOSE -eq 1 ]]; then T_MODE="v"; else T_MODE=""; fi

# ── Create ────────────────────────────────────────────────────────────────────
if [[ $RESTORE -eq 0 ]]; then
    [[ -d "$source" ]] || die "source is not a directory: $source"

    # Refuse a destination that lives inside the source (would archive itself).
    case "$dest" in
        "$source"/*) die "destination is inside the source directory" ;;
    esac

    mkdir -p "$(dirname "$dest")"

    # tar writes an uncompressed stream to stdout; gzip compresses to the file.
    tar "${TAR_OPTS[@]}" -c${T_MODE}f - -C "$source" . \
        | gzip -"$COMPRESSION_LEVEL" > "$dest"

    echo "created $dest"
# ── Restore ───────────────────────────────────────────────────────────────────
else
    [[ -f "$source" ]] || die "archive file does not exist: $source"

    mkdir -p "$dest"

    gzip -dc "$source" \
        | tar "${TAR_OPTS[@]}" -x${T_MODE}f - -C "$dest"

    echo "restored $source → $dest"
fi
