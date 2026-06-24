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

    /* Report-absence dialog. The first screen offers the three timing options
     * from the mockup — Today and Earlier are disabled; only Future is wired up.
     * Future leads to a small form that POSTs a future absence to the backend.
     * On success the dialog closes; on failure an inline banner is shown. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/absence-dialog.ui")]
    public class AbsenceDialog : Adw.Dialog {

        [GtkChild] private unowned Adw.NavigationView nav;
        [GtkChild] private unowned Button future_button;
        [GtkChild] private unowned Adw.Banner error_banner;
        [GtkChild] private unowned Adw.EntryRow reason_row;
        [GtkChild] private unowned Adw.ComboRow month_row;
        [GtkChild] private unowned Adw.SpinRow day_row;
        [GtkChild] private unowned Adw.SpinRow year_row;
        [GtkChild] private unowned Gtk.SpinButton start_hour;
        [GtkChild] private unowned Gtk.SpinButton start_minute;
        [GtkChild] private unowned Gtk.SpinButton end_hour;
        [GtkChild] private unowned Gtk.SpinButton end_minute;
        [GtkChild] private unowned Adw.Spinner spinner;
        [GtkChild] private unowned Button submit_button;

        private Session session;

        public AbsenceDialog (Session session) {
            Object ();
            this.session = session;
        }

        construct {
            // Month dropdown (localized names) + sensible "today" defaults.
            var months = new Gtk.StringList (null);
            var now = new DateTime.now_local ();
            for (int m = 1; m <= 12; m++) {
                months.append (new DateTime.local (2000, m, 1, 0, 0, 0).format ("%B"));
            }
            month_row.model = months;
            month_row.selected = now.get_month () - 1;
            day_row.value = now.get_day_of_month ();
            year_row.value = now.get_year ();

            // Two-digit display ("07", "05") for the time steppers.
            two_digits (start_hour);
            two_digits (start_minute);
            two_digits (end_hour);
            two_digits (end_minute);

            future_button.clicked.connect (() => nav.push_by_tag ("form"));
            submit_button.clicked.connect (on_submit);
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
                yield session.report_future_absence (
                    reason, iso (start_hour, start_minute), iso (end_hour, end_minute));
                close ();
            } catch (GLib.Error e) {
                warning ("create absence failed: %s", e.message);
                error_banner.title = _("Couldn't report absence. Please try again.");
                error_banner.revealed = true;
                set_busy (false);
            }
        }

        private void set_busy (bool busy) {
            spinner.visible = busy;
            submit_button.sensitive = !busy;
        }

        /* Build "yyyy-MM-ddTHH:mm:ss" from the Month/Day/Year rows + a time pair. */
        private string iso (Gtk.SpinButton hour, Gtk.SpinButton minute) {
            return "%04d-%02d-%02dT%02d:%02d:00".printf (
                (int) year_row.value, (int) month_row.selected + 1, (int) day_row.value,
                (int) hour.value, (int) minute.value);
        }
    }
}
