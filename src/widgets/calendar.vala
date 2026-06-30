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

    /* Returns a lesson marker label for a date, or null if there is none. The
     * calendar pulls markers through this so all three visible months populate
     * themselves (rather than the page having to push markers per month). */
    public delegate string? CalendarMarkerFunc (int year, int month, int day);

    /* A month-view calendar built on an Adw.Carousel of three month grids
     * (previous / current / next). The current month is centered; dragging the
     * carousel reveals the neighbours and snaps to one, after which the code
     * adopts it as the new center and recenters under it (an infinite pager).
     * The header carries the month name and previous/next buttons that scroll
     * the carousel (so they animate too). */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/calendar.ui")]
    public class Calendar : Adw.Bin {

        [GtkChild]
        private unowned Gtk.Label month_label;
        [GtkChild]
        private unowned Gtk.Button prev_button;
        [GtkChild]
        private unowned Gtk.Button next_button;
        [GtkChild]
        private unowned Adw.Carousel carousel;
        [GtkChild]
        private unowned Gtk.Grid page0;
        [GtkChild]
        private unowned Gtk.Grid page1;
        [GtkChild]
        private unowned Gtk.Grid page2;

        /* Weekday abbreviations indexed by ISO day: 0 = Monday .. 6 = Sunday.
         * They are rotated into the header columns according to first_weekday. */
        private const string[] WEEKDAYS = { "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" };

        /* Year of the displayed (center) month. */
        public int year { get; private set; }

        /* Displayed month, 1 (January) .. 12 (December). */
        public int month { get; private set; }

        /* Currently highlighted day of the displayed month, or 0 for none. */
        public int selected_day { get; private set; default = 0; }

        /* Day the week starts on, in ISO numbering: 1 = Monday .. 7 = Sunday. */
        public int first_weekday { get; set; default = 1; }

        /* Vertically compact rows for narrow windows — toggles a CSS class. */
        public bool compact { get; set; default = false; }

        /* Emitted when the user activates an in-month day button. */
        public signal void day_selected (int year, int month, int day);

        /* Emitted when navigation moves to a different month. */
        public signal void month_changed (int year, int month);

        private CalendarMarkerFunc? marker_func = null;

        /* The center grid's (page1) in-month day cells, for in-place selection. */
        private CalendarDay?[] day_buttons = new CalendarDay?[32];

        /* Navigable range as month indices (year * 12 + month - 1); UNBOUNDED
         * pages infinitely that way. Set from the schedule's first/last lesson
         * month: a drag toward a month outside the course springs back and the
         * boundary button greys out (see set_bounds). */
        private const int UNBOUNDED = int.MIN;
        private int min_index = UNBOUNDED;
        private int max_index = UNBOUNDED;

        /* True while we drive the carousel ourselves, so its settling
         * page-changed emissions aren't mistaken for a user swipe. Starts true:
         * the carousel can't be centred until it's first mapped (see recenter). */
        private bool syncing = true;

        construct {
            ensure_widget_styles (this);

            // The buttons scroll the carousel, so they animate like a drag does;
            // the settle then runs through on_page_changed exactly the same way.
            prev_button.clicked.connect (() => carousel.scroll_to (page0, true));
            next_button.clicked.connect (() => carousel.scroll_to (page2, true));
            carousel.page_changed.connect (on_page_changed);
            // scroll_to is a no-op until the carousel is mapped, and the schedule
            // tab isn't visible at startup — centre once it actually appears.
            carousel.map.connect (recenter);

            notify["first-weekday"].connect (refresh);
            notify["compact"].connect (() => {
                if (compact) {
                    add_css_class ("calendar-compact");
                } else {
                    remove_css_class ("calendar-compact");
                }
            });

            var now = new DateTime.now_local ();
            year = now.get_year ();
            month = now.get_month ();
            rebuild ();
        }

        /* Jump to a month with no animation (programmatic, e.g. to today). */
        public void set_date (int year, int month) {
            this.year = year;
            this.month = month;
            selected_day = 0;
            rebuild ();
        }

        /* Confine navigation to [first .. last] (inclusive). */
        public void set_bounds (int first_year, int first_month,
                                int last_year, int last_month) {
            min_index = month_index (first_year, first_month);
            max_index = month_index (last_year, last_month);
            update_buttons ();
        }

        /* Lift the navigation limits (e.g. when there is no course data). */
        public void clear_bounds () {
            min_index = UNBOUNDED;
            max_index = UNBOUNDED;
            update_buttons ();
        }

        /* Highlight a day in the displayed month (0 clears). Applied in place;
         * does not emit day-selected. */
        public void select_day (int day) {
            apply_selection (day);
        }

        /* Set where lesson markers come from; rebuilds so all three months pick
         * them up. */
        public void set_marker_func (owned CalendarMarkerFunc func) {
            marker_func = (owned) func;
            refresh ();
        }

        /* Re-query markers for the visible months (e.g. after a data load or a
         * first-weekday change). */
        public void refresh () {
            rebuild ();
        }

        /* The carousel settled on a side page (from a drag or a button). Adopt it
         * as the new center, unless that month is out of bounds — then spring
         * back. page1 is always the middle, so index 1 means "no move". */
        private void on_page_changed (uint index) {
            if (syncing) {
                // Our own recentre settling; disarm once it reaches the centre.
                if (index == 1) {
                    syncing = false;
                }
                return;
            }
            if (index == 1) {
                return;
            }
            int delta = (int) index - 1;   // 0 → previous, 2 → next
            if (within_bounds (month_index (year, month) + delta)) {
                shift (delta);
            } else {
                syncing = true;
                carousel.scroll_to (page1, true);
            }
        }

        private void shift (int delta) {
            int m = month + delta;
            int y = year;
            while (m < 1) { m += 12; y--; }
            while (m > 12) { m -= 12; y++; }
            this.year = y;
            this.month = m;
            selected_day = 0;

            // Rebuild the center first so page1 matches the just-revealed page,
            // jump onto it invisibly, then rebuild the (off-screen) sides.
            build_center ();
            recenter ();
            build_neighbors ();
            month_changed (year, month);
        }

        /* Build all three months for the current center and snap to it (no
         * animation). Used for every non-drag (re)build. */
        private void rebuild () {
            build_center ();
            build_neighbors ();
            recenter ();
        }

        /* Snap to the centre page, ignoring the carousel's settling page-changed
         * emissions so they aren't read as a swipe. The guard is dropped only
         * when the centre settle actually arrives (see on_page_changed), since
         * scroll_to settles a frame or two later, not synchronously. When already
         * centred there is nothing to settle, so don't arm the guard. Also the
         * map handler, as scroll_to is a no-op before the first allocation. */
        private void recenter () {
            if (centered ()) {
                return;
            }
            syncing = true;
            carousel.scroll_to (page1, false);
        }

        /* True when the carousel is resting on the centre page (page1, index 1).
         * position is in page units and settles to an exact integer. */
        private bool centered () {
            return ((int) (carousel.position + 0.5)) == 1;
        }

        // page1 = center month; page0 = previous; page2 = next.
        private void build_center () {
            day_buttons = build_month (page1, year, month, true);
            month_label.label = new DateTime.local (year, month, 1, 0, 0, 0).format ("%B %Y");
        }

        private void build_neighbors () {
            int pm = month - 1, py = year;
            if (pm < 1) { pm = 12; py--; }
            build_month (page0, py, pm, false);

            int nm = month + 1, ny = year;
            if (nm > 12) { nm = 1; ny++; }
            build_month (page2, ny, nm, false);

            update_buttons ();
        }

        /* Grey out the prev/next button when its month falls outside the bounds. */
        private void update_buttons () {
            int center = month_index (year, month);
            prev_button.sensitive = within_bounds (center - 1);
            next_button.sensitive = within_bounds (center + 1);
        }

        private static int month_index (int year, int month) {
            return year * 12 + (month - 1);
        }

        private bool within_bounds (int index) {
            return (min_index == UNBOUNDED || index >= min_index)
                && (max_index == UNBOUNDED || index <= max_index);
        }

        /* Build one month into `grid`, returning its in-month day cells. Markers
         * come from marker_func. Only the center grid's cells drive selection. */
        private CalendarDay?[] build_month (Gtk.Grid grid, int y, int m, bool is_center) {
            Gtk.Widget? child;
            while ((child = grid.get_first_child ()) != null) {
                grid.remove (child);
            }
            var buttons = new CalendarDay?[32];

            var first = new DateTime.local (y, m, 1, 0, 0, 0);

            // Weekday header row, rotated so column 0 is first_weekday.
            for (int col = 0; col < 7; col++) {
                int weekday_index = (first_weekday - 1 + col) % 7;
                var head = new Gtk.Label (WEEKDAYS[weekday_index]);
                head.add_css_class ("calendar-weekday");
                grid.attach (head, col, 0, 1, 1);
            }

            // get_day_of_week returns 1 (Mon) .. 7 (Sun); the column of the 1st
            // is its distance from first_weekday; + 7 keeps the result positive.
            int lead = (first.get_day_of_week () - first_weekday + 7) % 7;
            int days = GLib.Date.get_days_in_month ((DateMonth) m, (DateYear) y);

            int pm = m - 1, py = y;
            if (pm < 1) { pm = 12; py--; }
            int prev_days = GLib.Date.get_days_in_month ((DateMonth) pm, (DateYear) py);

            for (int i = 0; i < 42; i++) {
                int row = i / 7 + 1;
                int col = i % 7;

                CalendarDay cell;
                if (i < lead) {
                    // Trailing days of the previous month.
                    cell = make_dim_cell (prev_days - lead + 1 + i);
                } else if (i < lead + days) {
                    int day = i - lead + 1;
                    string? marker = marker_func != null ? marker_func (y, m, day) : null;
                    cell = make_day_cell (y, m, day, marker, is_center, buttons);
                } else {
                    // Leading days of the next month.
                    cell = make_dim_cell (i - lead - days + 1);
                }

                grid.attach (cell, col, row, 1, 1);
            }
            return buttons;
        }

        private CalendarDay make_day_cell (int y, int m, int day, string? marker,
                                           bool is_center, CalendarDay?[] buttons) {
            var cell = new CalendarDay (day);
            cell.set_marker (marker);
            if (is_center && day == selected_day) {
                cell.add_css_class ("selected-day");
            }
            cell.clicked.connect (() => {
                if (is_center) {
                    apply_selection (day);
                }
                day_selected (y, m, day);
            });
            if (is_center) {
                buttons[day] = cell;
            }
            return cell;
        }

        private CalendarDay make_dim_cell (int day) {
            return new CalendarDay (day) {
                sensitive = false
            };
        }

        /* Move the highlight without rebuilding, so the focused button survives. */
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
    }
}
