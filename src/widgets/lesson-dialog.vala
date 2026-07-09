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
        [GtkChild]
        private unowned Gtk.Label subject_label;
        [GtkChild]
        private unowned Gtk.Label activity_label;
        [GtkChild]
        private unowned Gtk.Box warning_box;
        [GtkChild]
        private unowned Adw.ActionRow time_row;
        [GtkChild]
        private unowned Adw.ToastOverlay toast_overlay;
        [GtkChild]
        private unowned Adw.PreferencesGroup absence_group;
        // The reason display *and* editor: an editable EntryRow with an apply
        // button when the absence can still be described.
        [GtkChild]
        private unowned Adw.EntryRow reason_row;

        private TimetableItem item;
        private Session session;

        public LessonDialog (TimetableItem item, Session session) {
            Object ();
            this.item = item;
            this.session = session;
            ensure_widget_styles (this);
            build (item);
        }

        private void build (TimetableItem item) {
            if (item.subject != "") {
                title = item.subject;
            }

            // Fill the static front-matter declared in the .ui.
            subject_label.label = item.subject;
            if (item.activity_code != "") {
                activity_label.label = item.activity_code;
                activity_label.visible = true;
            }
            // Warn about an upcoming lesson that can't be skipped.
            warning_box.visible = item.is_upcoming && !item.allow_absence;

            time_row.title = format_date (item);
            time_row.subtitle = item.time_range;

            // Only when the school surfaces absence reasons to students: show the
            // group when there's a reason to display or one can still be described.
            // When describable the row edits in place (apply button); otherwise
            // it's a read-only display of the existing reason.
            bool has_reason = item.absence_reason.strip () != "";
            bool describable = session.can_describe (item.end_datetime, item.absence_status);
            if (session.show_absence_reason && (has_reason || describable)) {
                reason_row.text = has_reason ? item.absence_reason.strip () : "";
                reason_row.editable = describable;
                reason_row.show_apply_button = describable;
                absence_group.visible = true;

                if (describable) {
                    reason_row.apply.connect (on_apply);
                    Connectivity.get_default ().bind_writable (reason_row);
                }
            }

            // Dynamic / repeated groups are appended after the static ones.
            var rooms = item.rooms;
            if (rooms.length > 0) {
                content_box.append (build_rooms (rooms));
            }

            var teachers = item.teachers;
            if (teachers.length > 0) {
                content_box.append (build_teachers (teachers));
            }

            if (item.homework.strip () != "") {
                content_box.append (build_text_group (_("Homework"), item.homework));
            }
            if (item.comment.strip () != "") {
                content_box.append (build_text_group (_("Comment"), item.comment));
            }
        }

        /* Apply button on the reason row: save the edited/added reason in place. */
        private void on_apply () {
            string reason = reason_row.text.strip ();
            if (reason == "") {
                return;   // nothing to save
            }
            save_reason.begin (reason);
        }

        private async void save_reason (string reason) {
            reason_row.sensitive = false;
            try {
                yield session.describe_absence (
                    item.admin_server_id, item.timetable_id, reason);
                toast_overlay.add_toast (new Adw.Toast (_("Reason saved.")));
            } catch (GLib.Error e) {
                warning ("describe absence failed: %s", e.message);
                toast_overlay.add_toast (new Adw.Toast (
                    _("Couldn't save reason — check your connection.")));
            }
            reason_row.sensitive = true;
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

        /* Teachers as a single collapsible row: the codes preview in the subtitle,
         * one row each when expanded — tidy whether it's one teacher or several. */
        private Gtk.Widget build_teachers (string[] teachers) {
            var group = new Adw.PreferencesGroup ();

            var expander = new Adw.ExpanderRow () {
                title = _("Teachers"),
                subtitle = string.joinv (", ", teachers)
            };
            foreach (string teacher in teachers) {
                expander.add_row (new Adw.ActionRow () { title = teacher });
            }
            group.add (expander);

            return group;
        }

        private Gtk.Widget build_text_group (string title, string text) {
            var group = new Adw.PreferencesGroup () {
                title = title
            };
            var row = new Adw.ActionRow () {
                title = text.strip (),
                use_markup = false,   // free-text (reason/note) may contain "&"/"<"
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
