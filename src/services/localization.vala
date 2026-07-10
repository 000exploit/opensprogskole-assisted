/* localization.vala
 *
 * Copyright 2026 000exploit
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Opensprogskole {

    /* Forcing the app's UI language independently of the system locale.
     *
     * gettext consults the LANGUAGE environment variable ahead of LC_MESSAGES, so
     * pinning a language is simply setting LANGUAGE before the first string is
     * translated — which is why apply() runs at startup, before any UI exists
     * (see main.vala). GTK/libadwaita build already-realized widgets' strings
     * once, so a change only fully lands on the next launch.
     *
     * This is the same mechanism that will later force the school's own language
     * (e.g. UMS's LanguageID from the auth JSON): resolve it to a code and call
     * apply(). "" always means "follow the system". */
    namespace Localization {

        /* Force `code` (e.g. "da") as the UI language for this process. Empty =
         * follow the system (no-op). Best effort: glibc consults LANGUAGE only
         * when LC_MESSAGES resolves to a real (non-C) locale, so when the
         * session runs under C/C.UTF-8/POSIX we also point LC_MESSAGES at a
         * real locale — set in the environment, not via setlocale(), because
         * gtk_init's later setlocale(LC_ALL, "") re-reads the environment and
         * would wipe anything set directly. */
        public void apply (string code) {
            if (code == "") {
                return;
            }
            GLib.Environment.set_variable ("LANGUAGE", code, true);

            if (!is_c_locale (effective_messages_locale ())) {
                return;
            }

            var candidate = find_real_locale (code);
            if (candidate == null) {
                // No real locale on this system at all; LANGUAGE alone still
                // works wherever LC_MESSAGES is non-C (e.g. Android's libintl).
                return;
            }

            // A C-ish LC_ALL would override LC_MESSAGES; demote it to LANG
            // (the default for every category) so the per-category var wins.
            var lc_all = GLib.Environment.get_variable ("LC_ALL");
            if (lc_all != null && lc_all != "") {
                GLib.Environment.unset_variable ("LC_ALL");
                GLib.Environment.set_variable ("LANG", lc_all, true);
            }
            GLib.Environment.set_variable ("LC_MESSAGES", candidate, true);
        }

        /* The messages locale gtk_init's setlocale(LC_ALL, "") will resolve
         * to, per POSIX env precedence. apply() runs before any setlocale, so
         * the environment is the only truthful source at that point. */
        private string effective_messages_locale () {
            string[] names = { "LC_ALL", "LC_MESSAGES", "LANG" };
            foreach (unowned string name in names) {
                var value = GLib.Environment.get_variable (name);
                if (value != null && value != "") {
                    return value;
                }
            }
            return "C";
        }

        private bool is_c_locale (string name) {
            return name == "C" || name == "POSIX" || name.has_prefix ("C.");
        }

        /* A locale the C library actually has, preferring the pinned
         * language's own (so %A/%B dates follow it too), then any other known
         * one — for unblocking LANGUAGE, any non-C locale will do. Probes with
         * setlocale() and restores the "C" state gtk_init expects. */
        private string? find_real_locale (string code) {
            string[] candidates = {};
            foreach (unowned string c in locale_candidates (code)) {
                candidates += c;
            }
            foreach (unowned string other in available ()) {
                if (other == code) {
                    continue;
                }
                foreach (unowned string c in locale_candidates (other)) {
                    candidates += c;
                }
            }

            foreach (unowned string candidate in candidates) {
                if (Intl.setlocale (LocaleCategory.MESSAGES, candidate) != null) {
                    Intl.setlocale (LocaleCategory.MESSAGES, "C");
                    return candidate;
                }
            }
            return null;
        }

        /* Likely locale names for a language code, best first. glibc
         * normalizes the codeset, so "UTF-8" also matches "utf8" locales. */
        private string[] locale_candidates (string code) {
            switch (code) {
                case "en": return { "en_US.UTF-8", "en_GB.UTF-8" };
                case "da": return { "da_DK.UTF-8" };
                case "ru": return { "ru_RU.UTF-8" };
                case "uk": return { "uk_UA.UTF-8" };
                default:   return { code + ".UTF-8", code };
            }
        }

        /* The selectable UI languages: the always-present source language
         * (English, which needs no catalog) plus every language with a compiled
         * catalog installed for our textdomain. Scans the install locale dir;
         * running uninstalled (no catalogs) yields just English. Never empty. */
        public string[] available () {
            string[] codes = { "en" };
            try {
                var dir = GLib.Dir.open (Config.LOCALEDIR);
                string? name;
                while ((name = dir.read_name ()) != null) {
                    var mo = GLib.Path.build_filename (Config.LOCALEDIR, name,
                        "LC_MESSAGES", Config.GETTEXT_PACKAGE + ".mo");
                    if (GLib.FileUtils.test (mo, GLib.FileTest.EXISTS)) {
                        codes += name;
                    }
                }
            } catch (GLib.Error e) {
                // No locale dir (uninstalled build) → English only.
            }
            return codes;
        }

        /* A language's endonym (its own name), for the picker. Deliberately not
         * translated — each option reads in its own language, as is conventional.
         * Falls back to the raw code for anything unmapped. */
        public string display_name (string code) {
            switch (code) {
                case "en": return "English";
                case "da": return "Dansk";
                case "ru": return "Русский";
                case "uk": return "Українська";
                default:   return code;
            }
        }
    }
}
