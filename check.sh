#!/usr/bin/env bash
set -euo pipefail

f="build.sh"
fails=0

step() { printf '\n== %s ==\n' "$*"; }
ok()   { printf '  [ok]   %s\n' "$*"; }
bad()  { printf '  [FAIL] %s\n' "$*"; fails=$((fails+1)); }

step "1. shebang"
head -n1 "$f" | grep -q '^#!/usr/bin/env bash$' && ok "shebang" || bad "shebang salah"

step "2. bash -n (parse)"
bash -n "$f" && ok "syntax valid" || bad "syntax rusak"

step "3. bash -u -o pipefail dry parse"
bash -u -o pipefail -n "$f" && ok "strict parse" || bad "strict parse gagal"

step "4. shellcheck (strict)"
if command -v shellcheck >/dev/null 2>&1; then
	shellcheck -S style -o all -x "$f" && ok "shellcheck clean" || bad "shellcheck ada temuan"
else
	printf '  [skip] shellcheck belum diinstall\n'
fi

step "5. deteksi pola bahaya"
grep -nE '\brm[[:space:]]+-rf[[:space:]]+[^"$]' "$f" && bad "rm -rf tanpa quote" || ok "rm -rf quoted"
grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^A-Za-z0-9_}"'\''[:space:]]' "$f" | grep -vE 'BASH_|SECONDS|RANDOM|LINENO|FUNCNAME' >/dev/null && bad "variabel tanpa quote" || ok "no unquoted vars (kasar)"
grep -nE '\[ ' "$f" >/dev/null && printf '  [info] ada "[ ... ]" (bisa ganti [[ ... ]])\n'

step "6. requires"
for c in mandoc awk sed sort find mktemp date sha512sum shasum; do
	command -v "$c" >/dev/null 2>&1 && ok "ada: $c" || printf '  [info] tidak ada di sini: %s\n' "$c"
done

step "7. cek config wajib"
grep -qE '^SITE_URL=' "$f" && ok "SITE_URL diset" || bad "SITE_URL hilang"
grep -qE 'set -Eeuo pipefail' "$f" && ok "strict mode" || bad "strict mode hilang"
grep -qE 'trap on_err ERR'  "$f" && ok "trap ERR"    || bad "trap ERR hilang"

printf '\nhasil: %d masalah\n' "$fails"
exit "$fails"
