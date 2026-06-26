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

    /* How a single fetched resource is doing: still in flight, done (possibly
     * with empty data), or failed. Lets a card distinguish "loading" from
     * "loaded but empty" from "error". */
    public enum LoadState { LOADING, LOADED, FAILED }

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
        // The student's own editable absences (GetFutureStudentAbsence). Shown on
        // the Absence page with edit/delete actions; the registered ones above are
        // read-only.
        public GLib.ListStore future_absences { get; default = new GLib.ListStore (typeof (FutureAbsenceItem)); }
        public UserInfoItem? user_info { get; private set; default = null; }
        public UserInfoSettings? user_settings { get; private set; default = null; }
        public AbsenceSummary? absence_summary { get; private set; default = null; }

        /* After the fast general data (grades/profile/settings). */
        public signal void updated ();
        /* After the (separately, often slowly fetched) timetable. */
        public signal void timetable_updated ();
        /* After the absence summary + events. */
        public signal void absence_updated ();
        /* After the (separately fetched) editable future absences. */
        public signal void future_absence_updated ();

        /* Per-resource load state, so each card can show a spinner, its content,
         * or an error. FAILED loads are retried when connectivity returns (see
         * retry_failed_loads). Each flips back to LOADING on a (re)fetch and its
         * matching *_updated()/updated() signal fires so the card re-renders. */
        public LoadState timetable_state { get; private set; default = LoadState.LOADING; }
        public LoadState absence_state { get; private set; default = LoadState.LOADING; }
        public LoadState future_absence_state { get; private set; default = LoadState.LOADING; }
        public LoadState grades_state { get; private set; default = LoadState.LOADING; }

        // Per-resource load generation. A loader captures it at the start and only
        // applies its result if it still matches; abort_requests bumps it so a
        // request left stalling on a dead socket can't clobber a later retry when
        // it finally times out.
        private uint timetable_gen = 0;
        private uint absence_gen = 0;
        private uint future_absence_gen = 0;
        private uint grades_gen = 0;

        public Session (School school, SchoolProvider provider, string username) {
            Object (school: school, provider: provider, username: username);
        }

        /* Opaque per-account key for the on-disk JSON cache (see JsonCache), so a
         * different account or school never reads another's cached data. */
        public string cache_account {
            owned get {
                return Checksum.compute_for_string (
                    ChecksumType.SHA256, "%s:%s".printf (school.id, username));
            }
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

            // Show the grades spinner during a retry. On the first load this fires
            // before the shell is bound, so it's a harmless no-op there.
            grades_state = LoadState.LOADING;
            updated ();

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

        /* The slow, streamed-in resources (each paints its own card). Kicked off
         * after the critical data on login, and re-run on their own when the user
         * asks for a manual refresh. */
        public void refresh_streamed () {
            refresh_timetable.begin ();
            refresh_absence.begin ();
            refresh_future_absence.begin ();
        }

        /* A full manual refresh: the critical data plus every streamed card.
         * Used by the sidebar refresh button (enter_session does the equivalent,
         * but yields on the critical part first to gate the shell's first paint). */
        public void refresh_all () {
            refresh.begin ();
            refresh_streamed ();
        }

        /* The timetable, fetched on its own so a slow GetTimetable doesn't block
         * the first paint. The "Up next" card shows a spinner until this fires. */
        public async void refresh_timetable () {
            int64 t = get_monotonic_time ();
            uint gen = ++timetable_gen;
            timetable_state = LoadState.LOADING;
            timetable_updated ();   // spinner (back) on, incl. on a retry

            // Network-first; on failure fall back to the last cached copy so the
            // schedule still shows offline (see JsonCache).
            Json.Node? node = null;
            try {
                node = yield provider.fetch_timetable ();
                if (gen != timetable_gen) {
                    return;   // superseded (dropped + retried) — leave the result
                }
                if (node != null) {
                    JsonCache.save (cache_account, "timetable", node);
                }
            } catch (GLib.Error e) {
                if (gen != timetable_gen) {
                    return;
                }
                warning ("timetable fetch failed: %s", e.message);
                node = JsonCache.load (cache_account, "timetable");
            }

            if (node != null && node.get_node_type () == Json.NodeType.ARRAY) {
                timetable.load (node.get_array ());
                timetable_state = LoadState.LOADED;   // network or cache
            } else {
                timetable_state = LoadState.FAILED;   // no network and no cache
            }
            link_absences ();
            debug ("refresh: timetable in %lld ms", (get_monotonic_time () - t) / 1000);
            timetable_updated ();
        }

        private async void load_grades_data () {
            int64 t = get_monotonic_time ();
            uint gen = ++grades_gen;
            try {
                var node = yield provider.fetch_grades ();
                if (gen != grades_gen) {
                    return;
                }
                load_grades (node);
                grades_state = LoadState.LOADED;
            } catch (GLib.Error e) {
                if (gen != grades_gen) {
                    return;
                }
                warning ("grades fetch failed: %s", e.message);
                grades_state = LoadState.FAILED;
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

            // Network-first; on failure use the last cached profile so the page
            // still renders offline.
            Json.Node? node = null;
            try {
                node = yield provider.fetch_user_info (username);
                if (node != null) {
                    JsonCache.save (cache_account, "user-info", node);
                }
            } catch (GLib.Error e) {
                warning ("user info fetch failed: %s", e.message);
                node = JsonCache.load (cache_account, "user-info");
            }

            if (node != null && node.get_node_type () == Json.NodeType.OBJECT) {
                user_info = (UserInfoItem) Json.gobject_deserialize (
                    typeof (UserInfoItem), node);
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

        /* Report a future absence; returns the new id. Refreshes both absence
         * lists on success so the page and Overview attendance stay current. */
        public async int report_future_absence (string reason, string start_iso,
                                                string end_iso) throws GLib.Error {
            int id = yield provider.create_future_absence (reason, start_iso, end_iso);
            refresh_after_absence_change ();
            return id;
        }

        /* Edit an existing future absence (the backend's way to change any
         * absence). Refreshes both lists on success. */
        public async void update_future_absence (int id, string reason,
                                                 string start_iso, string end_iso)
            throws GLib.Error {
            yield provider.update_future_absence (id, reason, start_iso, end_iso);
            refresh_after_absence_change ();
        }

        /* Remove a future absence. Refreshes both lists on success. */
        public async void delete_future_absence (int id) throws GLib.Error {
            yield provider.delete_future_absence (id);
            refresh_after_absence_change ();
        }

        private void refresh_after_absence_change () {
            refresh_future_absence.begin ();
            refresh_absence.begin ();
        }

        /* The whole-day absence window for a "today" report, derived from that
         * day's lessons: StartDateTime = first lesson start, EndDateTime = last
         * lesson end (the backend only accepts the full lesson span). The school
         * day ends at 20:30 local — past that the report rolls over to tomorrow.
         * Returns false when the target day has no lessons, since the backend
         * rejects a report with no lessons to attach it to. */
        public bool today_absence_window (out string start_iso, out string end_iso,
                                          out DateTime day) {
            start_iso = "";
            end_iso = "";
            var now = new DateTime.now_local ();
            // After 20:30 the day is done; report for tomorrow instead.
            day = (now.get_hour () > 20 || (now.get_hour () == 20 && now.get_minute () >= 30))
                ? now.add_days (1) : now;

            var store = timetable.get_day_for_key (day.format ("%Y-%m-%d"));
            if (store == null || store.get_n_items () == 0) {
                return false;
            }

            DateTime? first = null;
            DateTime? last = null;
            for (uint i = 0; i < store.get_n_items (); i++) {
                var item = (TimetableItem) store.get_item (i);
                if (item.start_datetime != null
                    && (first == null || item.start_datetime.compare (first) < 0)) {
                    first = item.start_datetime;
                }
                if (item.end_datetime != null
                    && (last == null || item.end_datetime.compare (last) > 0)) {
                    last = item.end_datetime;
                }
            }
            if (first == null || last == null) {
                return false;
            }
            start_iso = first.format ("%Y-%m-%dT%H:%M:%S");
            end_iso = last.format ("%Y-%m-%dT%H:%M:%S");
            return true;
        }

        /* The editable future absences, fetched on their own (own card state) so
         * a slow call doesn't hold up the page. */
        public async void refresh_future_absence () {
            int64 t = get_monotonic_time ();
            uint gen = ++future_absence_gen;
            future_absence_state = LoadState.LOADING;
            future_absence_updated ();
            try {
                var node = yield provider.fetch_future_absence ();
                if (gen != future_absence_gen) {
                    return;
                }
                parse_future_absence (node);
                future_absence_state = LoadState.LOADED;
            } catch (GLib.Error e) {
                if (gen != future_absence_gen) {
                    return;
                }
                warning ("future absence fetch failed: %s", e.message);
                future_absence_state = LoadState.FAILED;
            }
            debug ("refresh: future absence in %lld ms", (get_monotonic_time () - t) / 1000);
            future_absence_updated ();
        }

        /* Absence is fetched on its own so it doesn't slow the first paint. */
        public async void refresh_absence () {
            int64 t = get_monotonic_time ();
            uint gen = ++absence_gen;
            absence_state = LoadState.LOADING;
            absence_updated ();   // spinner (back) on, incl. on a retry
            try {
                var node = yield provider.fetch_absence ();
                if (gen != absence_gen) {
                    return;
                }
                parse_absence (node);
                absence_state = LoadState.LOADED;
            } catch (GLib.Error e) {
                if (gen != absence_gen) {
                    return;
                }
                warning ("absence fetch failed: %s", e.message);
                absence_state = LoadState.FAILED;
            }
            link_absences ();
            debug ("refresh: absence in %lld ms", (get_monotonic_time () - t) / 1000);
            absence_updated ();
        }

        /* Stamp each lesson with its attendance by matching the absence records'
         * EventId to the lesson's TimetableId. Runs after either the timetable or
         * the absence loads; the notifying `attendance` property updates the dots
         * live. Skipped until absence is genuinely loaded (e.g. offline, where it
         * isn't cached) so dots stay at their category colour rather than guessing.
         *
         * Future lessons are always left UNKNOWN — a reported (future) absence
         * must not paint a dot before the lesson has even happened. */
        /* Link each lesson to its registered-absence record, matched by
         * TimetableId <-> EventId, once the absence list is loaded. This gives a
         * lesson the details the timetable omits (e.g. StudentReason) and is the
         * groundwork for absence actions on a lesson. The dot colour does NOT
         * depend on this — it's derived from the lesson's own AbsenceStatus — so
         * offline (absence uncached) only loses the details, not the dots.
         * Re-run after either list (re)loads. */
        private void link_absences () {
            if (absence_state != LoadState.LOADED) {
                return;
            }
            var by_event = new GLib.HashTable<string, AbsenceItem> (str_hash, str_equal);
            for (uint i = 0; i < absences.get_n_items (); i++) {
                var a = (AbsenceItem) absences.get_item (i);
                if (a.event_id != "") {
                    by_event.set (a.event_id, a);
                }
            }

            timetable.foreach_lesson ((item) => {
                item.absence = by_event.lookup (item.timetable_id);
            });
        }

        /* Connectivity lost: tell the cards now instead of leaving them spinning
         * until the doomed requests time out. We can't actually unstick a request
         * blocked on a dead socket (see UmsClient.abort), so we flip each loading
         * resource to FAILED here and bump its generation — the stalled request,
         * whenever it finally returns, sees the newer generation and drops its
         * result. retry_failed_loads picks these up on reconnect. */
        public void abort_requests () {
            provider.abort_requests ();

            if (timetable_state == LoadState.LOADING) {
                timetable_gen++;
                timetable_state = LoadState.FAILED;
                timetable_updated ();
            }
            if (absence_state == LoadState.LOADING) {
                absence_gen++;
                absence_state = LoadState.FAILED;
                absence_updated ();
            }
            if (future_absence_state == LoadState.LOADING) {
                future_absence_gen++;
                future_absence_state = LoadState.FAILED;
                future_absence_updated ();
            }
            if (grades_state == LoadState.LOADING) {
                grades_gen++;
                grades_state = LoadState.FAILED;
                updated ();
            }
        }

        /* Re-attempt only the loads that failed — called when connectivity comes
         * back (see SessionController). Each retried load flips its card to a
         * spinner, then to content or back to an error. */
        public bool retry_failed_loads () {
            bool any = false;
            if (grades_state == LoadState.FAILED) {
                refresh.begin ();
                any = true;
            }
            if (timetable_state == LoadState.FAILED) {
                refresh_timetable.begin ();
                any = true;
            }
            if (absence_state == LoadState.FAILED) {
                refresh_absence.begin ();
                any = true;
            }
            if (future_absence_state == LoadState.FAILED) {
                refresh_future_absence.begin ();
                any = true;
            }
            return any;   // true while something still needs a (re)try
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

        private void parse_future_absence (Json.Node? node) {
            future_absences.remove_all ();
            if (node == null || node.get_node_type () != Json.NodeType.ARRAY) {
                return;
            }
            node.get_array ().foreach_element ((arr, i, element) => {
                var item = FutureAbsenceItem.from_json (element);
                if (item != null) {
                    future_absences.append (item);
                }
            });
            future_absences.sort ((a, b) => {
                var da = ((FutureAbsenceItem) a).start_date_time;
                var db = ((FutureAbsenceItem) b).start_date_time;
                if (da == null || db == null) {
                    return 0;
                }
                return db.compare (da);   // newest first
            });
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
