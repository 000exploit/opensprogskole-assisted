/* demo-provider.vala
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

    /* A credential-free provider that serves believable canned data with no
     * network. Used for "try the app" and for screenshots/design checks. Builds
     * models directly (no JSON, no cache), which the typed-model interface makes
     * trivial. */
    public class DemoProvider : GLib.Object, SchoolProvider {

        private School _school;
        public School school { get { return _school; } }
        public int64 token_expires_at { get { return 0; } }

        public DemoProvider (School school) {
            this._school = school;
        }

        // --- Auth: nothing to do ------------------------------------------------
        public void use_account (string username, Storage storage) {}   // canned data

        public async GLib.GenericArray<LoginMethod> login_methods () throws GLib.Error {
            var list = new GLib.GenericArray<LoginMethod> ();
            list.add (LoginMethod.none ());
            return list;
        }

        public async void authenticate (LoginMethod method, GLib.Variant credentials,
                                        GLib.Cancellable? cancellable = null) throws GLib.Error {}

        public async void resume (GLib.Variant saved) throws GLib.Error {}

        public GLib.Variant session_secret {
            owned get { return new GLib.VariantDict ().end (); }
        }

        public void abort_requests () {}

        // --- Data ---------------------------------------------------------------
        public async GLib.GenericArray<TimetableItem> load_timetable () throws GLib.Error {
            var items = new GLib.GenericArray<TimetableItem> ();
            var today = new DateTime.now_local ();
            var y = today.add_days (-1);
            var t = today.add_days (1);

            // Yesterday — one attended, one absent (with a reason) to show dots.
            items.add (lesson (y, 8, 15, 9, 45, "Dansk DU2", "MAL", "201", "y1", 0, ""));
            items.add (lesson (y, 10, 0, 11, 30, "Branchedansk", "AKH", "112", "y2", 3,
                               "Jeg var syg."));
            // Today — upcoming.
            items.add (lesson (today, 8, 15, 9, 45, "Dansk DU2", "MAL", "201", "d1", 0, ""));
            items.add (lesson (today, 10, 0, 11, 30, "Udtale", "BSK", "203", "d2", 0, ""));
            items.add (lesson (today, 12, 0, 13, 30, "Grammatik", "MAL", "201", "d3", 0, ""));
            // Tomorrow.
            items.add (lesson (t, 8, 15, 9, 45, "Dansk DU2", "MAL", "201", "t1", 0, ""));
            items.add (lesson (t, 10, 0, 11, 30, "Branchedansk", "AKH", "112", "t2", 0, ""));
            return items;
        }

        public async GLib.GenericArray<GradeItem> load_grades () throws GLib.Error {
            var items = new GLib.GenericArray<GradeItem> ();
            items.add (grade ("Dansk", "Modultest 4", "10", GradeTone.SUCCESS, "2026-05-28T00:00:00"));
            items.add (grade ("Dansk", "Modultest 3", "7", GradeTone.ACCENT, "2026-03-14T00:00:00"));
            items.add (grade ("Branchedansk", "Mundtlig", "Bestået", GradeTone.SUCCESS, "2026-02-02T00:00:00"));
            return items;
        }

        public async AbsenceData load_absence () throws GLib.Error {
            var data = new AbsenceData ();
            data.items.add (absence ("y2", "Branchedansk", "Jeg var syg.", 1, 10, 0, 11, 30, 3));
            data.items.add (absence ("old1", "Udtale", "", 7, 13, 0, 14, 30, 1));

            var s = new AbsenceSummary ();
            s.present = 4200;
            s.late = 120;
            s.illegal = 90;
            s.name = display_name ();
            data.summary = s;
            return data;
        }

        public async GLib.GenericArray<FutureAbsenceItem> load_future_absence () throws GLib.Error {
            return new GLib.GenericArray<FutureAbsenceItem> ();
        }

        public async UserInfoItem? load_user_info () throws GLib.Error {
            return new UserInfoItem () {
                first_name = "Alex",
                last_name = "Demo",
                private_mail = "alex.demo@example.org",
                phone_number = "+45 12 34 56 78",
                city = "Horsens",
                zip_code = "8700",
                address = "Skolegade 1",
                birth_day = "120400",   // DDMMYY, as the UMS backend returns it
                department_name = "DU2 — Modul 4"
            };
        }

        public async UserInfoSettings? load_user_info_settings () throws GLib.Error {
            return new UserInfoSettings () {
                phone_number_allow_edit = true,
                private_mail_allow_edit = true,
                private_mobile_phone_allow_edit = true,
                never_receive_sms_allow_edit = true
            };
        }

        public async AbsenceSettings? load_absence_settings () throws GLib.Error {
            return new AbsenceSettings () {
                student_reason_days_back = 3,
                show_absence_reason = true
            };
        }

        public async AppConfig load_app_config () throws GLib.Error {
            var config = new AppConfig ();
            config.links.add (new LinkItem () {
                link_text = "Ordnet", description = "Den Danske Ordbog", url = "https://ordnet.dk/ddo"
            });
            config.links.add (new LinkItem () {
                link_text = "Dansk for dig", description = "", url = "https://danskfordig.dk"
            });
            config.call_in_sick_cutoff = 20 * 60 + 30;   // 20:30
            return config;
        }

        // --- Writes: no-op ------------------------------------------------------
        public async bool update_user_info (UserInfoItem info) throws GLib.Error { return true; }
        public async bool update_user_image (GLib.Bytes image) throws GLib.Error { return true; }
        public async bool delete_pending_image () throws GLib.Error { return true; }
        public async GLib.Bytes? fetch_picture (string url) throws GLib.Error { return null; }
        public async int create_future_absence (string r, string s, string e) throws GLib.Error { return 0; }
        public async void update_future_absence (int id, string r, string s, string e) throws GLib.Error {}
        public async void delete_future_absence (int id) throws GLib.Error {}
        public async void create_absence_reason (int[] sids, string[] tids, string r) throws GLib.Error {}
        public async void student_call_in_sick (string reason, int type,
                                                out int code, out string message) throws GLib.Error {
            code = 0;
            message = _("Reported — see you soon.");
        }

        // --- Builders -----------------------------------------------------------
        private string display_name () {
            return "Alex Demo";
        }

        private TimetableItem lesson (DateTime day, int sh, int sm, int eh, int em,
                                      string subject, string teacher, string room,
                                      string id, int status, string reason) {
            var item = new TimetableItem ();
            item.subject = subject;
            item.start_time = "%02d:%02d".printf (sh, sm);
            item.end_time = "%02d:%02d".printf (eh, em);
            item.teacher = teacher;
            item.location = room;
            item.activity = subject;
            item.timetable_id = id;
            item.admin_server_id = 1;
            item.absence_status = status;
            item.absence_reason = reason;
            item.allow_absence = true;
            item.time_table_real_start_date_time = at (day, sh, sm);
            item.time_table_real_end_date_time = at (day, eh, em);
            item.time_table_real_date = at (day, 0, 0);
            return item;
        }

        private GradeItem grade (string course, string assessment, string value,
                                 GradeTone tone, string due_date) {
            var g = new GradeItem (course, "7-trinsskala", value, tone, due_date);
            g.grade_value = value;
            g.course_short_description = course;
            g.evaluation_form_description = assessment;
            g.apply_danish_scale ();
            return g;
        }

        private AbsenceItem absence (string event_id, string subject, string reason,
                                     int days_ago, int sh, int sm, int eh, int em, int status) {
            var day = new DateTime.now_local ().add_days (-days_ago);
            return new AbsenceItem () {
                event_id = event_id,
                server_id = 1,
                activity_short_description = subject,
                student_reason = reason,
                status = status,
                minutes_absence = 90,
                minutes_total = 90,
                start_date = at (day, 0, 0),
                start_time = at (day, sh, sm),
                end_time = at (day, eh, em)
            };
        }

        private static DateTime at (DateTime day, int hour, int minute) {
            return new DateTime.local (day.get_year (), day.get_month (),
                                       day.get_day_of_month (), hour, minute, 0);
        }
    }
}
