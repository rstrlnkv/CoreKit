# Read tokenized models_cache.json and emit model, visibility, and supported efforts.
$0 == ":" { key = value; taking = 1; next }
$0 == "{" || $0 == "[" {
  depth++
  if (depth == 2 && $0 == "[" && key == "models") models = 1
  if (models && depth == 3) { slug = ""; visibility = ""; efforts = "" }
  if (models && depth == 4 && $0 == "[" && key == "supported_reasoning_levels") levels = 1
  key = ""; taking = 0; next
}
$0 == "}" || $0 == "]" {
  if (levels && depth == 4) levels = 0
  if (models && depth == 3 && slug ~ /^[A-Za-z0-9._-]+$/ && visibility ~ /^[a-z_]+$/)
    print slug, visibility efforts
  if (models && depth == 2) { print "#catalog"; models = 0 }
  depth--; key = ""; taking = 0; next
}
/^"/ {
  value = substr($0, 2, length($0)-2)
  if (taking && models && depth == 3 && key == "slug") slug = value
  if (taking && models && depth == 3 && key == "visibility") visibility = value
  if (taking && levels && depth == 5 && key == "effort" && value ~ /^[a-z]+$/) efforts = efforts " " value
}
{ taking = 0; key = "" }
