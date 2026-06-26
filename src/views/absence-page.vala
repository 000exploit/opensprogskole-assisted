/* absence-page.vala
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

    /* The Absence page: the list of reported absence events from the session,
     * or an empty state. Owns no data. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/absence-page.ui")]
    public class AbsencePage : Adw.Bin {

        [GtkChild] private unowned Gtk.ListBox list;
        [GtkChild] private unowned Gtk.Stack stack;
        [GtkChild] private unowned Gtk.Button report_button;

        public signal void report_absence_requested ();

        construct {
            report_button.clicked.connect (() => report_absence_requested ());
            Connectivity.get_default ().bind_writable (report_button);
        }

        private Session? session = null;

        public void bind (Session session) {
            this.session = session;
            // The ListBox tracks the store directly, so rows appear the moment
            // absences land. The stack (loading / list / empty) is driven by the
            // same signals: items-changed for live list edits, absence_updated
            // for the loading→loaded transition (incl. the "loaded but empty" case).
            list.bind_model (session.absences, create_row);
            session.absences.items_changed.connect (sync_stack);
            session.absence_updated.connect (sync_stack);
            sync_stack ();
        }

        private void sync_stack () {
            if (session == null) {
                return;
            }
            if (!session.absence_loaded) {
                stack.visible_child_name = "loading";
                return;
            }
            stack.visible_child_name =
                session.absences.get_n_items () > 0 ? "list" : "empty";
        }

        private Gtk.Widget create_row (GLib.Object object) {
            var item = (AbsenceItem) object;
            string subtitle = item.student_reason != ""
                ? "%s · %s".printf (item.when_label, item.student_reason)
                : item.when_label;
            return new Adw.ActionRow () {
                title = item.subject != "" ? item.subject : _("Absence"),
                subtitle = subtitle,
                title_lines = 0,
                subtitle_lines = 0
            };
        }
    }
}
