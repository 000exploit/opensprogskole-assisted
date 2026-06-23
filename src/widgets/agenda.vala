/* agenda.vala
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

    /* The agenda view: every day in the store that has lessons, across all
     * months, listed under a date heading inside its own scroll area.
     *
     * Like the day panel it owns no data — each day's list is bound straight to
     * the ListStore the TimetableStore already prepared, so it shares the exact
     * objects the calendar/day panel use. It is rebuilt only when the store
     * changes.
     *
     * After a rebuild it scrolls to the nearest day on or after today, so the
     * user lands on what's coming up. If every lesson is in the past (e.g. the
     * course has ended) there is simply no such day and the scroll position is
     * left untouched. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/agenda.ui")]
    public class Agenda : Adw.Bin {

        [GtkChild]
        private unowned Gtk.ScrolledWindow scroller;
        [GtkChild]
        private unowned Gtk.Box content;

        /* Emitted when the user activates a lesson row. */
        public signal void lesson_activated (TimetableItem item);

        /* Heading widget of the nearest upcoming day, or null if there is none.
         * Used as the scroll anchor after a rebuild. */
        private Gtk.Widget? scroll_anchor = null;
        /* Whether we still owe a scroll-to-anchor once we are on screen. */
        private bool scroll_pending = false;

        construct {
            ensure_widget_styles (this);

            // We can only scroll once the agenda is mapped and laid out, which
            // is not the case while another stack page is showing.
            map.connect (() => {
                if (scroll_pending) {
                    scroll_to_anchor ();
                }
            });
        }

        /* Rebuild from every lesson day in the store. */
        public void set_all (TimetableStore store) {
            Gtk.Widget? child;
            while ((child = content.get_first_child ()) != null) {
                content.remove (child);
            }
            scroll_anchor = null;

            string today_key = new DateTime.now_local ().format ("%Y-%m-%d");

            foreach (string key in store.sorted_keys ()) {
                var model = store.get_day_for_key (key);
                if (model == null || model.get_n_items () == 0) {
                    continue;
                }

                var heading = new Gtk.Label (format_key (key)) {
                    halign = Gtk.Align.START
                };
                heading.add_css_class ("heading");
                content.append (heading);

                // The first day that is not in the past becomes the anchor.
                if (scroll_anchor == null && strcmp (key, today_key) >= 0) {
                    scroll_anchor = heading;
                }

                var list = new Gtk.ListBox () {
                    selection_mode = Gtk.SelectionMode.NONE
                };
                list.add_css_class ("boxed-list");
                list.bind_model (model, create_row);
                content.append (list);
            }

            if (content.get_first_child () == null) {
                var empty = new Gtk.Label (_("No lessons")) {
                    margin_top = 24
                };
                empty.add_css_class ("dim-label");
                content.append (empty);
            }

            // Scroll to the anchor; if there is none (all lessons are past),
            // leave the scroll position alone.
            scroll_pending = scroll_anchor != null;
            if (scroll_pending && get_mapped ()) {
                scroll_to_anchor ();
            }
        }

        private void scroll_to_anchor () {
            scroll_pending = false;
            var anchor = scroll_anchor;
            if (anchor == null) {
                return;
            }

            // Defer to an idle so the layout pass that follows mapping has run
            // and the anchor has a real position within the content.
            Idle.add (() => {
                Graphene.Rect bounds;
                if (anchor.compute_bounds (content, out bounds)) {
                    scroller.vadjustment.value = bounds.origin.y;
                }
                return Source.REMOVE;
            });
        }

        /* Same row shape as the day panel. */
        private Gtk.Widget create_row (GLib.Object object) {
            var lesson = (TimetableItem) object;

            var row = new Adw.ActionRow () {
                title = lesson.subject,
                subtitle = row_subtitle (lesson),
                activatable = true
            };

            var dot = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                valign = Gtk.Align.CENTER
            };
            bind_lesson_dot (dot, lesson);
            row.add_prefix (dot);

            var time = new Gtk.Label (lesson.time_range) {
                valign = Gtk.Align.CENTER
            };
            time.add_css_class ("numeric");
            time.add_css_class ("dim-label");
            row.add_suffix (time);

            row.activated.connect (() => lesson_activated (lesson));
            return row;
        }

        private static string row_subtitle (TimetableItem lesson) {
            var rooms = lesson.rooms;
            if (rooms.length > 0) {
                return _("Room %s").printf (string.joinv (", ", rooms));
            }
            return lesson.activity_code;
        }

        /* "2026-06-23" -> "Tuesday, 23 June 2026". */
        private static string format_key (string key) {
            int year = int.parse (key.substring (0, 4));
            int month = int.parse (key.substring (5, 2));
            int day = int.parse (key.substring (8, 2));
            var date = new DateTime.local (year, month, day, 0, 0, 0);
            return date.format ("%A, %-d %B %Y");
        }
    }
}
