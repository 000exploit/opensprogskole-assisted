/* chart.vala
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

    /* A single coloured slice of the donut chart. */
    private struct ChartSegment {
        public double value;
        public Gdk.RGBA color;
    }

    /* A donut/ring chart with text in the middle, as used by the attendance
     * cards in the design. The ring is drawn with Cairo; the centre text is an
     * overlaid label so it picks up the regular theme typography.
     *
     * The widget only renders the data it is handed — computing the values and
     * choosing the colours is the caller's job. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/chart.ui")]
    public class Chart : Adw.Bin {

        [GtkChild]
        private unowned Gtk.DrawingArea area;
        [GtkChild]
        private unowned Gtk.Label center_label;
        [GtkChild]
        private unowned Gtk.Label sub_label;

        private ChartSegment[] segments;

        /* Thickness of the ring, in pixels. */
        public double line_width { get; set; default = 18.0; }

        /* Large text shown in the middle of the ring (e.g. "83.4%"). */
        public string center_text {
            owned get { return center_label.label; }
            set { center_label.label = value; }
        }

        /* Small caption under the centre text (e.g. "present"). */
        public string subtitle {
            owned get { return sub_label.label; }
            set {
                sub_label.label = value;
                sub_label.visible = value != "";
            }
        }

        construct {
            ensure_widget_styles (this);

            area.set_draw_func (draw);
            notify["line-width"].connect (() => area.queue_draw ());
        }

        /* Append a slice. Segments are drawn clockwise from the top in the
         * order they are added; their values are interpreted as relative
         * weights, so they need not sum to any particular total. */
        public void add_segment (double value, Gdk.RGBA color) {
            if (value < 0) {
                value = 0;
            }
            segments += ChartSegment () { value = value, color = color };
            area.queue_draw ();
        }

        /* Remove every slice. */
        public void clear () {
            segments = {};
            area.queue_draw ();
        }

        private void draw (Gtk.DrawingArea da, Cairo.Context cr, int width, int height) {
            double lw = line_width;
            double size = double.min (width, height);
            double radius = (size - lw) / 2.0;
            if (radius <= 0) {
                return;
            }

            double cx = width / 2.0;
            double cy = height / 2.0;

            cr.set_line_width (lw);
            cr.set_line_cap (Cairo.LineCap.BUTT);

            double total = 0;
            foreach (var seg in segments) {
                total += seg.value;
            }

            // No data yet: draw a faint placeholder ring.
            if (total <= 0) {
                Gdk.RGBA fg = get_color ();
                cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.12);
                cr.arc (cx, cy, radius, 0, 2 * Math.PI);
                cr.stroke ();
                return;
            }

            double start = -Math.PI / 2.0; // 12 o'clock
            foreach (var seg in segments) {
                if (seg.value <= 0) {
                    continue;
                }
                double end = start + (seg.value / total) * 2.0 * Math.PI;
                cr.set_source_rgba (seg.color.red, seg.color.green,
                                    seg.color.blue, seg.color.alpha);
                cr.arc (cx, cy, radius, start, end);
                cr.stroke ();
                start = end;
            }
        }
    }
}
