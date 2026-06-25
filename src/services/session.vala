/* session.vala
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
        public UserInfoSettings? user_settings { get; private set; default = null; }
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

            yield load_user_info ();

            try {
                var node = yield provider.fetch_user_info_settings ();
                if (node != null && node.get_node_type () == Json.NodeType.OBJECT) {
                    user_settings = (UserInfoSettings) Json.gobject_deserialize (
                        typeof (UserInfoSettings), node);
                }
            } catch (GLib.Error e) {
                warning ("user info settings fetch failed: %s", e.message);
            }

            updated ();
        }

        /* Re-fetch just the profile (GetUserInfo) into user_info. Best effort —
         * a failed fetch leaves the previous value in place. Shared by the
         * initial refresh() and the picture-change helpers. */
        private async void load_user_info () {
            try {
                var node = yield provider.fetch_user_info (username);
                if (node != null && node.get_node_type () == Json.NodeType.OBJECT) {
                    user_info = (UserInfoItem) Json.gobject_deserialize (
                        typeof (UserInfoItem), node);
                }
            } catch (GLib.Error e) {
                warning ("user info fetch failed: %s", e.message);
            }
        }

        /* Re-pull the profile and notify listeners. Used after a picture change,
         * where the new pending/approved URL only shows up in a fresh fetch. */
        public async void refresh_user_info () {
            yield load_user_info ();
            updated ();
        }

        /* Persist the editable profile fields. The caller mutates user_info
         * first (an edited e-mail, a flipped SMS preference) and, on a thrown
         * error, reverts its UI. On success listeners refresh via updated(). */
        public async bool save_user_info () throws GLib.Error {
            if (user_info == null) {
                return false;
            }
            bool ok = yield provider.update_user_info (user_info);
            if (ok) {
                updated ();
            }
            return ok;
        }

        /* The profile picture as a paintable (downloaded + cached), or null when
         * there is none — the caller then shows initials. */
        public async Gdk.Paintable? load_avatar () {
            if (user_info == null || user_info.best_picture_url == "") {
                return null;
            }
            return yield AvatarCache.load (provider, user_info.best_picture_url);
        }

        /* Upload a new profile picture; on success re-pull the profile so the
         * pending picture/banner state updates. Returns true on success. */
        public async bool upload_avatar (GLib.Bytes image) throws GLib.Error {
            bool ok = yield provider.update_user_image (image);
            if (ok) {
                yield refresh_user_info ();
            }
            return ok;
        }

        /* Discard the pending profile picture; on success re-pull the profile.
         * Returns true on success. */
        public async bool remove_pending_avatar () throws GLib.Error {
            bool ok = yield provider.delete_pending_image ();
            if (ok) {
                yield refresh_user_info ();
            }
            return ok;
        }

        /* Report a future absence; returns the new id. Refreshes the absence
         * cache on success so the Overview attendance stays current. */
        public async int report_future_absence (string reason, string start_iso,
                                                string end_iso) throws GLib.Error {
            int id = yield provider.create_future_absence (reason, start_iso, end_iso);
            refresh_absence.begin ();
            return id;
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
