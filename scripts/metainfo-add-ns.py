#!/usr/bin/env python3
# Injects the metainfo namespace into the built metainfo (argv[1] -> argv[2]).
#
# pixiewood requires xmlns="…/metainfo/1.0" on <component> (its XInclude and
# XSLT select the namespaced element), but a namespaced *source* breaks
# gettext's ITS matching — the selectors are namespace-less XPath — making
# xgettext extract and msgfmt translate every element (licenses, urls, hex
# colors...). So the source .in stays namespace-less for the i18n tooling,
# and the namespace is added here, after translation merging.
import sys

NS = "https://specifications.freedesktop.org/metainfo/1.0"
text = open(sys.argv[1], encoding="utf-8").read()
marker = "<component "
if f'xmlns="{NS}"' not in text:
    text = text.replace(marker, f'<component xmlns="{NS}" ', 1)
open(sys.argv[2], "w", encoding="utf-8").write(text)
