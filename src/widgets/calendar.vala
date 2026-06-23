/* calendar.vala
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

    /* A month-view calendar laid out as a grid of buttons, matching the
     * Schedule screen in the design. The header carries the month name plus
     * previous/next navigation; below it a Sunday-first weekday row sits over a
     * 6x7 grid of day cells. Each in-month day is an activatable button that
     * can carry a small lesson marker (a dot and a short label).
     *
     * Markers are remembered per calendar date, so navigating away from a month
     * and back keeps its lessons. The grid is only rebuilt when the displayed
     * month changes; selecting a day or updating a marker is applied in place,
     * so the focused button is never destroyed under the user. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/calendar.ui")]
    public class Calendar : Adw.Bin {

        [GtkChild]
        private unowned Gtk.Label month_label;
        [GtkChild]
        private unowned Gtk.Button prev_button;
        [GtkChild]
        private unowned Gtk.Button next_button;
        [GtkChild]
        private unowned Gtk.Grid grid;

        /* Weekday abbreviations indexed by ISO day: 0 = Monday .. 6 = Sunday.
         * They are rotated into the header columns according to first_weekday. */
        private const string[] WEEKDAYS = { "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" };

        /* Year of the displayed month. */
        public int year { get; private set; }

        /* Displayed month, 1 (January) .. 12 (December). */
        public int month { get; private set; }

        /* Currently highlighted day of the displayed month, or 0 for none. */
        public int selected_day { get; private set; default = 0; }

        /* Day the week starts on, in ISO numbering: 1 = Monday .. 7 = Sunday.
         * Defaults to Monday; set it (e.g. to 7 for Sunday) to change the column
         * order. Changing it re-lays out the grid. */
        public int first_weekday { get; set; default = 1; }

        /* Lesson markers, keyed by date so they survive month navigation. */
        private GLib.HashTable<int, string> markers
            = new GLib.HashTable<int, string> (direct_hash, direct_equal);

        /* Cells for the in-month days of the current grid, indexed 1..31. */
        private CalendarDay?[] day_buttons = new CalendarDay?[32];

        /* Emitted when the user activates an in-month day button. */
        public signal void day_selected (int year, int month, int day);

        /* Emitted when navigation moves to a different month. */
        public signal void month_changed (int year, int month);

        construct {
            ensure_widget_styles (this);

            prev_button.clicked.connect (() => {
                shift_month (-1);
                // Keep focus on the navigation button rather than letting it
                // fall to a day cell after the grid is rebuilt.
                prev_button.grab_focus ();
            });
            next_button.clicked.connect (() => {
                shift_month (1);
                next_button.grab_focus ();
            });

            notify["first-weekday"].connect (rebuild_grid);

            var now = new DateTime.now_local ();
            year = now.get_year ();
            month = now.get_month ();
            rebuild_grid ();
        }

        /* Show a specific month. Markers already known for that month are
         * displayed; markers are never discarded by navigation. */
        public void set_date (int year, int month) {
            this.year = year;
            this.month = month;
            selected_day = 0;
            rebuild_grid ();
        }

        /* Highlight a day in the displayed month (0 clears the highlight).
         * Applied in place; does not emit day-selected. */
        public void select_day (int day) {
            apply_selection (day);
        }

        /* Attach a lesson marker to a day of the displayed month. A null label
         * removes the marker. Applied in place. */
        public void set_marker (int day, string? label) {
            if (day < 1 || day > 31) {
                return;
            }

            int key = date_key (year, month, day);
            if (label == null) {
                markers.remove (key);
            } else {
                markers.insert (key, label);
            }

            var button = day_buttons[day];
            if (button != null) {
                button.set_marker (label);
            }
        }

        /* Drop every lesson marker of the displayed month. Applied in place. */
        public void clear_markers () {
            for (int day = 1; day <= 31; day++) {
                markers.remove (date_key (year, month, day));
                var button = day_buttons[day];
                if (button != null) {
                    button.set_marker (null);
                }
            }
        }

        private static int date_key (int year, int month, int day) {
            return year * 10000 + month * 100 + day;
        }

        private void shift_month (int delta) {
            int m = month + delta;
            int y = year;
            while (m < 1) { m += 12; y--; }
            while (m > 12) { m -= 12; y++; }

            year = y;
            month = m;
            selected_day = 0;
            rebuild_grid ();
            month_changed (year, month);
        }

        /* Move the highlight without rebuilding the grid, so the focused button
         * survives. */
        private void apply_selection (int day) {
            var previous = (selected_day >= 1 && selected_day <= 31)
                ? day_buttons[selected_day] : null;
            if (previous != null) {
                previous.remove_css_class ("selected-day");
            }

            selected_day = day;

            var current = (day >= 1 && day <= 31) ? day_buttons[day] : null;
            if (current != null) {
                current.add_css_class ("selected-day");
            }
        }

        private void rebuild_grid () {
            // Drop the previous contents.
            Gtk.Widget? child;
            while ((child = grid.get_first_child ()) != null) {
                grid.remove (child);
            }
            day_buttons = new CalendarDay?[32];

            var first = new DateTime.local (year, month, 1, 0, 0, 0);
            month_label.label = first.format ("%B %Y");

            // Weekday header row, rotated so column 0 is first_weekday.
            for (int col = 0; col < 7; col++) {
                int weekday_index = (first_weekday - 1 + col) % 7;
                var head = new Gtk.Label (WEEKDAYS[weekday_index]);
                head.add_css_class ("calendar-weekday");
                grid.attach (head, col, 0, 1, 1);
            }

            // get_day_of_week returns 1 (Mon) .. 7 (Sun). The column of the 1st
            // is its distance from first_weekday; + 7 keeps the result positive.
            int lead = (first.get_day_of_week () - first_weekday + 7) % 7;
            int days = GLib.Date.get_days_in_month ((DateMonth) month, (DateYear) year);

            int prev_month = month - 1;
            int prev_year = year;
            if (prev_month < 1) { prev_month = 12; prev_year--; }
            int prev_days = GLib.Date.get_days_in_month ((DateMonth) prev_month, (DateYear) prev_year);

            for (int i = 0; i < 42; i++) {
                int row = i / 7 + 1;
                int col = i % 7;

                CalendarDay cell;
                if (i < lead) {
                    // Trailing days of the previous month.
                    cell = make_dim_cell (prev_days - lead + 1 + i);
                } else if (i < lead + days) {
                    int day = i - lead + 1;
                    string? marker = markers.lookup (date_key (year, month, day));
                    cell = make_day_cell (day, marker);
                } else {
                    // Leading days of the next month.
                    cell = make_dim_cell (i - lead - days + 1);
                }

                grid.attach (cell, col, row, 1, 1);
            }
        }

        private CalendarDay make_day_cell (int day, string? marker) {
            var cell = new CalendarDay (day);
            cell.set_marker (marker);
            if (day == selected_day) {
                cell.add_css_class ("selected-day");
            }
            cell.clicked.connect (() => {
                apply_selection (day);
                day_selected (year, month, day);
            });

            day_buttons[day] = cell;
            return cell;
        }

        private CalendarDay make_dim_cell (int day) {
            return new CalendarDay (day) {
                sensitive = false
            };
        }
    }
}
