/* ums-provider.vala
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

    /* SchoolProvider implementation for schools on the UMS backend (Sprogcenter
     * Midt and friends). It maps the school-agnostic interface onto UMS routes
     * via a UmsClient; everything above this class stays unaware of UMS. */
    public class UmsProvider : GLib.Object, SchoolProvider {

        // Backing field rather than a construct property, so the accessor matches
        // the interface's read-only `school`.
        private School _school;
        public School school { get { return _school; } }

        private UmsClient client;
        private string device_name;
        private string device_id;
        // Per-account GVDB cache, built in use_account; null until then.
        private Storage? storage = null;
        // The account username (for the GetUserInfo path).
        private string account_username = "";

        public UmsProvider (School school, string device_name, string device_id) {
            this._school = school;
            this.client = new UmsClient (school.base_url);
            this.device_name = device_name;
            this.device_id = device_id;
        }

        public void use_account (string username, Storage storage) {
            account_username = username;
            this.storage = storage;   // the session's shared per-account store
        }

        /* When the token expires (unix seconds), or 0 if unknown. */
        public int64 token_expires_at { get { return client.token_expires_at; } }

        /* Network-first with offline fallback: GET `path`, cache it under `key`,
         * and return the node; on a failed fetch return the cached copy, or
         * rethrow if there's none. The single place the load_* methods get their
         * raw JSON, so each stays a thin fetch + parse. */
        private async Json.Node fetch_cached (string key, string path) throws GLib.Error {
            try {
                var node = yield client.get_json (path, "2");
                if (storage != null) {
                    storage.set_json (key, node);
                }
                return node;
            } catch (GLib.Error e) {
                var cached = storage != null ? storage.get_json (key) : null;
                if (cached != null) {
                    warning ("%s fetch failed, using cache: %s", key, e.message);
                    return cached;
                }
                throw e;
            }
        }

        /* The methods this instance accepts, from the school's static config. UMS
         * has three (plain username/password+JWT, AzureAD, a second SSO variant);
         * only password is wired — the SSO ones are an OAuth slot, labelled "SSO". */
        public async GLib.GenericArray<LoginMethod> login_methods () throws GLib.Error {
            var list = new GLib.GenericArray<LoginMethod> ();
            foreach (string id in school.login_methods) {
                switch (id) {
                    case "password":
                        list.add (LoginMethod.password ());
                        break;
                    case "sso":
                        list.add (new LoginMethod ("sso", LoginKind.OAUTH,
                                                   _("SSO"), "network-workgroup-symbolic"));
                        break;
                    default:
                        break;
                }
            }
            if (list.length == 0) {
                list.add (LoginMethod.password ());
            }
            return list;
        }

        public async void authenticate (LoginMethod method, GLib.Variant credentials,
                                        GLib.Cancellable? cancellable = null)
            throws GLib.Error {
            if (method.kind == LoginKind.PASSWORD) {
                string username = field (credentials, "username");
                string password = field (credentials, "password");
                yield client.authenticate (username, password,
                                           school.login_type, school.auth_type,
                                           device_name, device_id);
                return;
            }
            throw new UmsError.HTTP ("SSO sign-in is not implemented yet");
        }

        /* Resume from a stored {token} secret — no network call; the controller
         * has already checked the saved expiry. */
        public async void resume (GLib.Variant saved) throws GLib.Error {
            string token = field (saved, "token");
            client.token = token;
            client.token_expires_at = UmsClient.decode_jwt_exp (token);
        }

        /* A string entry of an a{sv}/a{ss} credential or secret Variant, or "" if
         * absent — the varargs lookup leaves its out value null on a miss, so we
         * read it as a typed value instead. Keeps the empty-string contract that
         * the auth path and keyring round-trip depend on. */
        private static string field (GLib.Variant v, string key) {
            var entry = new GLib.VariantDict (v).lookup_value (key, GLib.VariantType.STRING);
            return entry != null ? entry.get_string () : "";
        }

        public GLib.Variant session_secret {
            owned get {
                var b = new GLib.VariantDict ();
                b.insert_value ("token", new GLib.Variant.string (client.token));
                return b.end ();
            }
        }

        /* Invalidate the token server-side. Best effort — the caller logs out
         * locally regardless. */
        public async void logout () throws GLib.Error {
            yield client.post (UmsEndpoints.DELETE_TOKEN);
        }

        public async GLib.GenericArray<TimetableItem> load_timetable () throws GLib.Error {
            var node = yield fetch_cached ("timetable",
                UmsEndpoints.GET_TIMETABLE + "?language=" + school.language);
            if (node.get_node_type () != Json.NodeType.ARRAY) {
                throw new UmsError.MALFORMED ("timetable is not an array");
            }
            return TimetableItem.from_json_array (node.get_array ());
        }

        public async GLib.GenericArray<GradeItem> load_grades () throws GLib.Error {
            var node = yield fetch_cached ("grades", UmsEndpoints.GET_GRADES);
            if (node.get_node_type () != Json.NodeType.ARRAY) {
                throw new UmsError.MALFORMED ("grades is not an array");
            }
            var items = new GLib.GenericArray<GradeItem> ();
            node.get_array ().foreach_element ((arr, i, element) => {
                var g = (GradeItem) Json.gobject_deserialize (typeof (GradeItem), element);
                g.apply_danish_scale ();
                items.add (g);
            });
            items.sort ((a, b) => strcmp (b.due_date, a.due_date));   // newest first
            return items;
        }

        public async AbsenceData load_absence () throws GLib.Error {
            var node = yield fetch_cached ("absence",
                UmsEndpoints.GET_USER_ABSENCE + "?language=" + school.language);
            if (node.get_node_type () != Json.NodeType.OBJECT) {
                throw new UmsError.MALFORMED ("absence is not an object");
            }
            var obj = node.get_object ();
            var data = new AbsenceData ();

            if (obj.has_member ("StudentRegisteredAbsence")) {
                obj.get_array_member ("StudentRegisteredAbsence").foreach_element ((arr, i, element) => {
                    data.items.add ((AbsenceItem) Json.gobject_deserialize (
                        typeof (AbsenceItem), element));
                });
                data.items.sort ((a, b) => {
                    var da = a.start_time;
                    var db = b.start_time;
                    return (da == null || db == null) ? 0 : db.compare (da);   // newest first
                });
            }
            if (obj.has_member ("StudentAbsence")
                && obj.get_member ("StudentAbsence").get_node_type () == Json.NodeType.OBJECT) {
                data.summary = (AbsenceSummary) Json.gobject_deserialize (
                    typeof (AbsenceSummary), obj.get_member ("StudentAbsence"));
            }
            return data;
        }

        public async UserInfoItem? load_user_info () throws GLib.Error {
            var node = yield fetch_cached ("user-info",
                UmsEndpoints.GET_USER_INFO + "/" + UmsClient.base64url (account_username));
            return node.get_node_type () == Json.NodeType.OBJECT
                ? (UserInfoItem) Json.gobject_deserialize (typeof (UserInfoItem), node)
                : null;
        }

        public async UserInfoSettings? load_user_info_settings () throws GLib.Error {
            // Not cached (matches prior behaviour — it gates edit-field visibility).
            var node = yield client.get_json (UmsEndpoints.GET_USER_INFO_SETTINGS, "2");
            return node.get_node_type () == Json.NodeType.OBJECT
                ? (UserInfoSettings) Json.gobject_deserialize (typeof (UserInfoSettings), node)
                : null;
        }

        /* UpdateUserInfo accepts exactly the editable fields. We send the current
         * value of each from `info`, so the caller only has to mutate what
         * changed (a flipped SMS switch, an edited e-mail) before calling. */
        public async bool update_user_info (UserInfoItem info) throws GLib.Error {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("PrivateMail"); b.add_string_value (info.private_mail);
            b.set_member_name ("WorkMail"); b.add_string_value (info.work_mail);
            b.set_member_name ("WorkPhoneNumber"); b.add_string_value (info.work_phone_number);
            b.set_member_name ("PhoneNumber"); b.add_string_value (info.phone_number);
            b.set_member_name ("PrivateMobilePhone"); b.add_string_value (info.private_mobile_phone);
            b.set_member_name ("WorkMobilePhone"); b.add_string_value (info.work_mobile_phone);
            b.set_member_name ("OtherInfo"); b.add_string_value (info.other_info);
            b.set_member_name ("NeverReceiveSms"); b.add_boolean_value (info.never_receive_sms);
            b.set_member_name ("PicturePrivacySetting"); b.add_int_value (info.picture_privacy_setting);
            b.end_object ();

            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());

            yield client.post_void (UmsEndpoints.UPDATE_USER_INFO, gen.to_data (null), "2");
            return true;
        }

        public async bool update_user_image (GLib.Bytes image) throws GLib.Error {
            yield client.post_multipart (UmsEndpoints.UPDATE_USER_IMAGE,
                "profilepicture", "profilepicture.jpg", "image/jpeg", image, "2");
            return true;
        }

        public async bool delete_pending_image () throws GLib.Error {
            yield client.post_action (UmsEndpoints.DELETE_PENDING_IMAGE, "2");
            return true;
        }

        public void abort_requests () {
            client.abort ();
        }

        public async GLib.Bytes? fetch_picture (string url) throws GLib.Error {
            if (url.has_prefix ("http")) {
                return yield client.fetch_picture (url);
            }
            // Relative URL: resolve against the host origin, not the /api base.
            string origin = school.base_url.has_suffix ("/api")
                ? school.base_url.substring (0, school.base_url.length - 4)
                : school.base_url;
            return yield client.fetch_picture (
                origin + (url.has_prefix ("/") ? url : "/" + url));
        }

        public async int create_future_absence (string reason, string start_iso,
                                                string end_iso) throws GLib.Error {
            string body = future_absence_body (0, 0, reason, start_iso, end_iso, current_utc_iso8601_time ());
            var result = yield client.post_json (
                UmsEndpoints.CREATE_FUTURE_ABSENCE, body, "2");
            // 200 returns a bare number — the new absence id.
            return (int) result.get_int ();
        }

        public async GLib.GenericArray<FutureAbsenceItem> load_future_absence () throws GLib.Error {
            // Not cached (matches prior behaviour); any successful fetch counts as
            // loaded, even an empty/odd one — only a network failure throws.
            var node = yield client.get_json (UmsEndpoints.GET_FUTURE_ABSENCE, "2");
            var items = new GLib.GenericArray<FutureAbsenceItem> ();
            if (node.get_node_type () == Json.NodeType.ARRAY) {
                node.get_array ().foreach_element ((arr, i, element) => {
                    var item = FutureAbsenceItem.from_json (element);
                    if (item != null) {
                        items.add (item);
                    }
                });
                items.sort ((a, b) => {
                    var da = a.start_date_time;
                    var db = b.start_date_time;
                    return (da == null || db == null) ? 0 : db.compare (da);   // newest first
                });
            }
            return items;
        }

        public async void update_future_absence (int id, string reason,
                                                 string start_iso, string end_iso)
            throws GLib.Error {
            // SLI_ID is ignored by the backend on update; only ID is honoured.
            string body = future_absence_body (id, 0, reason, start_iso, end_iso, current_utc_iso8601_time ());
            yield client.put_void (UmsEndpoints.UPDATE_FUTURE_ABSENCE, body, "2");
        }

        public async void delete_future_absence (int id) throws GLib.Error {
            yield client.delete_void (
                UmsEndpoints.DELETE_FUTURE_ABSENCE + "?ID=%d".printf (id), "2");
        }

        public async AbsenceSettings? load_absence_settings () throws GLib.Error {
            // Not cached (it gates "describe reason", a write — irrelevant offline).
            var node = yield client.get_json (
                UmsEndpoints.GET_ABSENCE_SETTINGS + "?language=" + school.language, "2");
            return node.get_node_type () == Json.NodeType.OBJECT
                ? (AbsenceSettings) Json.gobject_deserialize (typeof (AbsenceSettings), node)
                : null;
        }

        /* Links + call-in-sick cutoff, from the login AppSettings. On a fresh login
         * the token-free whitelist is captured into the cache so it survives a
         * token-resume restart; the values are then read back from there. */
        public async AppConfig load_app_config () throws GLib.Error {
            var fresh = client.app_settings;
            if (fresh != null && storage != null) {
                var curated = curate_app_settings (fresh);
                if (curated != null) {
                    storage.set_json ("app-settings", curated);
                }
            }

            var config = new AppConfig ();
            var app = storage != null ? storage.get_node ("app-settings") : null;
            if (app != null) {
                foreach (var n in app.get_array ("Links")) {
                    config.links.add (LinkItem.from_node (n));
                }
                var cis = app.get_object ("AbsenceCallInSickSettings");
                if (cis != null) {
                    config.call_in_sick_cutoff =
                        hhmm_to_minutes (cis.get_string ("IgnoreMessageStart"));
                }
            }
            return config;
        }

        /* The token-free slice of the login AppSettings we persist: Links (lifted
         * out of UserVariables) + AbsenceCallInSickSettings, copied so neither the
         * token (a sibling) nor the rest of UserVariables/PushSettings tags along. */
        private static Json.Node? curate_app_settings (Json.Node app_settings) {
            if (app_settings.get_node_type () != Json.NodeType.OBJECT) {
                return null;
            }
            var src = app_settings.get_object ();
            var dst = new Json.Object ();

            if (src.has_member ("UserVariables")
                && src.get_member ("UserVariables").get_node_type () == Json.NodeType.OBJECT) {
                var uv = src.get_object_member ("UserVariables");
                if (uv.has_member ("Links")) {
                    dst.set_member ("Links", uv.get_member ("Links").copy ());
                }
            }
            if (src.has_member ("AbsenceCallInSickSettings")) {
                dst.set_member ("AbsenceCallInSickSettings",
                                src.get_member ("AbsenceCallInSickSettings").copy ());
            }

            if (dst.get_size () == 0) {
                return null;
            }
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (dst);
            return node;
        }

        /* CreateAbsenceReason wants a base64-encoded JSON *array* of lesson-shaped
         * objects, but only these three members matter per entry; the server fills
         * the rest. One entry per lesson lets a single reason cover a whole day. */
        public async void create_absence_reason (int[] server_ids, string[] timetable_ids,
                                                 string reason) throws GLib.Error {
            var b = new Json.Builder ();
            b.begin_array ();
            for (int i = 0; i < timetable_ids.length; i++) {
                b.begin_object ();
                b.set_member_name ("AdminServerId"); b.add_int_value (server_ids[i]);
                b.set_member_name ("TimetableId"); b.add_string_value (timetable_ids[i]);
                b.set_member_name ("AbsenceReason"); b.add_string_value (reason);
                b.end_object ();
            }
            b.end_array ();

            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());

            // The endpoint reads the JSON from a base64 text body (content-type
            // still application/json). Response is the JSON string confirmation.
            string b64 = GLib.Base64.encode (gen.to_data (null).data);
            yield client.post_json (UmsEndpoints.CREATE_ABSENCE_REASON, b64, "2");
        }

        public async void student_call_in_sick (string reason, int type,
                                                out int code, out string message)
            throws GLib.Error {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("AbsenceReason"); b.add_string_value (reason);
            b.set_member_name ("AbsenceType"); b.add_int_value (type);
            b.end_object ();

            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());

            string b64 = GLib.Base64.encode (gen.to_data (null).data);
            var result = yield client.post_json (UmsEndpoints.CALL_IN_SICK, b64, "2");

            code = 0;
            message = "";
            if (result.get_node_type () == Json.NodeType.OBJECT) {
                var obj = result.get_object ();
                code = (int) obj.get_int_member_with_default ("Code", 0);
                message = obj.get_string_member_with_default ("Message", "");
            }
        }

        /* The shared CreateFutureStudentAbsence/UpdateFutureStudentAbsence body.
         * when_calculated is the server's "computed at" stamp — set to the actual
         * time of the create/update so it doubles as a "last updated" marker. */
        private static string future_absence_body (int id, int sli_id, string reason,
                                                   string start_iso, string end_iso,
                                                   string when_calculated) {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("ID"); b.add_int_value (id);
            b.set_member_name ("SLI_ID"); b.add_int_value (sli_id);
            b.set_member_name ("Reason"); b.add_string_value (reason);
            b.set_member_name ("StartDateTime"); b.add_string_value (start_iso);
            b.set_member_name ("EndDateTime"); b.add_string_value (end_iso);
            b.set_member_name ("WhenCalculated"); b.add_string_value (when_calculated);
            b.end_object ();

            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());
            return gen.to_data (null);
        }
    }
}
