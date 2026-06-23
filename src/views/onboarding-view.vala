/* onboarding-view.vala
 *
 * Copyright 2026 flex
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

    /* The pre-login flow: hello → login (with school picker) → welcome. It only
     * collects input and drives navigation; the Window does the actual
     * authentication and persistence. The split keeps network/secrets out of the
     * widget. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/onboarding-view.ui")]
    public class OnboardingView : Adw.Bin {

        [GtkChild] private unowned Adw.NavigationView nav;
        [GtkChild] private unowned Button hello_next_button;
        [GtkChild] private unowned Adw.ComboRow school_row;
        [GtkChild] private unowned Adw.EntryRow username_row;
        [GtkChild] private unowned Adw.PasswordEntryRow password_row;
        [GtkChild] private unowned Adw.Banner error_banner;
        [GtkChild] private unowned Adw.Spinner spinner;
        [GtkChild] private unowned Button login_button;
        [GtkChild] private unowned Button continue_button;

        /* The Window handles these. */
        public signal void authenticate_request (School school, string username, string password);
        public signal void finished ();

        private GLib.GenericArray<School> schools;

        construct {
            schools = Schools.all ();
            var names = new Gtk.StringList (null);
            for (uint i = 0; i < schools.length; i++) {
                names.append (schools[i].name);
            }
            school_row.model = names;

            hello_next_button.clicked.connect (() => nav.push_by_tag ("login"));
            login_button.clicked.connect (on_login);
            continue_button.clicked.connect (() => finished ());
        }

        private void on_login () {
            error_banner.revealed = false;
            uint idx = school_row.selected;
            var school = idx < schools.length ? schools[idx] : Schools.spc_midt ();
            authenticate_request (school, username_row.text, password_row.text);
        }

        /* Called by the Window while authentication is in flight. */
        public void set_busy (bool busy) {
            spinner.visible = busy;
            login_button.sensitive = !busy;
            username_row.sensitive = !busy;
            password_row.sensitive = !busy;
            school_row.sensitive = !busy;
        }

        public void show_error (string message) {
            error_banner.title = message;
            error_banner.revealed = true;
        }

        /* Advance to the welcome page after a successful login. */
        public void login_succeeded () {
            error_banner.revealed = false;
            nav.push_by_tag ("welcome");
        }

        /* Pre-fill the username (used when a saved account failed silent login). */
        public void prefill (string username) {
            username_row.text = username;
            nav.push_by_tag ("login");
        }
    }
}
