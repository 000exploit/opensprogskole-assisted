#!/usr/bin/env python3
"""Install the compiled gettext catalogs under Meson's 'runtime' install tag.

Meson's i18n module hardcodes the 'i18n' tag on the .mo files it installs,
and pixiewood stages the Android APK with `meson install --tags runtime` —
which silently drops them, shipping an APK without translations. Run via
meson.add_install_script(..., install_tag: 'runtime') from po/meson.build.

Reads the catalogs from Meson's internal po/<lang>/LC_MESSAGES layout in the
build dir; if a Meson upgrade ever moves them, this fails loudly rather than
staging an untranslated APK.
"""
import os
import shutil
import sys

domain, localedir = sys.argv[1], sys.argv[2]
source_root = os.environ["MESON_SOURCE_ROOT"]
build_root = os.environ["MESON_BUILD_ROOT"]
prefix = os.environ["MESON_INSTALL_DESTDIR_PREFIX"]

with open(os.path.join(source_root, "po", "LINGUAS"), encoding="utf-8") as f:
    langs = [line.split("#", 1)[0].strip() for line in f]

for lang in filter(None, langs):
    mo = os.path.join(build_root, "po", lang, "LC_MESSAGES", domain + ".mo")
    dest_dir = os.path.join(prefix, localedir, lang, "LC_MESSAGES")
    dest = os.path.join(dest_dir, domain + ".mo")
    os.makedirs(dest_dir, exist_ok=True)
    shutil.copy2(mo, dest)
    print("Installing {} to {}".format(mo, dest_dir))
