/* schedule-view.vala
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
        private unowned Calendar calendar;
        [GtkChild]
        private unowned DayLessons day_lessons;
        [GtkChild]
        private unowned Agenda agenda;
        [GtkChild]
        private unowned Gtk.Stack view_stack;
        [GtkChild]
        private unowned Gtk.ToggleButton agenda_toggle;

        // Set via use_store (); starts empty so the widget is usable standalone.
        private TimetableStore store = new TimetableStore ();

        construct {
            ensure_widget_styles (this);

            calendar.day_selected.connect (on_day_selected);
            calendar.month_changed.connect (on_month_changed);
            day_lessons.lesson_activated.connect (open_lesson);
            agenda.lesson_activated.connect (open_lesson);
            agenda_toggle.toggled.connect (() => {
                view_stack.visible_child_name =
                    agenda_toggle.active ? "agenda" : "month";
            });

            store.changed.connect (on_store_changed);
        }

        /* Use a shared store (e.g. the Session's). Renders its current contents
         * immediately and tracks future changes. */
        public void use_store (TimetableStore store) {
            this.store = store;
            store.changed.connect (on_store_changed);
            on_store_changed ();
        }

        /* The data set changed: the agenda lists every lesson day in the store,
         * so it is rebuilt here (not per month). The month-dependent calendar
         * bits are refreshed for whatever month is currently shown. */
        private void on_store_changed () {
            agenda.set_all (store);
            refresh_month (calendar.year, calendar.month);
        }

        /* Refresh the parts that depend on the visible month. */
        private void refresh_month (int year, int month) {
            refresh_markers (year, month);
            select_initial_day (year, month);
        }

        private void on_month_changed (int year, int month) {
            refresh_month (year, month);
        }

        private void refresh_markers (int year, int month) {
            calendar.clear_markers ();
            int days = GLib.Date.get_days_in_month ((DateMonth) month, (DateYear) year);
            for (int day = 1; day <= days; day++) {
                if (store.has_lessons (year, month, day)) {
                    calendar.set_marker (day, store.marker_label (year, month, day));
                }
            }
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
            calendar.select_day (day);
            on_day_selected (year, month, day);
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

        private void on_day_selected (int year, int month, int day) {
            var model = store.get_day (year, month, day);
            day_lessons.bind (model, day_title (year, month, day));
        }

        private void open_lesson (TimetableItem item) {
            var dialog = new LessonDialog (item);
            dialog.present (this);
        }

        private static string day_title (int year, int month, int day) {
            var date = new DateTime.local (year, month, day, 0, 0, 0);
            return date.format ("%A, %-d %B");
        }
    }
}
