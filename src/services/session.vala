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

        /* After the fast general data (grades/profile/settings). */
        public signal void updated ();
        /* After the (separately, often slowly fetched) timetable. */
        public signal void timetable_updated ();
        /* After the absence summary + events. */
        public signal void absence_updated ();

        /* False until the first timetable fetch settles, so widgets can show a
         * spinner instead of an empty "no lessons" state while it loads. */
        public bool timetable_loaded { get; private set; default = false; }

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

        /* The fast critical data the shell needs to paint: grades, profile and
         * the edit settings. Never throws.
         *
         * These three are independent, so they're fetched concurrently over the
         * shared Soup session (which the splash waits on): the user waits for
         * the slowest single call, not the sum. The timetable and absence
         * summary are far slower on some backends, so they load separately
         * (refresh_timetable / refresh_absence) and stream into their cards
         * without holding up the first paint. */
        public async void refresh () {
            int64 t0 = get_monotonic_time ();

            SourceFunc resume = refresh.callback;
            int remaining = 3;

            load_grades_data.begin ((o, r) => {
                load_grades_data.end (r);
                if (--remaining == 0) resume ();
            });
            load_user_info.begin ((o, r) => {
                load_user_info.end (r);
                if (--remaining == 0) resume ();
            });
            load_settings.begin ((o, r) => {
                load_settings.end (r);
                if (--remaining == 0) resume ();
            });

            yield;   // resumed once all three loaders report back

            debug ("refresh: critical data in %lld ms",
                   (get_monotonic_time () - t0) / 1000);
            updated ();
        }

        /* The timetable, fetched on its own so a slow GetTimetable doesn't block
         * the first paint. The "Up next" card shows a spinner until this fires. */
        public async void refresh_timetable () {
            int64 t = get_monotonic_time ();
            try {
                var node = yield provider.fetch_timetable ();
                if (node != null && node.get_node_type () == Json.NodeType.ARRAY) {
                    timetable.load (node.get_array ());
                }
            } catch (GLib.Error e) {
                warning ("timetable fetch failed: %s", e.message);
            }
            timetable_loaded = true;
            debug ("refresh: timetable in %lld ms", (get_monotonic_time () - t) / 1000);
            timetable_updated ();
        }

        private async void load_grades_data () {
            int64 t = get_monotonic_time ();
            try {
                var node = yield provider.fetch_grades ();
                load_grades (node);
            } catch (GLib.Error e) {
                warning ("grades fetch failed: %s", e.message);
            }
            debug ("refresh: grades in %lld ms", (get_monotonic_time () - t) / 1000);
        }

        private async void load_settings () {
            int64 t = get_monotonic_time ();
            try {
                var node = yield provider.fetch_user_info_settings ();
                if (node != null && node.get_node_type () == Json.NodeType.OBJECT) {
                    user_settings = (UserInfoSettings) Json.gobject_deserialize (
                        typeof (UserInfoSettings), node);
                }
            } catch (GLib.Error e) {
                warning ("user info settings fetch failed: %s", e.message);
            }
            debug ("refresh: settings in %lld ms", (get_monotonic_time () - t) / 1000);
        }

        /* Re-fetch just the profile (GetUserInfo) into user_info. Best effort —
         * a failed fetch leaves the previous value in place. Shared by the
         * initial refresh() and the picture-change helpers. */
        private async void load_user_info () {
            int64 t = get_monotonic_time ();
            try {
                var node = yield provider.fetch_user_info (username);
                if (node != null && node.get_node_type () == Json.NodeType.OBJECT) {
                    user_info = (UserInfoItem) Json.gobject_deserialize (
                        typeof (UserInfoItem), node);
                }
            } catch (GLib.Error e) {
                warning ("user info fetch failed: %s", e.message);
            }
            debug ("refresh: user info in %lld ms", (get_monotonic_time () - t) / 1000);
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
            if (user_info == null) {
                return null;
            }
            debug ("avatar: pending='%s' approved='%s' picture='%s' -> '%s'",
                   user_info.pending_picture_url, user_info.approved_picture_url,
                   user_info.picture_url, user_info.best_picture_url);
            if (user_info.best_picture_url == "") {
                return null;
            }
            return yield AvatarCache.load (provider, user_info.best_picture_url);
        }

        /* Upload a new profile picture; on success re-pull the profile so the
         * pending picture/banner state updates. The avatar itself refreshes via
         * load_avatar (network-first), so no cache eviction is needed. Returns
         * true on success. */
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
            int64 t = get_monotonic_time ();
            try {
                var node = yield provider.fetch_absence ();
                parse_absence (node);
            } catch (GLib.Error e) {
                warning ("absence fetch failed: %s", e.message);
            }
            debug ("refresh: absence in %lld ms", (get_monotonic_time () - t) / 1000);
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
