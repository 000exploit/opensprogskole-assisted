/* styles.vala
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

    /* Inline CSS shared by the dashboard widgets. It is registered once per
     * display, the first time any of the widgets is constructed, so the widgets
     * stay self-contained and do not depend on the application bundling a
     * separate stylesheet resource. Colours reference libadwaita's named
     * colours so the widgets follow the active light/dark theme and accent. */
    private const string WIDGET_CSS = """
    /* Grades — coloured grade chip */
    .grade-chip {
        min-width: 36px;
        min-height: 36px;
        border-radius: 9px;
        font-weight: 800;
        color: #ffffff;
    }
    .grade-chip.grade-success { background-color: @success_bg_color; color: @success_fg_color; }
    .grade-chip.grade-accent  { background-color: @accent_bg_color;  color: @accent_fg_color;  }
    .grade-chip.grade-warning { background-color: @warning_bg_color; color: @warning_fg_color; }
    .grade-chip.grade-error   { background-color: @destructive_bg_color; color: @destructive_fg_color; }
    .grade-chip.grade-neutral { background-color: @shade_color; color: @window_fg_color; }

    /* Lesson detail — room pills */
    .room-chip {
        background-color: @shade_color;
        border-radius: 7px;
        padding: 4px 10px;
    }

    /* Calendar — day buttons. The min-height reserves room for the optional
     * lesson marker row, so cells with and without a marker are the same height
     * and the calendar's overall height stays constant from month to month. */
    .calendar-cell {
        min-height: 58px;
        padding: 5px 7px;
        border-radius: 7px;
    }
    /* Vertically compact calendar for narrow windows — toggled by adding the
     * "calendar-compact" class on the Calendar (a breakpoint setter does this). */
    .calendar-compact .calendar-cell {
        min-height: 40px;
        padding: 2px 5px;
    }
    .calendar-compact .lesson-label { font-size: 0.7em; }
    .calendar-cell .calendar-day-number { font-weight: 600; }
    .calendar-cell.selected-day {
        background-color: alpha(@accent_bg_color, 0.12);
        box-shadow: inset 0 0 0 2px @accent_bg_color;
    }
    .calendar-cell.selected-day .calendar-day-number {
        color: @accent_color;
        font-weight: 800;
    }
    .calendar-weekday {
        font-size: 0.8em;
        font-weight: 700;
        opacity: 0.5;
    }
    .lesson-dot {
        min-width: 7px;
        min-height: 7px;
        border-radius: 9999px;
        background-color: @success_bg_color;
    }
    .lesson-label { font-size: 0.78em; opacity: 0.65; }

    /* Attendance ("check-in") dot states (defined after .lesson-dot so they win).
     * Adwaita semantic colours so they track the theme: present = success (green),
     * late = accent (blue), absent = error (red). Upcoming lessons show no dot
     * (transparent, but keep the space so the rows stay aligned). */
    .lesson-dot-present  { background-color: @success_bg_color; }
    .lesson-dot-late     { background-color: @accent_bg_color; }
    .lesson-dot-absent   { background-color: @error_bg_color; }
    .lesson-dot-warning  { background-color: @warning_bg_color; }
    .lesson-dot-upcoming { background-color: transparent; }

    /* Absence dialog — large vertical time steppers (GNOME Settings style). */
    .time-field { font-size: 1.6em; }
    .time-field text { padding-left: 2px; padding-right: 2px; }
    .time-colon { font-size: 1.6em; font-weight: 700; opacity: 0.55; }
    """;

    private bool widget_styles_loaded = false;

    /* Make sure the shared widget stylesheet is registered for the widget's
     * display. Safe to call repeatedly; it only does work once. */
    internal void ensure_widget_styles (Gtk.Widget widget) {
        if (widget_styles_loaded) {
            return;
        }

        // A widget that is not yet realized (e.g. a dialog before it is
        // presented) has no display of its own; fall back to the default.
        var display = widget.get_display () ?? Gdk.Display.get_default ();
        if (display == null) {
            return;
        }

        var provider = new Gtk.CssProvider ();
        provider.load_from_string (WIDGET_CSS);
        Gtk.StyleContext.add_provider_for_display (
            display,
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );

        widget_styles_loaded = true;
    }

    /* Turn an empty Box into a lesson dot coloured by the lesson's attendance.
     * The attendance is derived from the lesson's own AbsenceStatus, so it's
     * already correct when the row is built (no live update needed). */
    internal void bind_lesson_dot (Gtk.Box dot, TimetableItem lesson) {
        dot.add_css_class ("lesson-dot");
        dot.add_css_class (attendance_dot_class (lesson));
    }

    /* The dot class for a lesson. Upcoming lessons have no attendance yet, so no
     * dot — except an upcoming lesson you can't be absent from, which is flagged
     * (warning) since attendance is mandatory. Past lessons show their attendance. */
    internal string attendance_dot_class (TimetableItem lesson) {
        if (lesson.is_upcoming) {
            return lesson.allow_absence ? "lesson-dot-upcoming" : "lesson-dot-warning";
        }
        switch (lesson.attendance) {
            case AttendanceStatus.PRESENT: return "lesson-dot-present";
            case AttendanceStatus.LATE:    return "lesson-dot-late";
            case AttendanceStatus.ABSENT:  return "lesson-dot-absent";
            default:                       return "lesson-dot-upcoming";
        }
    }
}
