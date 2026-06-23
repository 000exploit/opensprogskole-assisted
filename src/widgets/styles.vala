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

    /* Lesson dot colour variants (defined after .lesson-dot so they win).
     * Map the backend's category colour names to the Adwaita-ish palette. */
    .lesson-dot-accent { background-color: @accent_bg_color; }
    .lesson-dot-yellow { background-color: #f5c211; }
    .lesson-dot-green  { background-color: #2ec27e; }
    .lesson-dot-red    { background-color: #e01b24; }
    .lesson-dot-blue   { background-color: #3584e4; }
    .lesson-dot-orange { background-color: #ff7800; }
    .lesson-dot-purple { background-color: #9141ac; }
    .lesson-dot-teal   { background-color: #1a9ba4; }
    .lesson-dot-pink   { background-color: #d56199; }
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

    /* Map a backend category colour name (e.g. "Yellow") to the CSS class that
     * colours a lesson dot. Unknown names fall back to the accent colour. Used
     * by the day-lessons and agenda rows. */
    internal string lesson_dot_class (string color) {
        switch (color.down ()) {
            case "yellow": return "lesson-dot-yellow";
            case "green":  return "lesson-dot-green";
            case "red":    return "lesson-dot-red";
            case "blue":   return "lesson-dot-blue";
            case "orange": return "lesson-dot-orange";
            case "purple": return "lesson-dot-purple";
            case "teal":   return "lesson-dot-teal";
            case "pink":   return "lesson-dot-pink";
            default:       return "lesson-dot-accent";
        }
    }
}
