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

        public UmsProvider (School school, string device_name, string device_id) {
            this._school = school;
            this.client = new UmsClient (school.base_url);
            this.device_name = device_name;
            this.device_id = device_id;
        }

        /* The current Bearer token (after login or resume). */
        public string token { owned get { return client.token; } }

        /* The AppSettings subtree from the last fresh login (null after a
         * token-resume). The caller curates + caches the safe parts. */
        public Json.Node? app_settings { owned get { return client.app_settings; } }

        /* When the token expires (unix seconds), or 0 if unknown. Set by login. */
        public int64 token_expires_at { get { return client.token_expires_at; } }

        public async bool login (string username, string password) throws GLib.Error {
            yield client.authenticate (username, password,
                                       school.login_type, school.auth_type,
                                       device_name, device_id);
            return true;
        }

        /* Resume with a previously saved token — no network call. */
        public void resume (string token) {
            client.token = token;
        }

        /* Invalidate the token server-side. Best effort — the caller logs out
         * locally regardless. */
        public async void logout () throws GLib.Error {
            yield client.post ("/Login/DeleteToken");
        }

        public async Json.Node? fetch_timetable () throws GLib.Error {
            return yield client.get_json (
                "/Timetable/GetTimetable?language=" + school.language, "2");
        }

        public async Json.Node? fetch_absence () throws GLib.Error {
            return yield client.get_json (
                "/Absence/GetUserAbsence?language=" + school.language, "2");
        }

        public async Json.Node? fetch_grades () throws GLib.Error {
            return yield client.get_json ("/Grades/GetGrades", "2");
        }

        public async Json.Node? fetch_user_info (string username) throws GLib.Error {
            return yield client.get_json (
                "/UserInfo/GetUserInfo/" + UmsClient.base64url (username), "2");
        }

        public async Json.Node? fetch_user_info_settings () throws GLib.Error {
            return yield client.get_json ("/UserInfo/GetUserInfoSettings", "2");
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

            yield client.post_void ("/UserInfo/UpdateUserInfo", gen.to_data (null), "2");
            return true;
        }

        public async bool update_user_image (GLib.Bytes image) throws GLib.Error {
            yield client.post_multipart ("/UserInfo/UpdateUserImage",
                "profilepicture", "profilepicture.jpg", "image/jpeg", image, "2");
            return true;
        }

        public async bool delete_pending_image () throws GLib.Error {
            yield client.post_action ("/UserInfo/DeletePendingImage", "2");
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
                "/Absence/CreateFutureStudentAbsence", body, "2");
            // 200 returns a bare number — the new absence id.
            return (int) result.get_int ();
        }

        public async Json.Node? fetch_future_absence () throws GLib.Error {
            return yield client.get_json ("/Absence/GetFutureStudentAbsence", "2");
        }

        public async void update_future_absence (int id, string reason,
                                                 string start_iso, string end_iso)
            throws GLib.Error {
            // SLI_ID is ignored by the backend on update; only ID is honoured.
            string body = future_absence_body (id, 0, reason, start_iso, end_iso, current_utc_iso8601_time ());
            yield client.put_void ("/Absence/UpdateFutureStudentAbsence", body, "2");
        }

        public async void delete_future_absence (int id) throws GLib.Error {
            yield client.delete_void (
                "/Absence/DeleteFutureStudentAbsence?ID=%d".printf (id), "2");
        }

        public async Json.Node? fetch_absence_settings () throws GLib.Error {
            return yield client.get_json (
                "/Absence/GetAbsenceSettings?language=" + school.language, "2");
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
            yield client.post_json ("/Absence/CreateAbsenceReason", b64, "2");
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
            var result = yield client.post_json ("/Absence/StudentCallInSick", b64, "2");

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
