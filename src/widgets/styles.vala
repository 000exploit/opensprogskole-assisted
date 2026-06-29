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

    /* The shared widget stylesheet (data/style.css, bundled as a GResource) is
     * registered once per display, the first time any of the widgets is
     * constructed. The CSS uses libadwaita's named colours so the widgets follow
     * the active light/dark theme and accent. */
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
        provider.load_from_resource ("/moe/ekusu/sprogskole/style.css");
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
