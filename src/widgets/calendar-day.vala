/* calendar-day.vala
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

    /* One day cell of the calendar grid: a button whose layout (day number,
     * the upper-left lesson dot and the lesson label) lives entirely in
     * calendar-day.ui. The dot is part of the layout but hidden until a marker
     * is set, so showing/hiding a lesson is just a visibility toggle rather than
     * rebuilding the cell's contents. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/calendar-day.ui")]
    public class CalendarDay : Gtk.Button {

        [GtkChild]
        private unowned Gtk.Label number_label;
        [GtkChild]
        private unowned Gtk.Box dot;
        [GtkChild]
        private unowned Gtk.Label lesson_label;

        /* The day number shown in this cell. */
        public int day { get; construct; }

        public CalendarDay (int day) {
            Object (day: day);
        }

        construct {
            ensure_widget_styles (this);
            number_label.label = day.to_string ();
        }

        /* Show a lesson marker (dot + short label), or hide it when label is
         * null. */
        public void set_marker (string? label) {
            bool has_lesson = label != null;
            dot.visible = has_lesson;
            lesson_label.visible = has_lesson;
            lesson_label.label = has_lesson ? label : "";
        }
    }
}
