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
     * Session only *orchestrates*: it holds the stores, the per-resource load
     * state and the signals, and asks the provider for ready models. The provider
     * owns the transport, the parsing and the offline cache (see SchoolProvider),
     * so Session never touches a school's wire format. */
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
        // The school's external links, from the provider's cached login config.
        public GLib.ListStore links { get; default = new GLib.ListStore (typeof (LinkItem)); }
        public UserInfoItem? user_info { get; private set; default = null; }
        public UserInfoSettings? user_settings { get; private set; default = null; }
        public AbsenceSummary? absence_summary { get; private set; default = null; }
        // How many days back the school still lets a student describe an absence
        // reason (0 ⇒ disabled). Gates can_describe.
        public int student_reason_days_back { get; private set; default = 0; }
        // Whether the school shows absence reasons to students (gates the reason
        // row in the lesson dialog).
        public bool show_absence_reason { get; private set; default = false; }
        // Daily call-in-sick cutoff (minutes since midnight) from the provider's
        // login config; -1 until loaded, then DEFAULT_CALL_IN_SICK_CUTOFF if none.
        private int call_in_sick_cutoff = -1;
        private const int DEFAULT_CALL_IN_SICK_CUTOFF = 20 * 60 + 30;   // 20:30

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
            // Let the provider build its per-account cache before any load.
            provider.use_account (username);
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

        /* The fast critical data the shell needs to paint: app config (links +
         * cutoff), grades, profile and the edit settings. Never throws. The
         * three network loads run concurrently; the timetable and absence stream
         * in separately (refresh_timetable / refresh_absence). */
        public async void refresh () {
            int64 t0 = get_monotonic_time ();

            // Links + call-in-sick cutoff from the provider's cached login config
            // (local + fast), loaded before the shell binds the Links page.
            try {
                var cfg = yield provider.load_app_config ();
                links.remove_all ();
                for (uint i = 0; i < cfg.links.length; i++) {
                    links.append (cfg.links[i]);
                }
                call_in_sick_cutoff = cfg.call_in_sick_cutoff;
            } catch (GLib.Error e) {
                warning ("app config load failed: %s", e.message);
            }

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
            try {
                var items = yield provider.load_timetable ();
                if (gen != timetable_gen) {
                    return;   // superseded (dropped + retried) — leave the result
                }
                timetable.load_items (items);
                timetable_state = LoadState.LOADED;
            } catch (GLib.Error e) {
                if (gen != timetable_gen) {
                    return;
                }
                warning ("timetable load failed: %s", e.message);
                timetable_state = LoadState.FAILED;   // keep any previous content
            }
            link_absences ();
            debug ("refresh: timetable in %lld ms", (get_monotonic_time () - t) / 1000);
            timetable_updated ();
        }

        private async void load_grades_data () {
            int64 t = get_monotonic_time ();
            uint gen = ++grades_gen;
            try {
                var items = yield provider.load_grades ();
                if (gen != grades_gen) {
                    return;
                }
                grades.remove_all ();
                for (uint i = 0; i < items.length; i++) {
                    grades.append (items[i]);
                }
                grades_state = LoadState.LOADED;
            } catch (GLib.Error e) {
                if (gen != grades_gen) {
                    return;
                }
                warning ("grades load failed: %s", e.message);
                grades.remove_all ();
                grades_state = LoadState.FAILED;
            }
            debug ("refresh: grades in %lld ms", (get_monotonic_time () - t) / 1000);
        }

        private async void load_settings () {
            int64 t = get_monotonic_time ();
            try {
                var s = yield provider.load_user_info_settings ();
                if (s != null) {
                    user_settings = s;
                }
            } catch (GLib.Error e) {
                warning ("user info settings load failed: %s", e.message);
            }
            debug ("refresh: settings in %lld ms", (get_monotonic_time () - t) / 1000);
        }

        /* Re-fetch just the profile (GetUserInfo) into user_info. Best effort —
         * a failed load leaves the previous value in place. Shared by the initial
         * refresh() and the picture-change helpers. */
        private async void load_user_info () {
            int64 t = get_monotonic_time ();
            try {
                var info = yield provider.load_user_info ();
                if (info != null) {
                    user_info = info;
                }
            } catch (GLib.Error e) {
                warning ("user info load failed: %s", e.message);
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

        /* Deliver the profile picture into `sink` — cached copy immediately,
         * a fresh one after revalidation if it changed (see AvatarCache), or
         * null when there is none so the caller shows initials. */
        public async void load_avatar (owned AvatarCache.Sink sink) {
            if (user_info == null || user_info.best_picture_url == "") {
                sink (null);
                return;
            }
            yield AvatarCache.load (provider, user_info.best_picture_url, (owned) sink);
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

        /* Report a future absence; returns the new id. Only the future-absence
         * list changes — a planned absence isn't a registered one — so the
         * (slower) registered-absence list is left alone. */
        public async int report_future_absence (string reason, string start_iso,
                                                string end_iso) throws GLib.Error {
            int id = yield provider.create_future_absence (reason, start_iso, end_iso);
            refresh_future_absence.begin ();
            return id;
        }

        /* Edit an existing future absence (the backend's way to change any
         * absence). Refreshes the future list only. */
        public async void update_future_absence (int id, string reason,
                                                 string start_iso, string end_iso)
            throws GLib.Error {
            yield provider.update_future_absence (id, reason, start_iso, end_iso);
            refresh_future_absence.begin ();
        }

        /* Remove a future absence. Refreshes the future list only. */
        public async void delete_future_absence (int id) throws GLib.Error {
            yield provider.delete_future_absence (id);
            refresh_future_absence.begin ();
        }

        /* Whether a past absent lesson can still have its reason described: the
         * school allows it (window > 0), the lesson was marked absent (status 3 —
         * 'late' is excluded), it already ended, and it falls inside the
         * StudentReasonDaysBack window. Today/future lessons are call-in-sick
         * territory, not this. Shared by the Absence page and the lesson dialog. */
        public bool can_describe (DateTime? end_dt, int status) {
            if (student_reason_days_back <= 0 || status != 3 || end_dt == null) {
                return false;
            }
            var now = new DateTime.now_local ();
            if (end_dt.compare (now) >= 0) {
                return false;   // hasn't ended yet
            }
            // Inclusive, calendar-day window: from the start (midnight) of the
            // StudentReasonDaysBack-th day ago up to now.
            var earliest = new DateTime.local (
                now.get_year (), now.get_month (), now.get_day_of_month (), 0, 0, 0)
                .add_days (-student_reason_days_back);
            return end_dt.compare (earliest) >= 0;
        }

        /* Whether "call in sick" is still available: the backend only accepts it
         * up to a daily cutoff (AbsenceCallInSickSettings.IgnoreMessageStart, e.g.
         * 20:30), falling back to a default when the school sends none. */
        public bool can_call_in_sick () {
            int cutoff = call_in_sick_cutoff >= 0
                ? call_in_sick_cutoff : DEFAULT_CALL_IN_SICK_CUTOFF;
            var now = new DateTime.now_local ();
            return now.get_hour () * 60 + now.get_minute () < cutoff;
        }

        /* Describe (create or edit) the reason for a single past absent lesson. */
        public async void describe_absence (int server_id, string timetable_id,
                                            string reason) throws GLib.Error {
            yield apply_absence_reason ({ server_id }, { timetable_id }, reason);
        }

        /* How many describable absent lessons share `day` — lets a caller decide
         * whether to offer the "whole day" option. */
        public uint describable_count_on (DateTime day) {
            return describable_on (day).length;
        }

        /* Describe every describable absent lesson on `day` with one reason — the
         * "whole day" case, sent as a single multi-entry CreateAbsenceReason. */
        public async void describe_absence_day (DateTime day, string reason)
            throws GLib.Error {
            var targets = describable_on (day);
            if (targets.length == 0) {
                return;
            }
            int[] server_ids = new int[targets.length];
            string[] timetable_ids = new string[targets.length];
            for (uint i = 0; i < targets.length; i++) {
                server_ids[i] = targets[i].admin_server_id;
                timetable_ids[i] = targets[i].timetable_id;
            }
            yield apply_absence_reason (server_ids, timetable_ids, reason);
        }

        /* The describable absent lessons on `day` (the shared predicate behind both
         * the count and the whole-day describe). */
        private GLib.GenericArray<TimetableItem> describable_on (DateTime day) {
            string key = day.format ("%Y-%m-%d");
            var found = new GLib.GenericArray<TimetableItem> ();
            timetable.foreach_lesson ((item) => {
                if (item.date_key == key && item.timetable_id != ""
                    && can_describe (item.end_datetime, item.absence_status)) {
                    found.add (item);
                }
            });
            return found;
        }

        /* POST the reason(s) then refresh the lists so the reason (and dots) update. */
        private async void apply_absence_reason (int[] server_ids, string[] timetable_ids,
                                                 string reason) throws GLib.Error {
            yield provider.create_absence_reason (server_ids, timetable_ids, reason);
            refresh_absence.begin ();
            refresh_timetable.begin ();
        }

        /* Report today's absence ("call in sick"). Returns the backend's message
         * (which may be an informational rejection) for the caller to surface. */
        public async string call_in_sick (string reason) throws GLib.Error {
            int code;
            string message;
            yield provider.student_call_in_sick (reason, 1, out code, out message);
            refresh_absence.begin ();
            return message;
        }

        /* The editable future absences, fetched on their own (own card state) so
         * a slow call doesn't hold up the page. */
        public async void refresh_future_absence () {
            int64 t = get_monotonic_time ();
            uint gen = ++future_absence_gen;
            future_absence_state = LoadState.LOADING;
            future_absence_updated ();
            try {
                var items = yield provider.load_future_absence ();
                if (gen != future_absence_gen) {
                    return;
                }
                future_absences.remove_all ();
                for (uint i = 0; i < items.length; i++) {
                    future_absences.append (items[i]);
                }
                future_absence_state = LoadState.LOADED;
            } catch (GLib.Error e) {
                if (gen != future_absence_gen) {
                    return;
                }
                warning ("future absence load failed: %s", e.message);
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

            // The policy that gates "describe reason"; best effort, so a failure
            // just leaves the window unchanged without failing the list.
            try {
                var settings = yield provider.load_absence_settings ();
                if (gen == absence_gen && settings != null) {
                    student_reason_days_back = settings.student_reason_days_back;
                    show_absence_reason = settings.show_absence_reason;
                }
            } catch (GLib.Error e) {
                warning ("absence settings load failed: %s", e.message);
            }

            try {
                var data = yield provider.load_absence ();
                if (gen != absence_gen) {
                    return;
                }
                absences.remove_all ();
                for (uint i = 0; i < data.items.length; i++) {
                    absences.append (data.items[i]);
                }
                absence_summary = data.summary;
                absence_state = LoadState.LOADED;
            } catch (GLib.Error e) {
                if (gen != absence_gen) {
                    return;
                }
                warning ("absence load failed: %s", e.message);
                absences.remove_all ();
                absence_summary = null;
                absence_state = LoadState.FAILED;
            }
            link_absences ();
            debug ("refresh: absence in %lld ms", (get_monotonic_time () - t) / 1000);
            absence_updated ();
        }

        /* Link each lesson to its registered-absence record, matched by
         * TimetableId <-> EventId, once the absence list is loaded. This gives a
         * lesson the details the timetable omits (e.g. StudentReason). The dot
         * colour does NOT depend on this — it's derived from the lesson's own
         * AbsenceStatus — so offline (absence uncached → FAILED) only loses the
         * details, not the dots. Re-run after either list (re)loads. */
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
    }
}
