#!/usr/bin/env bash
# Debug: DEBUG=1 ./build.sh    (verbose, tampilkan semua command)
set -Eeuo pipefail
IFS=$'\n\t'

# --- Debug scaffolding ----------------------------------------------------
DEBUG="${DEBUG:-0}"
[ "$DEBUG" = 1 ] && set -x

log()  { printf '  %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

on_err() {
	local rc=$? cmd="$BASH_COMMAND" line="${BASH_LINENO[0]}" src="${BASH_SOURCE[1]:-build.sh}"
	printf '\nFATAL: rc=%s\n  di   : %s:%s\n  cmd  : %s\n' \
		"$rc" "$src" "$line" "$cmd" >&2
	exit "$rc"
}
trap on_err ERR

POSTS_DIR="posts"
OUT_DIR="public"
CSS_SRC="man.css"
CSS_DST="man.css"
INDEX_TITLE="man.blog"
SITE_URL="https://mroczect.biz.id/man.blog"
SITE_DESC="Personal blog in man page format"
SORT_BY="datetime"
STRIP_NUMERIC_PREFIX=true
ENABLE_FEED=true
HASH_LEN=128

FAVICON_SRC="assets/favicon.png"

declare -A FOLDER_LABELS=(
	[database]="Database"
	[matematika]="Matematika"
	[sistem]="Sistem"
	[jaringan]="Jaringan"
)
DEFAULT_LABEL="Lain-lain"

case "$SORT_BY" in
	datetime|name) ;;
	*) die "SORT_BY=\"$SORT_BY\" tidak dikenal (pakai: datetime|name)" ;;
esac
[[ "$HASH_LEN" =~ ^[0-9]+$ ]] || die "HASH_LEN harus angka, dapat: $HASH_LEN"
case "$STRIP_NUMERIC_PREFIX" in true|false) ;; *) die "STRIP_NUMERIC_PREFIX harus true|false" ;; esac
case "$ENABLE_FEED"        in true|false) ;; *) die "ENABLE_FEED harus true|false" ;; esac
[ -d "$POSTS_DIR" ] || die "folder \"$POSTS_DIR/\" tidak ada"
[ -f "$CSS_SRC" ]   || die "file \"$CSS_SRC\" tidak ada"

if [ -n "$SITE_URL" ]; then
	BASE_PATH=$(printf '%s' "$SITE_URL" | sed -E 's|^https?://[^/]+||; s|/$||')
	FAVICON="${BASE_PATH}/${FAVICON_SRC}"
	FAVICON="${FAVICON:-/}"
else
	FAVICON="/${FAVICON_SRC}"
	warn "SITE_URL kosong, favicon pakai \"$FAVICON\" (mungkin salah kalau di subpath)"
fi

log "config: SITE_URL=$SITE_URL"
log "config: FAVICON=$FAVICON"
log "config: OUT_DIR=$OUT_DIR POSTS_DIR=$POSTS_DIR"

need=(mandoc awk sed sort find mktemp)
[ "$ENABLE_FEED" = true ] && need+=(date)

if   command -v sha512sum >/dev/null 2>&1; then HASH_CMD="sha512sum"
elif command -v shasum    >/dev/null 2>&1; then HASH_CMD="shasum -a 256"
else die "butuh sha512sum atau shasum"
fi

for cmd in "${need[@]}"; do
	command -v "$cmd" >/dev/null 2>&1 || die "butuh \"$cmd\""
done
log "deps: ${need[*]} + $HASH_CMD"

extract_field() {
	awk -v f=".$2" '$1 == f { $1 = ""; sub(/^ /, ""); print; exit }' "$1"
}

normalize_datetime() {
	local d="$1"
	if [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
		printf '%s' "$d"; return
	fi
	if [[ "$d" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})[T\ ]([0-9]{2}):([0-9]{2})(:([0-9]{2}))?$ ]]; then
		printf '%sT%s:%s:%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" \
			"${BASH_REMATCH[3]}" "${BASH_REMATCH[5]:-00}"
		return
	fi
	local iso
	iso=$(date -d "$d" +%Y-%m-%dT%H:%M:%S 2>/dev/null) || iso=""
	[ -n "$iso" ] || iso=$(date -d "$d" +%Y-%m-%d 2>/dev/null) || iso="$d"
	printf '%s' "$iso"
}

display_date() {
	local iso="$1"
	if [[ "$iso" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2}:[0-9]{2}) ]]; then
		printf '%s %s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
	else
		printf '%s' "$iso"
	fi
}

rel_prefix() {
	local dir="$1"
	[ -z "$dir" ] && return
	local n
	n=$(awk -F/ '{print NF}' <<<"$dir")
	printf '../%.0s' $(seq 1 "$n")
}

output_name() {
	local name="$1"
	if [ "$STRIP_NUMERIC_PREFIX" = true ]; then
		printf '%s' "${name#[0-9][0-9]-}"
	else
		printf '%s' "$name"
	fi
}

folder_label() {
	local dir="$1"
	[ -z "$dir" ] && { printf '%s' "$DEFAULT_LABEL"; return; }
	local key="${dir%%/*}"
	printf '%s' "${FOLDER_LABELS[$key]:-$key}"
}

top_dir() { printf '%s' "${1%%/*}"; }

html_escape() {
	sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

hash_file() {
	local f="$1"
	$HASH_CMD "$f" | awk -v n="$HASH_LEN" '{print substr($1,1,n)}'
}

mkdir -p "$OUT_DIR"
find "$OUT_DIR" -type f \( -name '*.html' -o -name '*.xml' \) -delete
rm -f  "$OUT_DIR/$CSS_DST"
rm -rf "$OUT_DIR/assets"
find "$OUT_DIR" -mindepth 1 -type d -empty -delete

cp "$CSS_SRC" "$OUT_DIR/$CSS_DST"
log "copy: $CSS_SRC -> $OUT_DIR/$CSS_DST"

if [ -f "$FAVICON_SRC" ]; then
	mkdir -p "$OUT_DIR/$(dirname "$FAVICON_SRC")"
	cp "$FAVICON_SRC" "$OUT_DIR/$FAVICON_SRC"
	log "copy: $FAVICON_SRC -> $OUT_DIR/$FAVICON_SRC"
else
	warn "favicon \"$FAVICON_SRC\" tidak ada, dilewati"
fi

touch "$OUT_DIR/.nojekyll"

CSS_HASH=$(hash_file "$CSS_SRC")
log "css hash: ${CSS_HASH:0:16}..."

tmp=$(mktemp -t blog.XXXXXX)
trap 'rm -f "$tmp"' EXIT
log "tmp: $tmp"

shopt -s nullglob globstar
for file in "$POSTS_DIR"/**/*.1; do
	rel="${file#$POSTS_DIR/}"
	dir=$(dirname "$rel"); [ "$dir" = "." ] && dir=""
	base=$(basename "$rel" .1)
	out=$(output_name "$base")
	title=$(extract_field "$file" Dt); title=${title%% *}
	date=$(extract_field "$file" Dd)
	iso=$(normalize_datetime "$date")
	fhash=$(hash_file "$file")
	printf '%s|%s|%s|%s|%s|%s|%s\n' \
		"$rel" "$dir" "$base" "$out" "$iso" "${title:-$base}" "$fhash" >> "$tmp"
done
shopt -u nullglob globstar

[ -s "$tmp" ] || warn "nggak ada file .1 di $POSTS_DIR/"

case "$SORT_BY" in
	datetime) sort -t'|' -k5,5r -k1,1 "$tmp" -o "$tmp" ;;
	name)     sort -t'|' -k1,1  "$tmp" -o "$tmp" ;;
esac

count=0
while IFS='|' read -r rel dir base out iso title fhash; do
	[ -n "$rel" ] || continue

	target_dir="$OUT_DIR${dir:+/$dir}"
	mkdir -p "$target_dir"
	target="$target_dir/${out}.html"

	log "build: $rel"

	mandoc -Thtml -O style="$CSS_DST" "$POSTS_DIR/$rel" > "$target"

	prefix=""
	[ -n "$dir" ] && prefix=$(rel_prefix "$dir")

	if [ -n "$dir" ]; then
		sed -i "s|href=\"$CSS_DST\"|href=\"${prefix}$CSS_DST\"|g" "$target"
	fi
	sed -i "s|href=\"\(${prefix}\)$CSS_DST\"|href=\"\1$CSS_DST?v=$CSS_HASH\"|g" "$target"

	build_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
	awk -v h="$fhash" -v ts="$build_ts" -v src="$rel" -v ico="$FAVICON" '
		!done && (/<\/head>/ || /<body/) {
			printf "<link rel=\"icon\" type=\"image/png\" href=\"%s\">\n", ico
			printf "<link rel=\"apple-touch-icon\" href=\"%s\">\n", ico
			printf "<meta name=\"post-hash\" content=\"%s\">\n", h
			printf "<meta name=\"post-source\" content=\"%s\">\n", src
			printf "<meta name=\"build-time\" content=\"%s\">\n", ts
			done = 1
		}
		{ print }
	' "$target" > "$target.tmp" && mv "$target.tmp" "$target"

	count=$((count + 1))
done < "$tmp"

log "build: index"
{
	printf '<!DOCTYPE html>\n<html lang="id">\n<head>\n'
	printf '<meta charset="utf-8">\n'
	printf '<meta name="viewport" content="width=device-width,initial-scale=1">\n'
	printf '<title>%s</title>\n' "$INDEX_TITLE"
	printf '<link rel="stylesheet" href="%s?v=%s">\n' "$CSS_DST" "$CSS_HASH"
	printf '<link rel="icon" type="image/png" href="%s">\n' "$FAVICON"
	printf '<link rel="apple-touch-icon" href="%s">\n' "$FAVICON"
	printf '</head>\n<body>\n'
	printf '<h1>%s</h1>\n' "$INDEX_TITLE"

	last_top="__none__"
	while IFS='|' read -r rel dir base out iso title fhash; do
		[ -n "$rel" ] || continue

		top=$(top_dir "$dir")
		if [ "$top" != "$last_top" ]; then
			[ "$last_top" != "__none__" ] && printf '</ul>\n'
			printf '<h2>%s</h2>\n<ul class="index-list">\n' "$(folder_label "$dir")"
			last_top="$top"
		fi

		link="${dir:+$dir/}${out}.html"
		disp=$(display_date "$iso")
		printf '<li><a href="%s"><span class="idx-date">%s</span><span class="idx-title">%s</span></a></li>\n' \
			"$link" "$disp" "$(printf '%s' "$title" | html_escape)"
	done < "$tmp"

	[ "$last_top" != "__none__" ] && printf '</ul>\n'
	printf '</body>\n</html>\n'
} > "$OUT_DIR/index.html"

if [ "$ENABLE_FEED" = true ]; then
	log "build: feed.xml"

	build_date=$(date -R 2>/dev/null || date +"%a, %d %b %Y %H:%M:%S %z")
	site="${SITE_URL%/}"
	guid_ns=$([ "${HASH_CMD%% *}" = "sha512sum" ] && echo sha512 || echo sha256)

	{
		printf '<?xml version="1.0" encoding="UTF-8"?>\n'
		printf '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">\n'
		printf '<channel>\n'
		printf '  <title>%s</title>\n' "$(printf '%s' "$INDEX_TITLE" | html_escape)"
		printf '  <description>%s</description>\n' "$(printf '%s' "$SITE_DESC" | html_escape)"
		if [ -n "$site" ]; then
			printf '  <link>%s/</link>\n' "$site"
			printf '  <atom:link href="%s/feed.xml" rel="self" type="application/rss+xml"/>\n' "$site"
		fi
		printf '  <lastBuildDate>%s</lastBuildDate>\n' "$build_date"

		while IFS='|' read -r rel dir base out iso title fhash; do
			[ -n "$rel" ] || continue

			pub="$build_date"
			if [ -n "$iso" ] && [ "$iso" != "?" ]; then
				c=$(date -d "$iso" -R 2>/dev/null) && pub="$c"
			fi

			link="${site}/${dir:+$dir/}${out}.html"
			guid="urn:${guid_ns}:${fhash}"
			printf '  <item>\n'
			printf '    <title>%s</title>\n' "$(printf '%s' "$title" | html_escape)"
			[ -n "$site" ] && printf '    <link>%s</link>\n' "$link"
			printf '    <guid isPermaLink="false">%s</guid>\n' "$guid"
			printf '    <pubDate>%s</pubDate>\n' "$pub"
			printf '  </item>\n'
		done < "$tmp"

		printf '</channel>\n'
		printf '</rss>\n'
	} > "$OUT_DIR/feed.xml"
fi

log "done: $count post -> $OUT_DIR/"
log "css hash: $CSS_HASH"
