/* absence-dialog.vala
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

using Gtk;

namespace Opensprogskole {

    /* Report-absence dialog. The first screen offers three timing options:
     *   - Today    — a whole-day absence for today (or tomorrow after 20:30),
     *                spanning that day's lessons (CreateFutureStudentAbsence).
     *   - Earlier  — there is no "create a past absence"; the backend edits an
     *                absence by updating its future record, so this just routes
     *                the user to the Absence page where those live.
     *   - Future   — the date/time form, also CreateFutureStudentAbsence.
     * Opened with .for_edit() it skips straight to the form, pre-filled, and
     * PUTs an UpdateFutureStudentAbsence instead. On success it closes; on a
     * failed submit a toast is shown. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/absence-dialog.ui")]
    public class AbsenceDialog : Adw.Dialog {

        [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
        [GtkChild] private unowned Adw.NavigationView nav;
        [GtkChild] private unowned Adw.NavigationPage form_page;
        [GtkChild] private unowned Button today_button;
        [GtkChild] private unowned Button earlier_button;
        [GtkChild] private unowned Button future_button;
        [GtkChild] private unowned Adw.Banner error_banner;
        [GtkChild] private unowned Adw.EntryRow reason_row;
        [GtkChild] private unowned Gtk.Label last_updated_label;
        [GtkChild] private unowned Adw.ComboRow month_row;
        [GtkChild] private unowned Adw.SpinRow day_row;
        [GtkChild] private unowned Adw.SpinRow year_row;
        [GtkChild] private unowned Gtk.SpinButton start_hour;
        [GtkChild] private unowned Gtk.SpinButton start_minute;
        [GtkChild] private unowned Gtk.SpinButton end_hour;
        [GtkChild] private unowned Gtk.SpinButton end_minute;
        [GtkChild] private unowned Adw.Spinner spinner;
        [GtkChild] private unowned Button submit_button;
        [GtkChild] private unowned Adw.EntryRow sick_reason_row;
        [GtkChild] private unowned Adw.Spinner sick_spinner;
        [GtkChild] private unowned Button sick_submit_button;

        /* The user chose "Earlier" — they want the Absence page, not a new record.
         * The caller (which owns navigation) handles this and the dialog closes. */
        public signal void show_absences_requested ();

        private Session session;
        // 0 when creating; the future-absence id when editing an existing one.
        private int edit_id = 0;
        // In-flight flags for the two submits; combined with connectivity to drive
        // their sensitivity (see sync_submits).
        private bool form_busy = false;
        private bool sick_busy = false;

        public AbsenceDialog (Session session) {
            Object ();
            this.session = session;
        }

        /* Open straight on the form, pre-filled from an existing future absence;
         * submitting updates it instead of creating a new one. */
        public AbsenceDialog.for_edit (Session session, FutureAbsenceItem item) {
            Object ();
            this.session = session;
            this.edit_id = item.id;

            reason_row.text = item.reason;
            var start = item.start_date_time ?? new DateTime.now_local ();
            var end = item.end_date_time ?? start;
            set_date (start);
            set_time (start_hour, start_minute, start);
            set_time (end_hour, end_minute, end);

            form_page.title = _("Edit absence");
            submit_button.label = _("Save changes");
            if (item.last_updated_label != "") {
                last_updated_label.label = _("Last updated %s").printf (item.last_updated_label);
                last_updated_label.visible = true;
            }
            // Replace the stack so Back/Escape leaves the dialog rather than
            // dropping the user on the (irrelevant) "choose" page.
            nav.replace_with_tags ({ "form" });
        }

        construct {
            // Month dropdown (localized names) + sensible "today" defaults.
            var months = new Gtk.StringList (null);
            for (int m = 1; m <= 12; m++) {
                months.append (new DateTime.local (2000, m, 1, 0, 0, 0).format ("%B"));
            }
            month_row.model = months;
            set_date (new DateTime.now_local ());

            // Two-digit display ("07", "05") for the time steppers.
            two_digits (start_hour);
            two_digits (start_minute);
            two_digits (end_hour);
            two_digits (end_minute);

            today_button.clicked.connect (on_today);
            earlier_button.clicked.connect (() => {
                show_absences_requested ();
                close ();
            });
            future_button.clicked.connect (() => nav.push_by_tag ("form"));
            submit_button.clicked.connect (on_submit);
            sick_submit_button.clicked.connect (on_sick_submit);

            // Both submits are writes — keep them off while offline (or busy).
            Connectivity.get_default ().notify["online"].connect (sync_submits);
            sync_submits ();
        }

        private void sync_submits () {
            bool online = Connectivity.get_default ().online;
            submit_button.sensitive = !form_busy && online;
            sick_submit_button.sensitive = !sick_busy && online;
        }

        /* "Today" = call in sick, on its own page in the same navigation view.
         * The backend only accepts this up to 20:30 local; past that we say so
         * rather than letting it fail. */
        private void on_today () {
            if (!session.can_call_in_sick ()) {
                toast_overlay.add_toast (new Adw.Toast (
                    _("You can only call in sick before 20:30.")));
                return;
            }
            nav.push_by_tag ("sick");
        }

        private void on_sick_submit () {
            string reason = sick_reason_row.text.strip ();
            if (reason == "") {
                toast_overlay.add_toast (new Adw.Toast (_("Please enter a reason.")));
                return;
            }
            call_in_sick.begin (reason);
        }

        private async void call_in_sick (string reason) {
            set_sick_busy (true);
            try {
                string message = yield session.call_in_sick (reason);
                if (message != "") {
                    // The backend replied with something to show — often a
                    // rejection (e.g. "no more classes today"). Stay on the page
                    // so the message is seen.
                    toast_overlay.add_toast (new Adw.Toast (message));
                    set_sick_busy (false);
                } else {
                    close ();
                }
            } catch (GLib.Error e) {
                warning ("call in sick failed: %s", e.message);
                toast_overlay.add_toast (new Adw.Toast (
                    _("Couldn't call in sick — check your connection.")));
                set_sick_busy (false);
            }
        }

        private void set_sick_busy (bool busy) {
            sick_busy = busy;
            sick_spinner.visible = busy;
            sick_reason_row.sensitive = !busy;
            sync_submits ();
        }

        private void set_date (DateTime dt) {
            month_row.selected = dt.get_month () - 1;
            day_row.value = dt.get_day_of_month ();
            year_row.value = dt.get_year ();
        }

        private void set_time (Gtk.SpinButton hour, Gtk.SpinButton minute, DateTime dt) {
            hour.value = dt.get_hour ();
            minute.value = dt.get_minute ();
        }

        private void two_digits (Gtk.SpinButton spin) {
            spin.output.connect (() => {
                spin.text = "%02d".printf ((int) spin.value);
                return true;
            });
        }

        private void on_submit () {
            error_banner.revealed = false;
            string reason = reason_row.text.strip ();
            if (reason == "") {
                error_banner.title = _("Please enter a reason.");
                error_banner.revealed = true;
                return;
            }
            submit.begin (reason);
        }

        private async void submit (string reason) {
            set_busy (true);
            try {
                if (edit_id != 0) {
                    yield session.update_future_absence (
                        edit_id, reason, iso (start_hour, start_minute), iso (end_hour, end_minute));
                } else {
                    yield session.report_future_absence (
                        reason, iso (start_hour, start_minute), iso (end_hour, end_minute));
                }
                close ();
            } catch (GLib.Error e) {
                warning ("save absence failed: %s", e.message);
                toast_overlay.add_toast (new Adw.Toast (
                    _("Couldn't save absence — check your connection.")));
                set_busy (false);
            }
        }

        private void set_busy (bool busy) {
            form_busy = busy;
            spinner.visible = busy;
            sync_submits ();
        }

        /* Build "yyyy-MM-ddTHH:mm:ss" from the Month/Day/Year rows + a time pair. */
        private string iso (Gtk.SpinButton hour, Gtk.SpinButton minute) {
            return "%04d-%02d-%02dT%02d:%02d:00".printf (
                (int) year_row.value, (int) month_row.selected + 1, (int) day_row.value,
                (int) hour.value, (int) minute.value);
        }
    }
}
