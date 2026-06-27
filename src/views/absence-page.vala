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

    /* The Absence page: the read-only registered absences plus the student's own
     * editable "planned" absences (each with edit/delete actions). Owns no data —
     * it tracks the session's stores and load state. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/absence-page.ui")]
    public class AbsencePage : Adw.Bin {

        [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
        [GtkChild] private unowned Gtk.ListBox list;
        [GtkChild] private unowned Gtk.Stack stack;
        [GtkChild] private unowned LoadingState absence_loading;
        [GtkChild] private unowned Gtk.Button report_button;
        [GtkChild] private unowned Gtk.Box planned_section;
        [GtkChild] private unowned Gtk.ListBox planned_list;

        public signal void report_absence_requested ();

        construct {
            report_button.clicked.connect (() => report_absence_requested ());
            Connectivity.get_default ().bind_writable (report_button);
        }

        private Session? session = null;

        public void bind (Session session) {
            this.session = session;
            // Both ListBoxes track their stores directly, so rows appear the
            // moment data lands. The reported stack (loading / list / empty) and
            // the planned section's visibility are driven by the same signals:
            // items-changed for live list edits, *_updated for the load
            // transitions (incl. the "loaded but empty" case).
            list.bind_model (session.absences, create_row);
            session.absences.items_changed.connect (sync_stack);
            session.absence_updated.connect (sync_stack);

            planned_list.bind_model (session.future_absences, create_planned_row);
            session.future_absences.items_changed.connect (sync_planned);
            session.future_absence_updated.connect (sync_planned);

            sync_stack ();
            sync_planned ();
        }

        private void sync_stack () {
            if (session == null) {
                return;
            }
            if (session.absence_state != LoadState.LOADED) {
                absence_loading.error = session.absence_state == LoadState.FAILED
                    ? _("Couldn't load absences.") : "";
                stack.visible_child_name = "loading";
                return;
            }
            stack.visible_child_name =
                session.absences.get_n_items () > 0 ? "list" : "empty";
        }

        /* The planned section only exists when the student has reported one — an
         * empty or still-loading list just stays hidden (the reported section
         * already carries the page's loading/empty state). */
        private void sync_planned () {
            if (session == null) {
                return;
            }
            planned_section.visible = session.future_absence_state == LoadState.LOADED
                && session.future_absences.get_n_items () > 0;
        }

        private Gtk.Widget create_row (GLib.Object object) {
            var item = (AbsenceItem) object;
            string subtitle = item.student_reason != ""
                ? "%s · %s".printf (item.when_label, item.student_reason)
                : item.when_label;
            var row = new Adw.ActionRow () {
                title = item.subject != "" ? item.subject : _("Absence"),
                subtitle = subtitle,
                title_lines = 0,
                subtitle_lines = 0
            };

            // A past absent lesson still inside the school's window can have its
            // reason described/edited (connectivity-gated, since it writes).
            if (session != null && session.can_describe (item.end_time, item.status)) {
                bool has_reason = item.student_reason.strip () != "";
                var describe = new Gtk.Button () {
                    icon_name = "document-edit-symbolic",
                    valign = Gtk.Align.CENTER,
                    tooltip_text = has_reason ? _("Edit reason") : _("Describe absence")
                };
                describe.add_css_class ("flat");
                describe.clicked.connect (() => open_describe (item));
                Connectivity.get_default ().bind_writable (describe);
                row.add_suffix (describe);
            }
            return row;
        }

        private void open_describe (AbsenceItem item) {
            if (session == null) {
                return;
            }
            bool has_reason = item.student_reason.strip () != "";
            var dialog = new ReasonDialog (
                has_reason ? _("Edit reason") : _("Describe absence"),
                item.subject, item.student_reason, _("Save"));
            dialog.submitted.connect ((reason) => describe.begin (dialog, item, reason));
            dialog.present (this);
        }

        private async void describe (ReasonDialog dialog, AbsenceItem item, string reason) {
            if (session == null) {
                return;
            }
            dialog.set_busy (true);
            try {
                yield session.describe_absence (item.server_id, item.event_id, reason);
                dialog.close ();
            } catch (GLib.Error e) {
                warning ("describe absence failed: %s", e.message);
                dialog.toast (_("Couldn't save reason — check your connection."));
                dialog.set_busy (false);
            }
        }

        /* A planned-absence row: the reason, its window, and edit/delete buttons.
         * Both buttons follow connectivity (disabled offline) since they write. */
        private Gtk.Widget create_planned_row (GLib.Object object) {
            var item = (FutureAbsenceItem) object;
            var row = new Adw.ActionRow () {
                title = item.reason != "" ? item.reason : _("Absence"),
                subtitle = item.when_label,
                title_lines = 0,
                subtitle_lines = 0
            };

            var edit = new Gtk.Button () {
                icon_name = "document-edit-symbolic",
                valign = Gtk.Align.CENTER,
                tooltip_text = _("Edit")
            };
            edit.add_css_class ("flat");
            edit.clicked.connect (() => open_edit (item));

            var remove = new Gtk.Button () {
                icon_name = "user-trash-symbolic",
                valign = Gtk.Align.CENTER,
                tooltip_text = _("Delete")
            };
            remove.add_css_class ("flat");
            remove.clicked.connect (() => confirm_delete (item));

            Connectivity.get_default ().bind_writable (edit);
            Connectivity.get_default ().bind_writable (remove);

            row.add_suffix (edit);
            row.add_suffix (remove);
            return row;
        }

        private void open_edit (FutureAbsenceItem item) {
            if (session != null) {
                new AbsenceDialog.for_edit (session, item).present (this);
            }
        }

        private void confirm_delete (FutureAbsenceItem item) {
            var dialog = new Adw.AlertDialog (
                _("Delete this absence?"),
                _("The reported absence will be removed."));
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("delete", _("Delete"));
            dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "cancel";
            dialog.close_response = "cancel";
            dialog.response.connect ((response) => {
                if (response == "delete") {
                    delete_item.begin (item);
                }
            });
            dialog.present (this);
        }

        private async void delete_item (FutureAbsenceItem item) {
            if (session == null) {
                return;
            }
            try {
                yield session.delete_future_absence (item.id);
            } catch (GLib.Error e) {
                warning ("delete absence failed: %s", e.message);
                toast_overlay.add_toast (new Adw.Toast (
                    _("Couldn't delete absence — check your connection.")));
            }
        }
    }
}
