/* ums-provider.vala
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

        public async int create_future_absence (string reason, string start_iso,
                                                string end_iso) throws GLib.Error {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("ID"); b.add_int_value (0);
            b.set_member_name ("SLI_ID"); b.add_int_value (0);
            b.set_member_name ("Reason"); b.add_string_value (reason);
            b.set_member_name ("StartDateTime"); b.add_string_value (start_iso);
            b.set_member_name ("EndDateTime"); b.add_string_value (end_iso);
            b.set_member_name ("WhenCalculated"); b.add_string_value ("");
            b.end_object ();

            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());

            var result = yield client.post_json (
                "/Absence/CreateFutureStudentAbsence", gen.to_data (null), "2");
            // 200 returns a bare number — the new absence id.
            return (int) result.get_int ();
        }
    }
}
