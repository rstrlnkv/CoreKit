# scripts/fold-rules.awk — a block of rule subsections (rule-block.awk's output) folded into a
# CLAUDE.md, for adopt.sh:
#   awk -v BF=<block file> -f fold-rules.awk <CLAUDE.md>   (prints the new CLAUDE.md)
# The block goes at the end of the "## Rules" section (before the next "## " heading outside a code
# fence), or at the end of the file under a new "## Rules" heading. Blank lines are held back (nb) so
# the block, which starts with one, joins without a double gap. Portable awk (BSD awk).
function emit(   l) { while ((getline l < BF) > 0) print l; close(BF); done = 1 }
function flush() { while (nb > 0) { print ""; nb-- } }
{
  line = $0; sub(/\r$/, "", line)
  if (line ~ /^[ \t]*$/ && !fence) { nb++; next }
  if (!done && inr && !fence && line ~ /^## /) { nb = 0; emit(); print ""; inr = 0 }
  flush()
  if (line ~ /^(```|~~~)/) fence = !fence
  if (!done && !fence && line ~ /^## Rules[ \t]*$/) inr = 1
  print
}
END { if (!done) { nb = 0; if (!inr) { print ""; print "## Rules" }; emit() } else flush() }
