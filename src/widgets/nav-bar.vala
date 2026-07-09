/* nav-bar.vala
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

    /* The narrow-layout bottom navigation bar — a hand-rolled stand-in for
     * Adw.ViewSwitcherBar, styled in style.css (.nav-bar). Unlike the built-in
     * switcher it isn't bound to a ViewStack: it renders whatever NavSections it's
     * handed and just emits section_activated on a tap, so the same shared section
     * list drives it and the wide sidebar. It's a dumb presenter — the shell owns
     * the catalog, the filtering, and what "activate" does (see MainView). */
    public class NavBar : Gtk.Box {

        /* A bar button was tapped; `tag` is the NavSection.tag to open. */
        public signal void section_activated (string tag);

        public NavBar () {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        }

        construct {
            homogeneous = true;
            add_css_class ("nav-bar");
        }

        /* Rebuild the bar from the given sections (already filtered/ordered by the
         * caller — typically the PRIMARY, provider-available ones). */
        public void set_sections (GLib.GenericArray<NavSection> sections) {
            Gtk.Widget? child;
            while ((child = get_first_child ()) != null) {
                remove (child);
            }
            for (uint i = 0; i < sections.length; i++) {
                append (make_button (sections[i]));
            }
        }

        /* Highlight the button for `tag` (the "selected" class), clearing the rest.
         * The tag rides on each button's widget name. */
        public void select (string tag) {
            for (var child = get_first_child (); child != null;
                 child = child.get_next_sibling ()) {
                if (child.name == tag) {
                    child.add_css_class ("selected");
                } else {
                    child.remove_css_class ("selected");
                }
            }
        }

        /* One bar item: a flat vertical icon-over-caption button that re-emits
         * section_activated. Uses the section's short_title (e.g. "You"), which
         * fits the bar better than the sidebar's longer label. */
        private Gtk.Button make_button (NavSection s) {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { valign = Gtk.Align.CENTER };
            box.append (new Gtk.Image.from_icon_name (s.icon_name));
            box.append (new Gtk.Label (s.short_title) {
                ellipsize = Pango.EllipsizeMode.END,
                single_line_mode = true
            });

            var button = new Gtk.Button () {
                child = box, hexpand = true, name = s.tag
            };
            button.add_css_class ("flat");
            button.clicked.connect (() => section_activated (s.tag));
            return button;
        }
    }
}
