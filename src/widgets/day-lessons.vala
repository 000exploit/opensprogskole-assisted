/* day-lessons.vala
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

    /* The "selected day" panel beside the calendar: a heading plus the day's
     * lessons, or an empty state.
     *
     * It owns no data. It is handed a GLib.ListModel of TimetableItem (the very
     * ListStore the TimetableStore prepared for that day) and binds to it; the
     * caller swaps models as the selected day changes. Activating a row emits
     * lesson_activated so the parent view can open the lesson dialog. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/day-lessons.ui")]
    public class DayLessons : Adw.Bin {

        [GtkChild]
        private unowned Gtk.Label title_label;
        [GtkChild]
        private unowned Gtk.ListBox list;
        [GtkChild]
        private unowned Gtk.Stack stack;

        /* Emitted when the user activates a lesson row. */
        public signal void lesson_activated (TimetableItem item);

        construct {
            ensure_widget_styles (this);
        }

        /* Show `model`'s lessons under `title`. Pass null/empty for a day with
         * no lessons. */
        public void bind (GLib.ListModel? model, string title) {
            title_label.label = title;
            list.bind_model (model, create_row);

            uint count = model != null ? model.get_n_items () : 0;
            stack.visible_child_name = count > 0 ? "list" : "empty";
        }

        /* Build the row widget for one lesson. Shared shape with the agenda. */
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
            dot.add_css_class ("lesson-dot");
            dot.add_css_class (lesson_dot_class (lesson.color));
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
    }
}
