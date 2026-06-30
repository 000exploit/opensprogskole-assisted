/* schedule-view.vala
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

    /* The Schedule page: the composition layer that ties the schedule widgets
     * to the data. This is what the plan calls a "view" / page — it lives in
     * src/views/, owns the TimetableStore (the single source of truth) and the
     * selected date, and wires everything together. The widgets below it stay
     * dumb.
     *
     * Both presentations — the month grid + day panel, and the agenda — read
     * from the same store. The Month/Agenda toggle only flips the visible child
     * of a Gtk.Stack, so switching views recomputes nothing. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/schedule-view.ui")]
    public class ScheduleView : Adw.Bin {

        [GtkChild]
        private unowned Adw.ViewStack view_stack;
        [GtkChild]
        private unowned Calendar calendar;
        [GtkChild]
        private unowned DayLessons day_lessons;
        [GtkChild]
        private unowned Agenda agenda;

        // Set via use_store (); starts empty so the widget is usable standalone.
        private TimetableStore store = new TimetableStore ();
        // Set by MainView; lets the lesson dialog describe an absence reason.
        public Session? session { get; set; default = null; }
        // The calendar's selected day (yyyy-MM-dd); the agenda scrolls here when
        // it's switched to. Set by on_day_selected.
        private string selected_key = "";

        private GLib.Settings settings = new GLib.Settings (Config.APP_ID);

        construct {
            ensure_widget_styles (this);

            // Calendar week start: the "first-weekday" preference, or the school's
            // default when it's "use school default" (0). Re-applies when either
            // the preference or the bound session changes.
            settings.changed["first-weekday"].connect (apply_first_weekday);
            notify["session"].connect (apply_first_weekday);
            apply_first_weekday ();

            calendar.day_selected.connect (on_day_selected);
            calendar.month_changed.connect (on_month_changed);
            day_lessons.lesson_activated.connect (open_lesson);
            agenda.lesson_activated.connect (open_lesson);

            // Scroll the agenda to the calendar's selected day each time it's
            // switched to (not just the first time it's shown). Falls back to the
            // upcoming-day anchor before any selection exists.
            view_stack.notify["visible-child"].connect (() => {
                if (view_stack.visible_child != agenda) {
                    return;
                }
                if (selected_key != "") {
                    agenda.scroll_to_day (selected_key);
                } else {
                    agenda.reveal_anchor ();
                }
            });
        }

        /* ISO weekday the calendar starts on: the user override, or the school's
         * default when the preference is "use school default" (0). */
        private void apply_first_weekday () {
            int pref = settings.get_int ("first-weekday");
            int school_default = session != null ? session.school.first_weekday : 1;
            calendar.first_weekday = pref != 0 ? pref : school_default;
        }

        /* Use a shared store (e.g. the Session's). Renders its current contents
         * immediately and tracks future changes. */
        public void use_store (TimetableStore store) {
            this.store = store;
            // The calendar pulls lesson dots through this, so all three visible
            // months populate themselves. Captures `store` (not `this`) to avoid
            // a reference cycle.
            calendar.set_marker_func ((y, m, d) =>
                store.has_lessons (y, m, d) ? store.marker_label (y, m, d) : null);
            store.changed.connect (on_store_changed);
            on_store_changed ();
        }

        /* The data set changed: rebuild the agenda, confine the calendar to the
         * course's date range and re-query its lesson dots, then open it. */
        private void on_store_changed () {
            agenda.set_all (store);
            reset_calendar ();
        }

        /* Bound the calendar to the months that carry lessons (so it can't page
         * into empty months outside the course) and open on the current month
         * with today selected. Only when today falls outside the course period do
         * we clamp to its nearest edge, so the view never lands on an empty,
         * unreachable month. */
        private void reset_calendar () {
            var now = new DateTime.now_local ();
            int year = now.get_year (), month = now.get_month (), day = now.get_day_of_month ();

            var keys = store.sorted_keys ();
            if (keys.length () == 0) {
                calendar.clear_bounds ();
            } else {
                string first = keys.nth_data (0);
                string last = keys.last ().data;
                calendar.set_bounds (key_year (first), key_month (first),
                                     key_year (last), key_month (last));

                int today = year * 12 + (month - 1);
                if (today < key_year (first) * 12 + (key_month (first) - 1)) {
                    year = key_year (first); month = key_month (first); day = key_day (first);
                } else if (today > key_year (last) * 12 + (key_month (last) - 1)) {
                    year = key_year (last); month = key_month (last); day = key_day (last);
                }
            }

            calendar.set_date (year, month);
            show_day (year, month, day);
        }

        /* Jump to and select the soonest upcoming lesson — the same "next up" day
         * the overview surfaces. Used when the user opens the schedule from the
         * overview's "View schedule" button. No-op when nothing is upcoming, so
         * the current view is kept. */
        public void focus_upcoming () {
            string? key = store.upcoming_day_key (new DateTime.now_local ());
            if (key == null) {
                return;
            }
            calendar.set_date (key_year (key), key_month (key));
            show_day (key_year (key), key_month (key), key_day (key));
        }

        private static int key_year (string key) { return int.parse (key.substring (0, 4)); }
        private static int key_month (string key) { return int.parse (key.substring (5, 2)); }
        private static int key_day (string key) { return int.parse (key.substring (8, 2)); }

        private void on_month_changed (int year, int month) {
            select_initial_day (year, month);
        }

        /* Pick a sensible day to show: today if it has lessons, else the first
         * day of the month that does, else the 1st. */
        private void select_initial_day (int year, int month) {
            int day = 1;
            var now = new DateTime.now_local ();
            if (now.get_year () == year && now.get_month () == month) {
                day = now.get_day_of_month ();
            }
            if (!store.has_lessons (year, month, day)) {
                int first = first_lesson_day (year, month);
                if (first > 0) {
                    day = first;
                }
            }
            show_day (year, month, day);
        }

        private int first_lesson_day (int year, int month) {
            int days = GLib.Date.get_days_in_month ((DateMonth) month, (DateYear) year);
            for (int day = 1; day <= days; day++) {
                if (store.has_lessons (year, month, day)) {
                    return day;
                }
            }
            return 0;
        }

        /* Highlight a day and show its lessons — the programmatic counterpart to
         * the user clicking a day (calendar.select_day doesn't emit day_selected). */
        private void show_day (int year, int month, int day) {
            calendar.select_day (day);
            on_day_selected (year, month, day);
        }

        private void on_day_selected (int year, int month, int day) {
            selected_key = "%04d-%02d-%02d".printf (year, month, day);
            var model = store.get_day (year, month, day);
            day_lessons.bind (model, day_title (year, month, day));
        }

        private void open_lesson (TimetableItem item) {
            if (session == null) {
                return;
            }
            var dialog = new LessonDialog (item, session);
            dialog.present (this);
        }

        private static string day_title (int year, int month, int day) {
            var date = new DateTime.local (year, month, day, 0, 0, 0);
            return date.format ("%A, %-d %B");
        }
    }
}
