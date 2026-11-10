# lib-tree-state.sh — `bash lib.sh tree-state` (lib.sh sources this file for that subcommand only).

# tree_state <dir> — one line fingerprinting a work tree: HEAD, status, diff against HEAD, the index, and the content of
# untracked files that are not ignored (an untracked nested repo by its own tree-state). Ignored files are NOT covered (a
# change there is not seen). Exit 1 when <dir> is not a git work tree, 2 on bad arguments.
tree_state() {
  [ $# -eq 1 ] && [ -n "$1" ] || { echo "Usage: lib.sh tree-state <dir>" >&2; return 2; }
  [ "$(git -C "$1" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] || { echo "corecrew: $1 is not a git work tree" >&2; return 1; }
  {
    git -C "$1" rev-parse HEAD 2>/dev/null
    git -C "$1" status --porcelain -uall 2>/dev/null
    git -C "$1" diff HEAD --binary 2>/dev/null
    git -C "$1" ls-files -s 2>/dev/null
    git -C "$1" ls-files -z --others --exclude-standard 2>/dev/null | while IFS= read -r -d '' f; do
      printf '%s ' "$f"
      if [ -L "$1/$f" ]; then readlink "$1/$f"
      elif [ -d "$1/$f" ]; then bash "$_LIB_DIR/lib.sh" tree-state "$1/$f" 2>/dev/null   # untracked nested repo
      else cksum 2>/dev/null < "$1/$f"; fi
    done
  } | cksum | tr ' ' '-'
}
