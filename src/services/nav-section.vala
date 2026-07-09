/* nav-section.vala
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

    /* Where a section sits in the wide sidebar: the primary list up top, or the
     * "More" list below. (The narrow bottom bar only takes PRIMARY.) */
    public enum NavPlacement {
        PRIMARY, SECONDARY
    }

    /* One entry in the shell's navigation config — the single source of truth
     * for *which* sections exist and in what order, shared by both nav controls
     * (the wide sidebar and the narrow bottom bar). It's deliberately separate
     * from the Adw.ViewStack, which stays the source of truth for *what is
     * currently shown*.
     *
     * `tag` is the navigate() target: a core section switches the ViewStack, a
     * secondary one pushes onto the content NavigationView (see MainView).
     * `capability` gates the section behind SchoolProvider.supports() so a school
     * only offers sections it can actually fill; ALWAYS means it's always shown
     * (Overview, and locally-served sections like Homework). `pinned` sections
     * (Overview + Profile) are always present and — once customization lands —
     * never removable. */
    public class NavSection : GLib.Object {

        // Sentinel for "no capability gate" — a nullable enum is awkward in Vala,
        // so an out-of-band value reads clearer and allocates nothing.
        public const DataKind ALWAYS = (DataKind) (-1);

        public string tag { get; construct; }
        public string title { get; construct; }
        // A compact label for the space-constrained bottom bar (e.g. "You" vs the
        // sidebar's "Your information"). Defaults to `title`.
        public string short_title { get; construct; }
        public string icon_name { get; construct; }
        public NavPlacement placement { get; construct; }
        public bool pinned { get; construct; }
        public DataKind capability { get; construct; }

        public NavSection (string tag, string title, string icon_name,
                           NavPlacement placement, bool pinned, DataKind capability,
                           string? short_title = null) {
            Object (tag: tag, title: title, icon_name: icon_name,
                    placement: placement, pinned: pinned, capability: capability,
                    short_title: short_title ?? title);
        }

        /* Whether this section should appear for the given provider: pinned and
         * always-available sections pass unconditionally; the rest defer to the
         * backend's supports(). */
        public bool available_for (SchoolProvider provider) {
            return pinned || capability == ALWAYS || provider.supports (capability);
        }

        /* The shell's full section list, in display order — the single catalog
         * both nav controls (sidebar + bottom bar) are built from. Kept in the
         * same order/icons as the .blp ViewStack so nothing shifts on UMS. Filter
         * it per-provider with available_for(). */
        public static NavSection[] catalog () {
            return {
                new NavSection ("overview", _("Overview"), "view-grid-symbolic",
                                NavPlacement.PRIMARY, true, ALWAYS),
                new NavSection ("schedule", _("Schedule"), "x-office-calendar-symbolic",
                                NavPlacement.PRIMARY, false, DataKind.TIMETABLE),
                new NavSection ("grades", _("Grades"), "starred-symbolic",
                                NavPlacement.PRIMARY, false, DataKind.GRADES),
                new NavSection ("absence", _("Absence"), "appointment-soon-symbolic",
                                NavPlacement.PRIMARY, false, DataKind.ABSENCE),
                new NavSection ("profile", _("Your information"), "avatar-default-symbolic",
                                NavPlacement.PRIMARY, true, DataKind.PROFILE, _("You")),
                new NavSection ("news", _("News"), "application-rss+xml-symbolic",
                                NavPlacement.SECONDARY, false, DataKind.NEWS),
                new NavSection ("homework", _("Homework"), "folder-documents-symbolic",
                                NavPlacement.SECONDARY, false, DataKind.HOMEWORK),
                new NavSection ("links", _("Links"), "web-browser-symbolic",
                                NavPlacement.SECONDARY, false, DataKind.LINKS),
            };
        }
    }
}
