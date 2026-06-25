/* overview-page.vala
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

using Gtk;

namespace Opensprogskole {

    /* The overview / dashboard: greeting, today's lessons, attendance donut,
     * recent grades and a news placeholder. Reads everything from the Session's
     * stores; reflows to a single column under the breakpoint. The attendance
     * card shows a spinner until the (separately fetched) absence data arrives. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/overview-page.ui")]
    public class OverviewPage : Adw.Bin {

        [GtkChild] private unowned Label greeting;
        [GtkChild] private unowned Label subtitle;
        [GtkChild] private unowned Label lessons_subheading;
        [GtkChild] private unowned Gtk.Stack lessons_stack;
        [GtkChild] private unowned DayLessons today_lessons;
        [GtkChild] private unowned Gtk.Stack attendance_stack;
        [GtkChild] private unowned Chart chart;
        [GtkChild] private unowned Label attendance_caption;
        [GtkChild] private unowned Grades grades;
        [GtkChild] private unowned Button report_button;
        [GtkChild] private unowned Button report_button_mobile;
        [GtkChild] private unowned Button view_schedule_button;
        [GtkChild] private unowned Button all_grades_button;

        public signal void report_absence_requested ();
        public signal void open_schedule ();
        public signal void open_grades ();

        private Session? session = null;

        construct {
            report_button.clicked.connect (() => report_absence_requested ());
            report_button_mobile.clicked.connect (() => report_absence_requested ());
            view_schedule_button.clicked.connect (() => open_schedule ());
            all_grades_button.clicked.connect (() => open_grades ());
            today_lessons.lesson_activated.connect ((item) => {
                new LessonDialog (item).present (this);
            });
        }

        public void bind (Session session) {
            this.session = session;
            session.updated.connect (reload);
            session.absence_updated.connect (update_attendance);
            reload ();
            if (session.absence_summary != null) {
                update_attendance ();   // already loaded (e.g. re-bind)
            }
        }

        private void reload () {
            if (session == null) {
                return;
            }

            var now = new DateTime.now_local ();
            string first = session.display_name.split (" ")[0];
            /* TODO: different time */
            greeting.label = _("Good day, %s").printf (first);
            subtitle.label = "%s · %s".printf (
                now.format ("%A, %-d %B %Y"), session.school.name);

            reload_lessons (now);

            grades.bind (session.grades);
        }

        /* Surface the next relevant day's lessons: today while it still has a
         * lesson to come, otherwise the closest future day. When nothing is
         * upcoming at all, swap in the "no more lessons" status page. */
        private void reload_lessons (DateTime now) {
            string? key = session.timetable.upcoming_day_key (now);
            if (key == null) {
                lessons_stack.visible_child_name = "none";
                return;
            }

            string today = now.format ("%Y-%m-%d");
            if (key == today) {
                lessons_subheading.label = _("Today");
            } else {
                var day = new DateTime.local (
                    int.parse (key.substring (0, 4)),
                    int.parse (key.substring (5, 2)),
                    int.parse (key.substring (8, 2)), 0, 0, 0);
                /* Translators: a weekday + date, e.g. "Tuesday, 30 June".
                   Reorder the %A/%-d/%B parts to suit your locale —
                   see `man strftime` for what each one means. */
                lessons_subheading.label = day.format (_("%A, %-d %B"));
            }

            today_lessons.bind (session.timetable.get_day_for_key (key),
                                lessons_subheading.label);
            lessons_stack.visible_child_name = "lessons";
        }

        private void update_attendance () {
            var s = session != null ? session.absence_summary : null;
            if (s == null || s.total <= 0) {
                chart.clear ();
                chart.add_segment (1.0, rgba ("#deddda"));
                chart.center_text = "—";
                chart.subtitle = _("no data");
                attendance_caption.label = _("No attendance data");
                attendance_stack.visible_child_name = "chart";
                return;
            }

            chart.clear ();
            chart.add_segment (s.present, rgba ("#3584e4"));   // arrived — accent
            chart.add_segment (s.illegal, rgba ("#e01b24"));   // not approved
            chart.add_segment (s.late, rgba ("#e5a50a"));      // late
            if (s.legal > 0) {
                chart.add_segment (s.legal, rgba ("#2ec27e")); // approved absence
            }

            chart.center_text = "%.0f%%".printf (s.present_percent);
            chart.subtitle = _("present");
            attendance_caption.label = _("Present %.1f%% · Not approved %.1f%% · Late %.1f%%")
                .printf (pct (s.present, s.total), pct (s.illegal, s.total), pct (s.late, s.total));

            attendance_stack.visible_child_name = "chart";
        }

        private static double pct (int part, int total) {
            return total > 0 ? (double) part / total * 100.0 : 0.0;
        }

        private static Gdk.RGBA rgba (string spec) {
            var c = Gdk.RGBA ();
            c.parse (spec);
            return c;
        }
    }
}
