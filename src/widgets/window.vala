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
    private Session? active_session = null;

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
            // Reuse a still-valid saved token without contacting the server.
            // token-valid-until == 0 means the JWT had no expiry claim — per
            // design we still try the token in that case.
            string? token = yield SecretStore.lookup_token (school_id, username);
            int64 valid_until = settings.get_int64 ("token-valid-until");
            int64 now = GLib.get_real_time () / 1000000;
            if (token != null && (valid_until == 0 || valid_until > now + 60)) {
                var provider = new UmsProvider (school, device_name, device_id);
                provider.resume (token);
                yield go_to_main (new Session (school, provider, username));
                return;
            }

            // Token missing/expired: re-authenticate with the saved password.
            string? password = yield SecretStore.lookup (school_id, username);
            if (password == null) {
                onboarding.prefill (username);
                root_stack.visible_child_name = "onboarding";
                return;
            }
            var p = new UmsProvider (school, device_name, device_id);
            yield p.login (username, password);
            yield store_session_token (school, username, p);
            yield go_to_main (new Session (school, p, username));
        } catch (GLib.Error e) {
            warning ("silent login failed: %s", e.message);
            onboarding.prefill (username);
            onboarding.show_error (
                _("Couldn't sign you in automatically. Please log in again."));
            root_stack.visible_child_name = "onboarding";
        }
    }

    private void on_authenticate_request (School school, string username,
                                          string password, bool save_password) {
        onboarding.set_busy (true);
        do_login.begin (school, username, password, save_password);
    }

    private async void do_login (School school, string username, string password,
                                 bool save_password) {
        try {
            var provider = new UmsProvider (school, device_name, device_id);
            yield provider.login (username, password);

            settings.set_string ("active-school", school.id);
            settings.set_string ("username", username);
            yield store_session_token (school, username, provider);

            // The token is always saved; the password only with the user's
            // consent (any previously saved one is cleared otherwise).
            if (save_password) {
                yield SecretStore.store (school.id, username, password);
            } else {
                yield SecretStore.clear (school.id, username);
            }

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

    /* Persist the freshly obtained token + its expiry. */
    private async void store_session_token (School school, string username,
                                            UmsProvider provider) throws GLib.Error {
        settings.set_int64 ("token-valid-until", provider.token_expires_at);
        yield SecretStore.store_token (school.id, username, provider.token);
    }

    private async void go_to_main (Session session) {
        root_stack.visible_child_name = "loading";
        yield session.refresh ();          // general data — keeps startup quick
        main_view.bind (session);
        root_stack.visible_child_name = "main";
        pending_session = null;
        active_session = session;
        session.refresh_absence.begin ();  // heavier; loads in the background
    }

    /* Log out: invalidate the token server-side (best effort), forget the saved
     * account, and return to onboarding. Invoked via the app.logout action. */
    public void logout () {
        do_logout.begin ();
    }

    private async void do_logout () {
        string school_id = settings.get_string ("active-school");
        string username = settings.get_string ("username");

        if (active_session != null && active_session.provider is UmsProvider) {
            try {
                yield ((UmsProvider) active_session.provider).logout ();
            } catch (GLib.Error e) {
                warning ("DeleteToken failed (logging out locally anyway): %s", e.message);
            }
        }

        try { yield SecretStore.clear_token (school_id, username); } catch (GLib.Error e) {
            warning ("clear token failed: %s", e.message);
        }
        try { yield SecretStore.clear (school_id, username); } catch (GLib.Error e) {
            warning ("clear password failed: %s", e.message);
        }
        settings.set_string ("username", "");
        settings.set_int64 ("token-valid-until", 0);

        active_session = null;
        onboarding.reset ();
        root_stack.visible_child_name = "onboarding";
    }
}
