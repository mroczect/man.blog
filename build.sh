#!/usr/bin/env bash
set -euo pipefail

# --- Config ---------------------------------------------------------------
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

# Favicon: file lokal + URL absolut (biar dari subdir tetap ketemu)
FAVICON_SRC="assets/favicon.png"
FAVICON="/${FAVICON_SRC}"              # -> /assets/favicon.png

declare -A FOLDER_LABELS=(
	[database]="Database"
	[matematika]="Matematika"
	[sistem]="Sistem"
	[jaringan]="Jaringan"
)
DEFAULT_LABEL="Lain-lain"

need=(mandoc awk sed sort find mktemp)
[ "$ENABLE_FEED" = true ] && need+=(date)
if command -v sha512sum >/dev/null 2>&1; then
	HASH_CMD="sha512sum"
elif command -v shasum >/dev/null 2>&1; then
	HASH_CMD="shasum -a 256"
else
	printf 'error: butuh sha512sum atau shasum\n' >&2
	exit 1
fi

for cmd in "${need[@]}"; do
	command -v "$cmd" >/dev/null 2>&1 || {
		printf 'error: butuh "%s"\n' "$cmd" >&2
		exit 1
	}
done

# --- Helpers --------------------------------------------------------------
extract_field() {
	awk -v f=".$2" '$1 == f { $1 = ""; sub(/^ /, ""); print; exit }' "$1"
}

normalize_datetime() {
	local d="$1"
	if [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
		printf '%s' "$d"; return
	fi
	if [[ "$d" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})[T\ ]([0-9]{2}):([0-9]{2})(:([0-9]{2}))?$ ]]; then
		local date="${BASH_REMATCH[1]}"
		local hh="${BASH_REMATCH[2]}"
		local mm="${BASH_REMATCH[3]}"
		local ss="${BASH_REMATCH[5]:-00}"
		printf '%sT%s:%s:%s' "$date" "$hh" "$mm" "$ss"
		return
	fi
	local iso
	iso=$(date -d "$d" +%Y-%m-%dT%H:%M:%S 2>/dev/null) || iso=""
	if [ -z "$iso" ]; then
		iso=$(date -d "$d" +%Y-%m-%d 2>/dev/null) || iso="$d"
	fi
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

hash_stdin() {
	$HASH_CMD | awk -v n="$HASH_LEN" '{print substr($1,1,n)}'
}

# --- Bersihkan output -----------------------------------------------------
mkdir -p "$OUT_DIR"
find "$OUT_DIR" -type f \( -name '*.html' -o -name '*.xml' \) -delete
rm -f "$OUT_DIR/$CSS_DST"
rm -rf "$OUT_DIR/assets"
find "$OUT_DIR" -mindepth 1 -type d -empty -delete

[ -f "$CSS_SRC" ] && cp "$CSS_SRC" "$OUT_DIR/$CSS_DST"

# Copy favicon ke public/ (dengan struktur folder yang sama)
if [ -f "$FAVICON_SRC" ]; then
	mkdir -p "$OUT_DIR/$(dirname "$FAVICON_SRC")"
	cp "$FAVICON_SRC" "$OUT_DIR/$FAVICON_SRC"
	printf '  assets  %s\n' "$FAVICON_SRC"
else
	printf 'warning: favicon "%s" tidak ada, favicon dilewati\n' "$FAVICON_SRC" >&2
fi

touch "$OUT_DIR/.nojekyll"

CSS_HASH=""
[ -f "$CSS_SRC" ] && CSS_HASH=$(hash_file "$CSS_SRC")

# --- Kumpulkan daftar post -----------------------------------------------
tmp=$(mktemp -t blog.XXXXXX)
trap 'rm -f "$tmp"' EXIT

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

if [ ! -s "$tmp" ]; then
	printf 'warning: nggak ada file .1 di %s/\n' "$POSTS_DIR" >&2
fi

case "$SORT_BY" in
	datetime) sort -t'|' -k5,5r -k1,1 "$tmp" -o "$tmp" ;;
	name)     sort -t'|' -k1,1  "$tmp" -o "$tmp" ;;
	*)        printf 'warning: SORT_BY="%s" nggak dikenal\n' "$SORT_BY" >&2
	          sort -t'|' -k5,5r -k1,1 "$tmp" -o "$tmp" ;;
esac

# --- Render tiap post -----------------------------------------------------
count=0
while IFS='|' read -r rel dir base out iso title fhash; do
	[ -n "$rel" ] || continue

	target_dir="$OUT_DIR${dir:+/$dir}"
	mkdir -p "$target_dir"
	target="$target_dir/${out}.html"

	printf '  build  %s  [%s]\n' "$rel" "$fhash"

	mandoc -Thtml -O style="$CSS_DST" "$POSTS_DIR/$rel" > "$target"

	prefix=""
	[ -n "$dir" ] && prefix=$(rel_prefix "$dir")

	if [ -n "$dir" ]; then
		sed -i "s|href=\"$CSS_DST\"|href=\"${prefix}$CSS_DST\"|g" "$target"
	fi
	if [ -n "$CSS_HASH" ]; then
		sed -i "s|href=\"\(${prefix}\)$CSS_DST\"|href=\"\1$CSS_DST?v=$CSS_HASH\"|g" "$target"
	fi

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

# --- Index ----------------------------------------------------------------
printf '  build  index\n'
{
	printf '<!DOCTYPE html>\n<html lang="id">\n<head>\n'
	printf '<meta charset="utf-8">\n'
	printf '<meta name="viewport" content="width=device-width,initial-scale=1">\n'
	printf '<title>%s</title>\n' "$INDEX_TITLE"
	if [ -n "$CSS_HASH" ]; then
		printf '<link rel="stylesheet" href="%s?v=%s">\n' "$CSS_DST" "$CSS_HASH"
	else
		printf '<link rel="stylesheet" href="%s">\n' "$CSS_DST"
	fi
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
			printf '<h2>%s</h2>\n<ul class="index-list">\n' \
				"$(folder_label "$dir")"
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

# --- Feed -----------------------------------------------------------------
if [ "$ENABLE_FEED" = true ]; then
	printf '  build  feed.xml\n'

	build_date=$(date -R 2>/dev/null || date +"%a, %d %b %Y %H:%M:%S %z")
	site="${SITE_URL%/}"

	{
		printf '<?xml version="1.0" encoding="UTF-8"?>\n'
		printf '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">\n'
		printf '<channel>\n'
		printf '  <title>%s</title>\n' "$(printf '%s' "$INDEX_TITLE" | html_escape)"
		printf '  <description>%s</description>\n' "$(printf '%s' "$SITE_DESC" | html_escape)"
		printf '  <link>%s/</link>\n' "$site"
		if [ -n "$site" ]; then
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
			guid="urn:sha256:${fhash}"
			printf '  <item>\n'
			printf '    <title>%s</title>\n' "$(printf '%s' "$title" | html_escape)"
			printf '    <link>%s</link>\n' "$link"
			printf '    <guid isPermaLink="false">%s</guid>\n' "$guid"
			printf '    <pubDate>%s</pubDate>\n' "$pub"
			printf '  </item>\n'
		done < "$tmp"

		printf '</channel>\n'
		printf '</rss>\n'
	} > "$OUT_DIR/feed.xml"
fi

printf 'done. %d post -> %s/\n' "$count" "$OUT_DIR"
[ -n "$CSS_HASH" ] && printf 'css hash: %s\n' "$CSS_HASH"
