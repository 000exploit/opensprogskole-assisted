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
        private unowned Gtk.Box header_box;
        [GtkChild]
        private unowned Gtk.Label title_label;
        [GtkChild]
        private unowned Gtk.ListBox list;
        [GtkChild]
        private unowned Gtk.Stack stack;

        /* Compact edition (e.g. the overview's "Up next" card on mobile): drops
         * the "Selected day" header and the room/course subtitle, shows only the
         * start time and a single room — to take far less vertical space. The
         * coloured dot is kept in both modes (it doubles as the check-in
         * indicator). */
        public bool compact { get; set; default = false; }

        /* Emitted when the user activates a lesson row. */
        public signal void lesson_activated (TimetableItem item);

        // Kept so a compact-toggle can rebuild the rows for the new layout.
        private GLib.ListModel? current_model = null;

        construct {
            ensure_widget_styles (this);
            notify["compact"].connect (() => {
                header_box.visible = !compact;
                list.bind_model (current_model, create_row);
            });
        }

        /* Show `model`'s lessons under `title`. Pass null/empty for a day with
         * no lessons. */
        public void bind (GLib.ListModel? model, string title) {
            current_model = model;
            title_label.label = title;
            header_box.visible = !compact;
            list.bind_model (model, create_row);

            uint count = model != null ? model.get_n_items () : 0;
            stack.visible_child_name = count > 0 ? "list" : "empty";
        }

        /* Build the row widget for one lesson. Shared shape with the agenda. */
        private Gtk.Widget create_row (GLib.Object object) {
            var lesson = (TimetableItem) object;

            var row = new Adw.ActionRow () {
                title = lesson.subject,
                activatable = true
            };

            var dot = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                valign = Gtk.Align.CENTER
            };
            bind_lesson_dot (dot, lesson);
            row.add_prefix (dot);

            if (compact) {
                // [dot] [start] Subject .......... [room]
                row.title_lines = 1;

                var time = new Gtk.Label (lesson.start_time) {
                    valign = Gtk.Align.CENTER
                };
                time.add_css_class ("numeric");
                row.add_prefix (time);

                string rooms = compact_rooms (lesson);
                if (rooms != "") {
                    var room = new Gtk.Label (rooms) {
                        valign = Gtk.Align.CENTER
                    };
                    room.add_css_class ("dim-label");
                    row.add_suffix (room);
                    row.tooltip_text = string.joinv (", ", lesson.rooms);
                }
            } else {
                // [dot] Subject / rooms·code .......... [time range]
                row.subtitle = row_subtitle (lesson);

                var time = new Gtk.Label (lesson.time_range) {
                    valign = Gtk.Align.CENTER
                };
                time.add_css_class ("numeric");
                time.add_css_class ("dim-label");
                row.add_suffix (time);
            }

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

        /* One room verbatim; many rooms collapse to "first +N" (full list in the
         * row tooltip) so a busy day still fits a narrow row. */
        private static string compact_rooms (TimetableItem lesson) {
            var rooms = lesson.rooms;
            if (rooms.length == 0) {
                return "";
            }
            if (rooms.length == 1) {
                return rooms[0];
            }
            return "%s +%d".printf (rooms[0], rooms.length - 1);
        }
    }
}
