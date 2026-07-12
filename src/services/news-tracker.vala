/* news-tracker.vala
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

    /* Watches a Session for news the user hasn't seen before: freshly
     * published grades and newly scheduled exams. A pure observer — Session
     * stays an orchestrator and knows nothing about "news"; what counts as an
     * exam is the backend's call (SchoolProvider.is_exam), since every school
     * system encodes that differently.
     *
     * Detection compares against seen-sets persisted in the session's
     * per-account storage, so arrivals *between* app runs are caught too —
     * that's the background sync's whole point. The first successful load
     * only primes a set (no storm on a fresh login); the stored set is the
     * union of everything ever seen, so an item flapping out of and back
     * into a server response can't re-announce itself. Logout wipes the sets
     * with the rest of the account storage. */
    public class NewsTracker : GLib.Object {

        public signal void grades_added (GradeItem[] items);
        public signal void exams_added (TimetableItem[] items);

        private Session session;

        public NewsTracker (Session session) {
            this.session = session;

            // Test hook: with OPENSPROGSKOLE_FORGET_NEWS set, empty the seen-
            // sets (kept present, so this is not a re-prime) — the next
            // refresh then re-announces everything currently on the server,
            // exercising the whole notification chain without waiting for
            // real news. Pairs well with --sync, which has no window whose
            // focus could suppress the delivery.
            if (GLib.Environment.get_variable ("OPENSPROGSKOLE_FORGET_NEWS") != null) {
                foreach (var key in new string[] { "seen-grades", "seen-exams" }) {
                    if (session.storage.get_value (key) != null) {
                        session.storage.set_value (key, new GLib.Variant.strv ({}));
                        debug ("forgot all %s for testing", key);
                    }
                }
            }

            session.updated.connect (check_grades);
            session.timetable_updated.connect (check_exams);
        }

        private void check_grades () {
            if (session.grades_state != LoadState.LOADED) {
                return;
            }
            string[] keys = {};
            for (uint i = 0; i < session.grades.get_n_items (); i++) {
                keys += grade_key ((GradeItem) session.grades.get_item (i));
            }
            var fresh = unseen_keys ("seen-grades", keys);
            if (fresh.length == 0) {
                return;
            }
            GradeItem[] news = {};
            for (uint i = 0; i < session.grades.get_n_items (); i++) {
                var item = (GradeItem) session.grades.get_item (i);
                if (fresh.contains (grade_key (item))) {
                    news += item;
                }
            }
            grades_added (news);
        }

        private void check_exams () {
            if (session.timetable_state != LoadState.LOADED) {
                return;
            }
            // Every exam id (past ones included) feeds the seen-set so nothing
            // old ever announces itself; only new AND upcoming ones are news.
            string[] keys = {};
            TimetableItem[] exams = {};
            session.timetable.foreach_lesson ((item) => {
                if (session.provider.is_exam (item)) {
                    keys += item.timetable_id;
                    exams += item;
                }
            });
            var fresh = unseen_keys ("seen-exams", keys);
            if (fresh.length == 0) {
                return;
            }
            TimetableItem[] news = {};
            foreach (var item in exams) {
                if (item.is_upcoming && fresh.contains (item.timetable_id)) {
                    news += item;
                }
            }
            if (news.length > 0) {
                exams_added (news);
            }
        }

        // Grades carry no server id; the identifying fields make the key. A
        // corrected grade value counts as news — arguably it is.
        private static string grade_key (GradeItem item) {
            return "%s|%s|%s|%s".printf (item.course, item.evaluation_form,
                                         item.due_date, item.grade_value);
        }

        /* The keys from `fresh` that the persisted set under `storage_key`
         * doesn't know yet — none when the set didn't exist (first load =
         * prime, not news). */
        private GLib.GenericSet<string> unseen_keys (string storage_key, string[] fresh) {
            var result = new GLib.GenericSet<string> (str_hash, str_equal);
            var seen = new GLib.GenericSet<string> (str_hash, str_equal);
            GLib.Variant? stored = session.storage.get_value (storage_key);
            bool primed = stored != null;
            if (primed) {
                foreach (var key in stored.get_strv ()) {
                    seen.add (key);
                }
            }
            bool grew = false;
            foreach (var key in fresh) {
                if (!seen.contains (key)) {
                    seen.add (key);
                    grew = true;
                    if (primed) {
                        result.add (key);
                    }
                }
            }
            if (grew) {
                string[] all = {};
                seen.foreach ((key) => all += key);
                session.storage.set_value (storage_key, new GLib.Variant.strv (all));
            }
            return result;
        }
    }
}
