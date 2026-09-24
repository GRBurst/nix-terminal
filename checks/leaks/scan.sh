# usage: leak-scan <dir>
# Prints file:line:match for every hit on stderr; exits 1 if there is any.
# Generic patterns only (D14): a list of private terms here would leak them.
dir=$1
hits=$(mktemp)
cd "$dir"
opts=(--no-heading --with-filename --line-number --only-matching --hidden --no-ignore
  --glob '!checks/leaks/fixtures/**' --glob '!.git/**')

# email addresses, minus the reserved example domains and the SSH remote form
rg "${opts[@]}" -P '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}' . |
  grep -v -E '@example\.(com|org|net|invalid)$|:git@github\.com$' >>"$hits" || true

# key ids in key context (16-40 hex), and 0x-prefixed ids (8-40 hex)
rg "${opts[@]}" -P -i '(signing_?key|user\.signingkey|--local-user|--default-key|\s-u)\s*[=: ]\s*"?[0-9a-f]{16,40}\b' . >>"$hits" || true
rg "${opts[@]}" -P -i '\b0x[0-9a-f]{8,40}\b' . >>"$hits" || true

# personal home directories
rg "${opts[@]}" -P '/(home|Users)/(?!coder\b|tester\b)[A-Za-z_][A-Za-z0-9_-]*' . >>"$hits" || true

if [ -s "$hits" ]; then
  sort -u "$hits" >&2
  exit 1
fi
