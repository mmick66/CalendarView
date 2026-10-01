#!/bin/sh
# Flags `open` declarations that have no documentation comment.
#
# swift-format's AllPublicDeclarationsHaveDocumentation checks only `public` declarations, so an
# undocumented `open` class or member passes `swift-format lint`. This covers the gap with the
# same rule: overrides are exempt (they inherit their documentation), and the comment (`///` or
# `/** */`) must sit directly above the declaration or its attribute lines.
#
# Usage: scripts/lint-open-documentation.sh [path ...]   (default: Sources)

set -eu

[ $# -gt 0 ] || set -- Sources

find "$@" -name '*.swift' -type f -print0 | xargs -0 awk '
FNR == 1 { documented = 0; inDocBlock = 0; inBlock = 0 }

# Attribute lines between the comment and the declaration keep what came before them.
/^[ \t]*(@[A-Za-z_][A-Za-z0-9_.]*(\([^)]*\))?[ \t]*)+$/ && !inBlock { next }

{
    line = $0
    isDocumentation = 0
    if (inBlock) {
        if (line ~ /\*\//) { inBlock = 0; isDocumentation = inDocBlock }
    } else if (line ~ /^[ \t]*\/\/\//) {
        isDocumentation = 1
    } else if (line ~ /^[ \t]*\/\*/) {
        inDocBlock = (line ~ /^[ \t]*\/\*\*/)
        if (line ~ /\*\/[ \t]*$/) { isDocumentation = inDocBlock } else { inBlock = 1 }
    } else if (line ~ /^[ \t]*((@[A-Za-z_][A-Za-z0-9_]*(\([^)]*\))?|nonisolated|final|required|convenience|dynamic|static|class|override)[ \t]+)*open[ \t]/ \
               && line !~ /^[ \t]*([^ \t]+[ \t]+)*override[ \t]/ && !documented) {
        name = line
        sub(/^[ \t]+/, "", name)
        column = length(line) - length(name) + 1
        printf "%s:%d:%d: error: [OpenDeclarationsHaveDocumentation] add a documentation comment for: %s\n", \
            FILENAME, FNR, column, name
        failed = 1
    }
    if (!inBlock) documented = isDocumentation
}

END { exit failed }
'
