/* dashboard-registry.vala
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

    /* Everything the dashboard needs to know about a widget type without
     * building it: its display metadata (for the add picker), the data it
     * needs (to filter by provider capability), a default size, and the GType
     * of its DashboardWidget controller (to instantiate a placed tile). */
    public class WidgetInfo : GLib.Object {
        // Plain fields (not construct) — a GObject array property is awkward in
        // Vala, and this is just an immutable descriptor.
        public string type_id;
        public string title;              // picker label (translated)
        public string icon_name;
        public DataKind required_capability;
        public GLib.Type controller_type;
        // The sizes this widget can take, in cycle order (the resize button
        // steps through them). The first is the default.
        public WidgetSize[] sizes;

        public WidgetInfo (string type_id, string title, string icon_name,
                           DataKind required_capability, GLib.Type controller_type,
                           WidgetSize[] sizes) {
            this.type_id = type_id;
            this.title = title;
            this.icon_name = icon_name;
            this.required_capability = required_capability;
            this.controller_type = controller_type;
            this.sizes = sizes;
        }

        public WidgetSize default_size {
            get { return sizes[0]; }
        }

        /* The next size in the cycle after `current` (wraps). */
        public WidgetSize next_size (WidgetSize current) {
            for (int i = 0; i < sizes.length; i++) {
                if (sizes[i] == current) {
                    return sizes[(i + 1) % sizes.length];
                }
            }
            return sizes[0];
        }
    }

    /* The catalogue of dashboard widget types. A singleton (like Connectivity)
     * that registers the built-ins once; the DashboardView reads it to build
     * tiles from a saved layout and to populate the add-widget picker. */
    public class DashboardWidgetRegistry : GLib.Object {

        private static DashboardWidgetRegistry? _default = null;

        public static unowned DashboardWidgetRegistry get_default () {
            if (_default == null) {
                _default = new DashboardWidgetRegistry ();
            }
            return _default;
        }

        // Insertion-ordered: a lookup table plus a list so the picker shows a
        // stable order.
        private GLib.HashTable<string, WidgetInfo> by_id =
            new GLib.HashTable<string, WidgetInfo> (str_hash, str_equal);
        private GLib.GenericArray<WidgetInfo> ordered = new GLib.GenericArray<WidgetInfo> ();

        private DashboardWidgetRegistry () {
            register_builtins ();
        }

        private void register (WidgetInfo info) {
            by_id.insert (info.type_id, info);
            ordered.add (info);
        }

        public WidgetInfo? lookup (string type_id) {
            return by_id.lookup (type_id);
        }

        public GLib.GenericArray<WidgetInfo> all () {
            return ordered;
        }

        /* A fresh controller for `type_id`, or null if the id is unknown — the
         * forward-compat escape hatch when a saved layout names a widget this
         * build doesn't have. */
        public DashboardWidget? create (string type_id) {
            var info = by_id.lookup (type_id);
            if (info == null) {
                return null;
            }
            return (DashboardWidget) Object.new (info.controller_type);
        }

        private void register_builtins () {
            register (new WidgetInfo ("up-next", _("Up next"),
                "appointment-soon-symbolic", DataKind.TIMETABLE,
                typeof (UpNextWidget),
                { WidgetSize.FULL, WidgetSize.MINI }));
            // One attendance widget, two looks: a donut when full/half, the
            // expressive wave gauge when mini (switch via the resize button).
            register (new WidgetInfo ("attendance", _("Attendance"),
                "object-select-symbolic", DataKind.ABSENCE,
                typeof (AttendanceWidget),
                { WidgetSize.HALF, WidgetSize.MINI, WidgetSize.FULL }));
            register (new WidgetInfo ("recent-grades", _("Grades"),
                "starred-symbolic", DataKind.GRADES,
                typeof (RecentGradesWidget),
                { WidgetSize.FULL, WidgetSize.MINI }));
            register (new WidgetInfo ("lessons-today", _("Lessons today"),
                "appointment-soon-symbolic", DataKind.TIMETABLE,
                typeof (LessonsTodayWidget),
                { WidgetSize.MINI, WidgetSize.HALF }));
            register (new WidgetInfo ("average-grade", _("Average grade"),
                "starred-symbolic", DataKind.GRADES,
                typeof (AverageGradeWidget),
                { WidgetSize.MINI, WidgetSize.HALF }));
        }
    }
}
