/* lesson-dialog.vala
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

    /* A modal-ish detail sheet for a single lesson, presented with
     * present(parent). It reads everything it shows from the TimetableItem's
     * normalized getters (parsed date, room/teacher lists), so the messy JSON
     * never reaches the UI layer. The layout is intentionally not a 1:1 copy of
     * the mockup — it uses standard libadwaita rows and groups. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/lesson-dialog.ui")]
    public class LessonDialog : Adw.Dialog {

        [GtkChild]
        private unowned Gtk.Box content_box;

        public LessonDialog (TimetableItem item) {
            Object ();
            ensure_widget_styles (this);
            build (item);
        }

        private void build (TimetableItem item) {
            if (item.subject != "") {
                title = item.subject;
            }

            content_box.append (build_header (item));
            content_box.append (build_time_group (item));

            var rooms = item.rooms;
            if (rooms.length > 0) {
                content_box.append (build_rooms (rooms));
            }

            var teachers = item.teachers;
            if (teachers.length > 0) {
                content_box.append (build_list_group (_("Teachers"), teachers));
            }

            if (item.homework.strip () != "") {
                content_box.append (build_text_group (_("Homework"), item.homework));
            }
            if (item.comment.strip () != "") {
                content_box.append (build_text_group (_("Comment"), item.comment));
            }
        }

        private Gtk.Widget build_header (TimetableItem item) {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);

            var subject = new Gtk.Label (item.subject) {
                halign = Gtk.Align.START,
                xalign = 0,
                wrap = true
            };
            subject.add_css_class ("title-2");
            box.append (subject);

            if (item.activity_code != "") {
                var code = new Gtk.Label (item.activity_code) {
                    halign = Gtk.Align.START
                };
                code.add_css_class ("monospace");
                code.add_css_class ("dim-label");
                box.append (code);
            }

            return box;
        }

        private Gtk.Widget build_time_group (TimetableItem item) {
            var group = new Adw.PreferencesGroup ();

            var row = new Adw.ActionRow () {
                title = format_date (item),
                subtitle = item.time_range
            };
            var icon = new Gtk.Image.from_icon_name ("x-office-calendar-symbolic");
            row.add_prefix (icon);
            group.add (row);

            return group;
        }

        private Gtk.Widget build_rooms (string[] rooms) {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);

            var caption = new Gtk.Label (_("Rooms")) {
                halign = Gtk.Align.START
            };
            caption.add_css_class ("heading");
            box.append (caption);

            var flow = new Gtk.FlowBox () {
                selection_mode = Gtk.SelectionMode.NONE,
                column_spacing = 6,
                row_spacing = 6,
                homogeneous = false,
                max_children_per_line = 100
            };
            foreach (string room in rooms) {
                var chip = new Gtk.Label (room);
                chip.add_css_class ("room-chip");
                var child = new Gtk.FlowBoxChild () {
                    can_focus = false,
                    child = chip
                };
                flow.append (child);
            }
            box.append (flow);

            return box;
        }

        private Gtk.Widget build_list_group (string title, string[] entries) {
            var group = new Adw.PreferencesGroup () {
                title = title
            };
            foreach (string entry in entries) {
                group.add (new Adw.ActionRow () { title = entry });
            }
            return group;
        }

        private Gtk.Widget build_text_group (string title, string text) {
            var group = new Adw.PreferencesGroup () {
                title = title
            };
            var row = new Adw.ActionRow () {
                title = text.strip (),
                title_lines = 0
            };
            group.add (row);
            return group;
        }

        private static string format_date (TimetableItem item) {
            var dt = item.start_datetime;
            if (dt != null) {
                return dt.format ("%A, %-d %B %Y");
            }
            return item.date_key;
        }
    }
}
