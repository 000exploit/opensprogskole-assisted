/* window.vala
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

/* The top-level window is the flow coordinator. It is a three-state stack —
 * onboarding, a loading splash, and the main shell — and owns the bits the
 * widgets must not: the API session, the keyring and GSettings. Onboarding and
 * silent auto-login both converge on go_to_main(). */
[GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/window.ui")]
public class Opensprogskole.Window : Adw.ApplicationWindow {

    [GtkChild] private unowned Gtk.Stack root_stack;
    [GtkChild] private unowned OnboardingView onboarding;
    [GtkChild] private unowned MainView main_view;

    private GLib.Settings settings;
    private string device_name;
    private string device_id;
    private Session? pending_session = null;

    public Window (Gtk.Application app) {
        Object (application: app);
    }

    construct {
        settings = new GLib.Settings ("moe.ekusu.sprogskole");
        device_name = "OpenSprogskole on %s".printf (Environment.get_host_name ());
        device_id = ensure_device_id ();

        onboarding.authenticate_request.connect (on_authenticate_request);
        onboarding.finished.connect (() => {
            if (pending_session != null) {
                go_to_main.begin (pending_session);
            }
        });

        start ();
    }

    private string ensure_device_id () {
        string id = settings.get_string ("device-id");
        if (id == "") {
            id = GLib.Uuid.string_random ();
            settings.set_string ("device-id", id);
        }
        return id;
    }

    /* Decide the initial screen: silent login if an account is saved. */
    private void start () {
        string username = settings.get_string ("username");
        if (username == "") {
            root_stack.visible_child_name = "onboarding";
            return;
        }
        root_stack.visible_child_name = "loading";
        silent_login.begin (username);
    }

    private async void silent_login (string username) {
        string school_id = settings.get_string ("active-school");
        var school = Schools.by_id (school_id);
        try {
            string? password = yield SecretStore.lookup (school_id, username);
            if (password == null) {
                onboarding.prefill (username);
                root_stack.visible_child_name = "onboarding";
                return;
            }
            var provider = new UmsProvider (school, device_name, device_id);
            yield provider.login (username, password);
            yield go_to_main (new Session (school, provider, username));
        } catch (GLib.Error e) {
            warning ("silent login failed: %s", e.message);
            onboarding.prefill (username);
            onboarding.show_error (
                _("Couldn't sign you in automatically. Please log in again."));
            root_stack.visible_child_name = "onboarding";
        }
    }

    private void on_authenticate_request (School school, string username, string password) {
        onboarding.set_busy (true);
        do_login.begin (school, username, password);
    }

    private async void do_login (School school, string username, string password) {
        try {
            var provider = new UmsProvider (school, device_name, device_id);
            yield provider.login (username, password);

            yield SecretStore.store (school.id, username, password);
            settings.set_string ("active-school", school.id);
            settings.set_string ("username", username);

            pending_session = new Session (school, provider, username);
            onboarding.set_busy (false);
            onboarding.login_succeeded ();
        } catch (UmsError e) {
            onboarding.set_busy (false);
            onboarding.show_error (e.code == UmsError.UNAUTHORIZED
                ? _("Invalid username or password.")
                : _("Login failed: %s").printf (e.message));
        } catch (GLib.Error e) {
            onboarding.set_busy (false);
            onboarding.show_error (_("Login failed: %s").printf (e.message));
        }
    }

    private async void go_to_main (Session session) {
        root_stack.visible_child_name = "loading";
        yield session.refresh ();          // general data — keeps startup quick
        main_view.bind (session);
        root_stack.visible_child_name = "main";
        pending_session = null;
        session.refresh_absence.begin ();  // heavier; loads in the background
    }
}
