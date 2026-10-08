#!/usr/bin/env bash
# Transitional: run tools/check-book.py and the Odin checker on the same damaged copies of
# the generated book and compare what they report. Delete this file together with
# tools/check-book.py once the Odin checker has been the only one in CI for a release.
#
# Usage: tools/check-book/compare.sh [path-to-odin-binary]
#   PYTHON=...   the interpreter with PyYAML (default: .venv/bin/python in the repo)
#
# Exit status: 0 if every scenario agrees, 1 if any differs.
set -u

repo=$(cd "$(dirname "$0")/../.." && pwd)
odin_bin=${1:-/tmp/check-book-odin}
python=${PYTHON:-$repo/.venv/bin/python}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
book=$work/book
differences=0

# A fresh copy of what both tools read. The Python copy is patched to print every problem,
# not the first 50, so that the two reports can be compared as sets.
fresh() {
    rm -rf "$book"
    mkdir -p "$book/tools" "$book/docs"
    cp -r "$repo/html" "$book/html"
    cp -r "$repo/docs/assets" "$book/docs/assets"
    cp "$repo/mkdocs.yml" "$book/mkdocs.yml"
    cp "$repo/tools/legacy-anchors.json" "$book/tools/legacy-anchors.json"
    sed 's/errors\[:50\]/errors/' "$repo/tools/check-book.py" >"$book/tools/check-book.py"
}

html_edit() { # html_edit SED-EXPRESSION: edit every generated page
    find "$book/html" -name '*.html' -exec sed -i -E "$1" {} +
}

append_to() { # append_to PAGE TEXT: add markup to the end of one page
    printf '%s\n' "$2" >>"$book/html/$1"
}

# What the two tools reported, normalised to one problem per line. The Python tool reports
# problems as the text of an AssertionError and anything else as a crash.
python_report() {
    local out status
    out=$(cd "$book" && "$python" tools/check-book.py 2>&1)
    status=$?
    python_status=$status
    if [ $status -eq 0 ]; then
        python_problems=""
    elif grep -q '^AssertionError: ' <<<"$out"; then
        python_problems=$(sed -n '/^AssertionError: /,$p' <<<"$out" | sed 's/^AssertionError: //' | sort)
    else
        python_problems="(crash: $(tail -n 1 <<<"$out"))"
    fi
}

odin_report() {
    local out status
    out=$("$odin_bin" --root "$book" --all 2>&1 >/dev/null)
    status=$?
    odin_status=$status
    # The XML package also prints "file(line:col) message" itself; our own lines carry the path.
    odin_problems=$(grep -vE '^[^ ]+\([0-9]+:[0-9]+\) ' <<<"$out" | sort)
    [ $status -eq 0 ] && odin_problems=""
}

# compare NAME [status-only]: run both tools on the current copy and compare.
compare() {
    local name=$1 mode=${2:-sets}
    python_report
    odin_report
    local verdict_python=$((python_status == 0 ? 0 : 1)) verdict_odin=$((odin_status == 0 ? 0 : 1))
    local count
    count=$(grep -c . <<<"$odin_problems")
    if [ "$verdict_python" -ne "$verdict_odin" ]; then
        echo "DIFFERENT  $name: python exit $python_status, odin exit $odin_status"
        differences=$((differences + 1))
    elif [ "$mode" = status-only ] || [ "$python_problems" = "$odin_problems" ]; then
        echo "same       $name ($count problems$([ "$mode" = status-only ] && echo ", verdict only"))"
    else
        echo "DIFFERENT  $name: the problem lists differ (only-python < / only-odin >, first 8):"
        diff <(echo "$python_problems") <(echo "$odin_problems") | head -8 | sed 's/^/             /'
        differences=$((differences + 1))
    fi
}

scenario() { # scenario NAME [status-only] -- uses the function named mutate_NAME
    fresh
    "mutate_$1"
    compare "$@"
}

mutate_untouched() { :; }
mutate_every_local_link_broken() { html_edit 's/(href|src)="([^":#?]+)"/\1="\2-broken"/g'; }
mutate_every_anchor_broken() { html_edit 's/(href="[^"#:]*)#([^"]*)"/\1#\2-broken"/g'; }
mutate_every_id_renamed() { html_edit 's/ id="([^"]*)"/ id="\1-r"/g'; }
mutate_single_quoted_attributes() { html_edit "s/href=\"([^\"']*)\"/href='\\1'/g"; }
mutate_unquoted_attributes() { html_edit 's/href="([^" >]*)"/href=\1/g'; }
mutate_upper_case_tags_and_attributes() { html_edit 's/<a /<A /g; s/ href=/ HREF=/g; s/ id=/ ID=/g'; }
mutate_chapter_13b() { sed -i -E 's/(<h2[^>]*>)13a\./\113b./' "$book/html/chapters/cli-linux.html"; }
mutate_chapter_missing() { sed -i -E 's/(<h2[^>]*>)5\. /\1/' "$book/html/chapters/cli-linux.html"; }
mutate_chapter_duplicated() { sed -i -E 's/(<h2[^>]*>)6\. /\15. /' "$book/html/chapters/cli-linux.html"; }
mutate_legacy_anchor_gone() { sed -i 's/"how-to-read"/"how-to-read-gone"/' "$book/tools/legacy-anchors.json"; }
mutate_legacy_page_gone() { sed -i 's#"index.html"#"nowhere.html"#' "$book/tools/legacy-anchors.json"; }
mutate_svg_truncated() { head -c 80 "$(find "$book/docs/assets" -name '*.svg' | sort | head -n 1)" >"$work/svg" && cp "$work/svg" "$(find "$book/docs/assets" -name '*.svg' | sort | head -n 1)"; }
mutate_page_truncated() { head -c 3000 "$book/html/index.html" >"$work/page" && cp "$work/page" "$book/html/index.html"; }
mutate_no_pages() { find "$book/html" -name '*.html' -delete; }

mutate_outside_the_reader() {
    append_to index.html '<a href="../../x.html">up</a><a href="/abs.html">abs</a><a href="chapters/../../../etc/passwd">dots</a>'
}

mutate_tricky_markup() {
    append_to index.html "<a href='chapters/cli-linux.html#cli-contract'>single</a>
<a href=chapters/nope.html>unquoted</a>
<A HREF=\"chapters/cli%2Dlinux.html\">percent</A>
<a href=\"chapters/cli-linux.html?x=1#streams\">query</a>
<a href=\"x&amp;y.html\">entity</a>
<img src=\"assets/none.png\"/>
<link href=\"nofile.css\">
<a href=\"mailto:x@y.z\">m</a><a href=\"//cdn.example.org/x\">c</a><a href=\"chapters/\">dir</a>
<a href=\"chapters/cli-linux.html#no%20such\">encoded anchor</a>
<a href=\"#no-such-self\">self</a>
<a href=\"chapters/cli-linux.html#CLI-CONTRACT\">case</a>"
}

mutate_hidden_markup() {
    append_to index.html "<script>var a = '<a href=\"in-script.html\">';</script>
<style>/* <a href='in-style.html'> */</style>
<!-- <a href=\"in-comment.html\"> -->
<![CDATA[ <a href=\"in-cdata.html\"> ]]>
<SCRIPT>x = \"</scrip\" + \"t>\";</SCRIPT>
<p>a < b <a href=\"after-less-than.html\">x</a></p>"
}

mutate_the_404_page() {
    append_to 404.html '<a href="/odin-in-practice/nope.html">gone</a><a href="/odin-in-practice/index.html#nope">anchor</a><a href="/elsewhere/x.html">outside</a><a href="index.html">relative</a>'
}

mutate_a_404_page_in_a_subdirectory() {
    printf '<a href="/odin-in-practice/index.html">ok</a><a href="/odin-in-practice/nope.html">gone</a>' >"$book/html/chapters/404.html"
}

if [ ! -x "$odin_bin" ]; then
    echo "no Odin checker at $odin_bin: build it with 'odin build tools/check-book -out:$odin_bin'" >&2
    exit 2
fi

scenario untouched
scenario every_local_link_broken
scenario every_anchor_broken
scenario every_id_renamed
scenario single_quoted_attributes
scenario unquoted_attributes
scenario upper_case_tags_and_attributes
scenario chapter_13b
scenario chapter_missing
scenario chapter_duplicated
scenario legacy_anchor_gone
scenario legacy_page_gone
scenario svg_truncated status-only
scenario page_truncated
scenario no_pages status-only
scenario outside_the_reader
scenario tricky_markup
scenario hidden_markup
scenario the_404_page
scenario a_404_page_in_a_subdirectory

if [ $differences -eq 0 ]; then
    echo "All scenarios agree."
    exit 0
fi
echo "$differences scenario(s) differ."
exit 1
