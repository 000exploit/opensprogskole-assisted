/* session.vala
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

    /* The authenticated app state for one account: the school, its provider and
     * the in-memory stores the views read from.
     *
     * Loading is split so the window can appear quickly: refresh() pulls the
     * "general" data (timetable, grades, profile) and emits updated();
     * refresh_absence() pulls the heavier absence summary + events separately and
     * emits absence_updated(). Both are best effort — a failed endpoint is
     * logged, not fatal. */
    public class Session : GLib.Object {

        public School school { get; construct; }
        public SchoolProvider provider { get; construct; }
        public string username { get; construct; }

        public TimetableStore timetable { get; default = new TimetableStore (); }
        public GLib.ListStore grades { get; default = new GLib.ListStore (typeof (GradeItem)); }
        public GLib.ListStore absences { get; default = new GLib.ListStore (typeof (AbsenceItem)); }
        public UserInfoItem? user_info { get; private set; default = null; }
        public AbsenceSummary? absence_summary { get; private set; default = null; }

        /* After general data (timetable/grades/profile). */
        public signal void updated ();
        /* After the absence summary + events. */
        public signal void absence_updated ();

        public Session (School school, SchoolProvider provider, string username) {
            Object (school: school, provider: provider, username: username);
        }

        /* Best-effort name for the sidebar/profile. */
        public string display_name {
            owned get {
                if (user_info != null && user_info.full_name != "") {
                    return user_info.full_name;
                }
                return username;
            }
        }

        /* General data shown right after login. Never throws. */
        public async void refresh () {
            try {
                var node = yield provider.fetch_timetable ();
                if (node != null && node.get_node_type () == Json.NodeType.ARRAY) {
                    timetable.load (node.get_array ());
                }
            } catch (GLib.Error e) {
                warning ("timetable fetch failed: %s", e.message);
            }

            try {
                var node = yield provider.fetch_grades ();
                load_grades (node);
            } catch (GLib.Error e) {
                warning ("grades fetch failed: %s", e.message);
            }

            try {
                var node = yield provider.fetch_user_info (username);
                if (node != null && node.get_node_type () == Json.NodeType.OBJECT) {
                    user_info = (UserInfoItem) Json.gobject_deserialize (
                        typeof (UserInfoItem), node);
                }
            } catch (GLib.Error e) {
                warning ("user info fetch failed: %s", e.message);
            }

            updated ();
        }

        /* Absence is fetched on its own so it doesn't slow the first paint. */
        public async void refresh_absence () {
            try {
                var node = yield provider.fetch_absence ();
                parse_absence (node);
            } catch (GLib.Error e) {
                warning ("absence fetch failed: %s", e.message);
            }
            absence_updated ();
        }

        private void parse_absence (Json.Node? node) {
            absences.remove_all ();
            absence_summary = null;
            if (node == null || node.get_node_type () != Json.NodeType.OBJECT) {
                return;
            }
            var obj = node.get_object ();

            if (obj.has_member ("StudentRegisteredAbsence")) {
                var arr = obj.get_array_member ("StudentRegisteredAbsence");
                arr.foreach_element ((a, i, element) => {
                    absences.append (Json.gobject_deserialize (typeof (AbsenceItem), element));
                });
                absences.sort ((a, b) => {
                    var da = ((AbsenceItem) a).start_time;
                    var db = ((AbsenceItem) b).start_time;
                    if (da == null || db == null) {
                        return 0;
                    }
                    return db.compare (da);   // newest first
                });
            }

            if (obj.has_member ("StudentAbsence")
                && obj.get_member ("StudentAbsence").get_node_type () == Json.NodeType.OBJECT) {
                absence_summary = (AbsenceSummary) Json.gobject_deserialize (
                    typeof (AbsenceSummary), obj.get_member ("StudentAbsence"));
            }
        }

        private void load_grades (Json.Node? node) {
            grades.remove_all ();
            if (node == null || node.get_node_type () != Json.NodeType.ARRAY) {
                return;
            }
            node.get_array ().foreach_element ((arr, i, element) => {
                var grade = (GradeItem) Json.gobject_deserialize (typeof (GradeItem), element);
                grade.apply_danish_scale ();
                grades.append (grade);
            });
            grades.sort ((a, b) => {
                return strcmp (((GradeItem) b).due_date, ((GradeItem) a).due_date);
            });
        }
    }
}
