/* session-controller.vala
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

    /* Owns the account/session lifecycle: secure storage, the JWT-expiry decision,
     * silent auto-login, manual login, and logout. It holds no widgets — it emits
     * state signals and the Window maps them to screens. This keeps all of the
     * auth/network/keyring logic out of the UI layer. */
    public class SessionController : GLib.Object {

        public Session? session { get; private set; default = null; }

        // Reconnect retry backs off up to this many seconds: the link can come up
        // before DNS/routing is ready, so the first attempt often fails with a
        // name-resolution error — we keep trying, spaced out, until it sticks.
        private const int RECONNECT_MAX_DELAY = 16;

        private GLib.Settings settings;
        private string device_name;
        private string device_id;
        // Logged in but waiting for the user to confirm the welcome page.
        private Session? pending = null;
        // Pending reconnect-retry timer + its current backoff step.
        private uint reconnect_source = 0;
        private int reconnect_delay = 0;

        /* Show the loading splash (bootstrapping / fetching). */
        public signal void loading ();
        /* Show onboarding. username/error are set when a saved account couldn't be
         * resumed (prefill + message); both null for a clean first run / logout. */
        public signal void needs_login (string? username, string? error);
        /* A manual login attempt failed. */
        public signal void login_failed (string message);
        /* A manual login attempt succeeded (Window shows the welcome page). */
        public signal void login_succeeded ();
        /* The session is ready and its first data load is done. */
        public signal void authenticated (Session session);

        construct {
            settings = new GLib.Settings ("moe.ekusu.sprogskole");
            device_name = "OpenSprogskole on %s".printf (Environment.get_host_name ());
            device_id = ensure_device_id ();

            // React to connectivity changes. On loss, abort in-flight requests so
            // they fail now (a per-request cancel can't unstick a shared HTTP/2
            // connection — tearing it down does). On return, retry what failed.
            // Lives here (not in Session) so the long-lived controller owns the
            // subscription — no leak when the per-account Session is replaced.
            Connectivity.get_default ().notify["online"].connect (() => {
                if (Connectivity.get_default ().online) {
                    begin_reconnect_retry ();
                } else {
                    cancel_reconnect_retry ();
                    if (session != null) {
                        session.abort_requests ();
                    }
                }
            });
        }

        /* Came back online: retry the failed loads, then keep retrying with an
         * increasing delay until they stick or we hit the ceiling — the link is
         * often up before DNS/routing is, so the first attempt(s) can fail. */
        private void begin_reconnect_retry () {
            cancel_reconnect_retry ();
            reconnect_delay = 1;
            attempt_reconnect_retry ();
        }

        private void attempt_reconnect_retry () {
            if (session == null || !Connectivity.get_default ().online) {
                return;
            }
            if (!session.retry_failed_loads ()) {
                return;   // nothing left failing — recovered
            }
            if (reconnect_delay >= RECONNECT_MAX_DELAY) {
                return;   // backed off as far as we will — give up until next change
            }
            reconnect_delay = int.min (reconnect_delay * 2, RECONNECT_MAX_DELAY);
            reconnect_source = Timeout.add_seconds (reconnect_delay, () => {
                reconnect_source = 0;
                attempt_reconnect_retry ();
                return Source.REMOVE;
            });
        }

        private void cancel_reconnect_retry () {
            if (reconnect_source != 0) {
                Source.remove (reconnect_source);
                reconnect_source = 0;
            }
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
        public void start () {
            string username = settings.get_string ("username");
            if (username == "") {
                needs_login (null, null);
                return;
            }
            loading ();
            silent_login.begin (username);
        }

        private async void silent_login (string username) {
            string school_id = settings.get_string ("active-school");
            var school = Schools.by_id (school_id);
            try {
                var provider = new UmsProvider (school, device_name, device_id);

                // Reuse a still-valid saved token without contacting the server.
                // valid_until == 0 means the JWT had no expiry claim — still try it.
                string? token = yield SecretStore.lookup_token (school_id, username);
                int64 valid_until = settings.get_int64 ("token-valid-until");
                int64 now = GLib.get_real_time () / 1000000;

                if (token != null && (valid_until == 0 || valid_until > now + 60)) {
                    provider.resume (token);
                } else {
                    warning ("token expired, requesting new.");
                    string? password = yield SecretStore.lookup (school_id, username);
                    if (password == null) {
                        needs_login (username, null);
                        return;
                    }
                    yield provider.login (username, password);
                    yield store_token (school, username, provider);
                }

                yield enter_session (new Session (school, provider, username));
            } catch (GLib.Error e) {
                warning ("silent login failed: %s", e.message);
                needs_login (username,
                    _("Couldn't sign you in automatically. Please log in again."));
            }
        }

        /* Authenticate from the onboarding form. The token is always saved; the
         * password only with consent (any previously saved one is cleared). */
        public async void try_login (School school, string username, string password,
                                     bool save_password) {
            try {
                var provider = new UmsProvider (school, device_name, device_id);
                yield provider.login (username, password);

                settings.set_string ("active-school", school.id);
                settings.set_string ("username", username);
                yield store_token (school, username, provider);

                if (save_password) {
                    yield SecretStore.store (school.id, username, password);
                } else {
                    yield SecretStore.clear (school.id, username);
                }

                pending = new Session (school, provider, username);
                login_succeeded ();
            } catch (UmsError e) {
                login_failed (e.code == UmsError.UNAUTHORIZED
                    ? _("Invalid username or password.")
                    : _("Login failed: %s").printf (e.message));
            } catch (GLib.Error e) {
                login_failed (_("Login failed: %s").printf (e.message));
            }
        }

        /* User confirmed the welcome page → enter the app. */
        public void enter () {
            if (pending == null) {
                return;
            }
            var ready = pending;
            pending = null;
            enter_session.begin (ready);
        }

        private async void enter_session (Session s) {
            loading ();
            yield s.refresh ();           // fast critical data — paints the shell
            session = s;
            authenticated (s);
            // Slow endpoints stream into their own cards (spinners) afterwards,
            // so a sluggish GetTimetable/GetUserAbsence never holds up startup.
            s.refresh_streamed ();
        }

        /* Invalidate the token server-side (best effort), forget the account, and
         * return to onboarding. */
        public void logout () {
            do_logout.begin ();
        }

        private async void do_logout () {
            string school_id = settings.get_string ("active-school");
            string username = settings.get_string ("username");

            if (session != null) {
                try {
                    yield session.provider.logout ();
                } catch (GLib.Error e) {
                    warning ("provider logout failed (logging out locally anyway): %s", e.message);
                }
            }

            try {
                yield SecretStore.clear_token (school_id, username);
            } catch (GLib.Error e) {
                warning ("clear token failed: %s", e.message);
            }
            try {
                yield SecretStore.clear (school_id, username);
            } catch (GLib.Error e) {
                warning ("clear password failed: %s", e.message);
            }
            settings.set_string ("username", "");
            settings.set_int64 ("token-valid-until", 0);

            // Wipe this account's whole on-disk store along with its secrets.
            Storage.clear (Checksum.compute_for_string (
                ChecksumType.SHA256, "%s:%s".printf (school_id, username)));

            session = null;
            needs_login (null, null);
        }

        private async void store_token (School school, string username,
                                        UmsProvider provider) throws GLib.Error {
            settings.set_int64 ("token-valid-until", provider.token_expires_at);
            yield SecretStore.store_token (school.id, username, provider.token);
        }
    }
}
