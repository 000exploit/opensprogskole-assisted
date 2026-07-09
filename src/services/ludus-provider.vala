/* ludus-provider.vala
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

    /* SchoolProvider for LUDUS (EG) schools. Sign-in is OpenID Connect
     * (Authorization Code + PKCE) against the school's Keycloak realm: the
     * provider opens the system browser, waits for the dk.eg.ludus.mobile://
     * redirect (via OidcCallbackRouter), and exchanges the code for tokens.
     * The refresh token is the resume secret.
     *
     * STATUS: auth (authenticate/resume/logout) is implemented; the data
     * load_* methods throw LudusError.NOT_MAPPED until their response shapes
     * are confirmed against a live account — see docs/ludus-api.md. */
    public class LudusProvider : GLib.Object, SchoolProvider {

        private School _school;
        public School school { get { return _school; } }

        private LudusClient client = new LudusClient ();
        private LudusTokens? tokens = null;

        public LudusProvider (School school) {
            this._school = school;
        }

        public void use_account (string username, Storage storage) {
            // Scope authed API calls to the chosen school.
            client.institution_number = number ();
        }

        /* The school's institution number, carried in the School id as
         * "ludus:<number>" (see LudusFamily.fetch_schools). */
        private string number () {
            string id = school.id;
            return id.has_prefix ("ludus:") ? id.substring ("ludus:".length) : id;
        }

        /* Data endpoints are all stubbed (LudusError.NOT_MAPPED), so no widget
         * has data to show yet. Flip specific kinds to true as they're mapped. */
        public bool supports (DataKind kind) {
            return false;
        }

        public int64 token_expires_at {
            get { return tokens != null ? tokens.expires_at : 0; }
        }

        /* LUDUS is OIDC only — one browser-driven method. The label stays
         * neutral: the school's Keycloak page decides whether it's MitID or
         * username/password, so we can't name the mechanism up front. */
        public async GLib.GenericArray<LoginMethod> login_methods () throws GLib.Error {
            var list = new GLib.GenericArray<LoginMethod> ();
            list.add (new LoginMethod ("oidc", LoginKind.OAUTH,
                                       _("Continue to sign-in"), "dialog-password-symbolic"));
            return list;
        }

        /* The full OIDC dance. `credentials` is unused (OAUTH carries none);
         * `cancellable` fires if the user abandons the browser prompt. */
        /* The school's Keycloak realm, "ludus-<institutionNumber>". The number
         * rides in the School id as "ludus:<number>" (see
         * LudusFamily.fetch_schools). */
        private string realm () {
            return LudusConfig.realm_for (number ());
        }

        public async void authenticate (LoginMethod method, GLib.Variant credentials,
                                        GLib.Cancellable? cancellable = null)
            throws GLib.Error {
            var cancel = cancellable ?? new GLib.Cancellable ();
            string realm = realm ();

            string verifier = LudusOidc.new_verifier ();
            string state = LudusOidc.new_state ();
            string nonce = LudusOidc.new_state ();   // same shape, distinct value
            string url = LudusOidc.authorization_url (
                realm, state, nonce, LudusOidc.challenge_for (verifier));

            var launcher = new Gtk.UriLauncher (url);
            Gtk.Window? parent =
                (GLib.Application.get_default () as Gtk.Application)?.active_window;
            yield launcher.launch (parent, cancel);

            string? redirect = yield OidcCallbackRouter.get_default ().next (cancel);
            if (redirect == null) {
                throw new LudusAuthError.FLOW ("Sign-in was cancelled");
            }
            string code = LudusOidc.code_from_redirect (redirect, state);
            tokens = yield LudusOidc.exchange_code (client.soup, realm,
                                                    code, verifier, cancel);
            client.access_token = tokens.access_token;
        }

        /* Resume from a stored {refresh_token}: swap it for a fresh access
         * token. Throws if the refresh token is dead (the controller then falls
         * back to a full sign-in). */
        public async void resume (GLib.Variant saved) throws GLib.Error {
            string refresh_token = field (saved, "refresh_token");
            if (refresh_token == "") {
                throw new LudusAuthError.TOKEN ("No refresh token to resume from");
            }
            tokens = yield LudusOidc.refresh (client.soup, realm (),
                                              refresh_token, null);
            client.access_token = tokens.access_token;
        }

        public GLib.Variant session_secret {
            owned get {
                var b = new GLib.VariantDict ();
                string refresh = tokens != null ? tokens.refresh_token : "";
                b.insert_value ("refresh_token", new GLib.Variant.string (refresh));
                return b.end ();
            }
        }

        /* End the Keycloak session (best effort). */
        public async void logout () throws GLib.Error {
            if (tokens == null || tokens.refresh_token == "") {
                return;
            }
            var msg = new Soup.Message ("POST",
                LudusConfig.endpoint_for (realm (), LudusConfig.Endpoint.LOGOUT));
            var form = new GLib.HashTable<string, string> (str_hash, str_equal);
            form.insert ("client_id", LudusConfig.CLIENT_ID);
            form.insert ("refresh_token", tokens.refresh_token);
            string body = Soup.Form.encode_hash (form);
            msg.set_request_body_from_bytes ("application/x-www-form-urlencoded",
                                             new Bytes (body.data));
            yield client.soup.send_and_read_async (msg, Priority.DEFAULT, null);
        }

        public void abort_requests () {
            client.abort ();
        }

        private static string field (GLib.Variant v, string key) {
            var entry = new GLib.VariantDict (v).lookup_value (key, GLib.VariantType.STRING);
            return entry != null ? entry.get_string () : "";
        }

        // --- Reads: wired to the LUDUS endpoints (see LudusEndpoints) ----------
        //
        // The endpoint paths are recovered from the app; parsing mirrors the UMS
        // provider (Json.gobject_deserialize / from_json). IMPORTANT: no LUDUS
        // response body survived the AOT compile, so the field mappings are
        // UNVERIFIED — these fetch correctly but a live account is needed to
        // confirm the shapes. Unexpected shapes degrade to empty rather than
        // throw, so a mismatch shows "no data", not an error wall.

        public async GLib.GenericArray<TimetableItem> load_timetable () throws GLib.Error {
            var node = yield client.get_json (LudusEndpoints.TIMETABLE);
            if (node.get_node_type () == Json.NodeType.ARRAY) {
                return TimetableItem.from_json_array (node.get_array ());
            }
            return new GLib.GenericArray<TimetableItem> ();
        }

        public async AbsenceData load_absence () throws GLib.Error {
            var data = new AbsenceData ();
            var node = yield client.get_json (LudusEndpoints.ABSENCE);
            if (node.get_node_type () == Json.NodeType.ARRAY) {
                node.get_array ().foreach_element ((arr, i, element) => {
                    if (element.get_node_type () == Json.NodeType.OBJECT) {
                        data.items.add ((AbsenceItem) Json.gobject_deserialize (
                            typeof (AbsenceItem), element));
                    }
                });
            }
            // Attendance summary is a separate endpoint; best effort.
            try {
                var overview = yield client.get_json (LudusEndpoints.ABSENCE_OVERVIEW);
                if (overview.get_node_type () == Json.NodeType.OBJECT) {
                    data.summary = (AbsenceSummary) Json.gobject_deserialize (
                        typeof (AbsenceSummary), overview);
                }
            } catch (GLib.Error e) {
                warning ("ludus absence overview: %s", e.message);
            }
            return data;
        }

        /* LUDUS's mobile API exposes no grades endpoint — genuinely none, so an
         * empty list (the Grades widget then shows its empty state). */
        public async GLib.GenericArray<GradeItem> load_grades () throws GLib.Error {
            return new GLib.GenericArray<GradeItem> ();
        }

        public async UserInfoItem? load_user_info () throws GLib.Error {
            var node = yield client.get_json (LudusEndpoints.STUDENT);
            if (node.get_node_type () == Json.NodeType.OBJECT) {
                return (UserInfoItem) Json.gobject_deserialize (typeof (UserInfoItem), node);
            }
            if (node.get_node_type () == Json.NodeType.ARRAY
                && node.get_array ().get_length () > 0) {
                return (UserInfoItem) Json.gobject_deserialize (typeof (UserInfoItem),
                    node.get_array ().get_element (0));
            }
            return null;
        }

        /* No known "editable fields" endpoint — nothing editable for now. */
        public async UserInfoSettings? load_user_info_settings () throws GLib.Error {
            return null;
        }

        /* No clear future-absence read endpoint yet — empty. */
        public async GLib.GenericArray<FutureAbsenceItem> load_future_absence ()
            throws GLib.Error {
            return new GLib.GenericArray<FutureAbsenceItem> ();
        }

        public async AbsenceSettings? load_absence_settings () throws GLib.Error {
            var node = yield client.get_json (LudusEndpoints.ABSENCE_REASONS);
            if (node.get_node_type () == Json.NodeType.OBJECT) {
                return (AbsenceSettings) Json.gobject_deserialize (
                    typeof (AbsenceSettings), node);
            }
            return null;
        }

        /* App config (links + call-in-sick cutoff). The response shape is
         * unconfirmed, so return an empty config for now (no links). */
        public async AppConfig load_app_config () throws GLib.Error {
            return new AppConfig ();
        }

        // --- Writes: endpoints known, but request bodies are unconfirmed, so
        // these stay stubbed (posting a guessed body could send bad data).

        private GLib.Error not_mapped (string feature) {
            return new LudusError.NOT_MAPPED (
                "LUDUS %s isn't mapped yet (see docs/ludus-api.md)".printf (feature));
        }

        public async bool update_user_info (UserInfoItem info) throws GLib.Error {
            throw not_mapped ("profile update");
        }
        public async bool update_user_image (GLib.Bytes image) throws GLib.Error {
            throw not_mapped ("profile picture");   // /profile-picture
        }
        public async bool delete_pending_image () throws GLib.Error {
            throw not_mapped ("profile picture");
        }
        public async GLib.Bytes? fetch_picture (string url) throws GLib.Error {
            return null;   // profile pictures not wired yet
        }
        public async int create_future_absence (string reason, string start_iso,
                                                string end_iso) throws GLib.Error {
            throw not_mapped ("absence reporting");   // /absenceRegistration
        }
        public async void update_future_absence (int id, string reason,
                                                 string start_iso, string end_iso)
            throws GLib.Error {
            throw not_mapped ("absence reporting");
        }
        public async void delete_future_absence (int id) throws GLib.Error {
            throw not_mapped ("absence reporting");
        }
        public async void create_absence_reason (int[] server_ids,
                                                 string[] timetable_ids,
                                                 string reason) throws GLib.Error {
            throw not_mapped ("absence reasons");
        }
        public async void student_call_in_sick (string reason, int type,
                                                out int code, out string message)
            throws GLib.Error {
            code = 0;
            message = "";
            throw not_mapped ("call in sick");
        }
    }
}
