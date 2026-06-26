/* timetable-store.vala
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

    /* In-memory home for the timetable. This is the single source of truth the
     * Schedule views read from — the widgets never hold the lessons themselves.
     *
     * On load() the flat JSON array is deserialized once into TimetableItem
     * objects and indexed by day into a HashTable of GLib.ListStore. Each day's
     * ListStore is built and sorted a single time, so:
     *
     *   - the calendar grid asks has_lessons()/marker_label() per day for dots,
     *   - the day panel binds straight to get_day(),
     *   - the agenda reads the same per-day stores,
     *
     * and switching between the month and agenda views recomputes nothing: they
     * are different presentations of the same prepared data. */
    public class TimetableStore : GLib.Object {

        // Day key "yyyy-mm-dd" -> sorted ListStore of TimetableItem.
        private GLib.HashTable<string, GLib.ListStore> by_day
            = new GLib.HashTable<string, GLib.ListStore> (str_hash, str_equal);

        public signal void changed ();

        public void load (Json.Array array) {
            by_day.remove_all ();

            var items = TimetableItem.from_json_array (array);
            for (uint i = 0; i < items.length; i++) {
                var item = items[i];
                string key = item.date_key;
                if (key == "") {
                    continue;
                }

                var day = by_day.lookup (key);
                if (day == null) {
                    day = new GLib.ListStore (typeof (TimetableItem));
                    by_day.insert (key, day);
                }
                day.append (item);
            }

            // Sort each day chronologically by start time.
            by_day.foreach ((key, day) => {
                day.sort ((a, b) => {
                    return strcmp (((TimetableItem) a).start_time,
                                   ((TimetableItem) b).start_time);
                });
            });

            changed ();
        }

        public delegate void LessonFunc (TimetableItem item);

        /* Visit every lesson across all days. Lets a caller stamp per-lesson
         * state (e.g. attendance) without reaching into the private day table. */
        public void foreach_lesson (LessonFunc func) {
            by_day.foreach ((key, day) => {
                for (uint i = 0; i < day.get_n_items (); i++) {
                    func ((TimetableItem) day.get_item (i));
                }
            });
        }

        /* The lessons of a day as a list model, or null when there are none.
         * The same ListStore instance is returned for repeated calls. */
        public GLib.ListStore? get_day (int year, int month, int day) {
            return by_day.lookup (day_key (year, month, day));
        }

        public bool has_lessons (int year, int month, int day) {
            return by_day.contains (day_key (year, month, day));
        }

        /* Short label for the calendar dot — the first lesson's short label. */
        public string? marker_label (int year, int month, int day) {
            var store = by_day.lookup (day_key (year, month, day));
            if (store == null || store.get_n_items () == 0) {
                return null;
            }
            return ((TimetableItem) store.get_item (0)).short_label;
        }

        /* All days that have lessons, as "yyyy-mm-dd" keys, in chronological
         * order (lexicographic order of the key matches date order). */
        public GLib.List<string> sorted_keys () {
            var keys = new GLib.List<string> ();
            foreach (string key in by_day.get_keys ()) {
                keys.append (key);
            }
            keys.sort ((a, b) => strcmp (a, b));
            return keys;
        }

        /* The lessons for a "yyyy-mm-dd" key, or null. */
        public GLib.ListStore? get_day_for_key (string key) {
            return by_day.lookup (key);
        }

        /* The day the overview should surface as "up next": today while it still
         * has a lesson that hasn't ended, otherwise the closest strictly-future
         * day that has lessons. Returns null when there are no current or future
         * lessons at all (so the caller can show an empty state). */
        public string? upcoming_day_key (DateTime now) {
            string today = now.format ("%Y-%m-%d");

            var today_store = by_day.lookup (today);
            if (today_store != null && day_has_remaining (today_store, now)) {
                return today;
            }

            // Closest day after today (keys sort lexicographically = by date).
            string? best = null;
            foreach (string key in by_day.get_keys ()) {
                if (strcmp (key, today) > 0
                    && (best == null || strcmp (key, best) < 0)) {
                    best = key;
                }
            }
            return best;
        }

        /* True when at least one lesson of the day ends after `now`. */
        private static bool day_has_remaining (GLib.ListStore store, DateTime now) {
            for (uint i = 0; i < store.get_n_items (); i++) {
                var end = ((TimetableItem) store.get_item (i)).end_datetime;
                if (end != null && end.compare (now) > 0) {
                    return true;
                }
            }
            return false;
        }

        private static string day_key (int year, int month, int day) {
            return "%04d-%02d-%02d".printf (year, month, day);
        }
    }
}
