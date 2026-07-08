/* tile-attendance-wave.vala
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

    /* A Material-You-Expressive gauge: a rounded box filled from the bottom to
     * `fraction`, the fill's top edge a gently moving sine wave, big digits +
     * a short label centred on top. Custom-drawn via Gtk.Snapshot; the fill
     * colour follows the theme accent (a CSS class sets `color`). */
    public class WaveGauge : Gtk.Widget {

        private const double CORNER = 18.0;
        private const double WAVE_AMPLITUDE = 5.0;
        private const double WAVE_CYCLES = 1.6;   // crests across the width
        private const double FILL_ALPHA = 0.85;

        private Label value_label;
        private Label caption_label;

        /* 0..1 fill height (animated by the controller). */
        public double fraction { get; set; default = 0.0; }
        /* Radians; advanced continuously to animate the wave. */
        public double phase { get; set; default = 0.0; }

        construct {
            add_css_class ("attendance-wave");
            set_layout_manager (new Gtk.BinLayout ());

            value_label = new Label ("—") { halign = Align.CENTER };
            value_label.add_css_class ("title-1");
            caption_label = new Label ("") { halign = Align.CENTER };
            caption_label.add_css_class ("caption");

            var box = new Box (Orientation.VERTICAL, 2) {
                halign = Align.CENTER,
                valign = Align.CENTER
            };
            box.append (value_label);
            box.append (caption_label);
            box.set_parent (this);

            notify["fraction"].connect (queue_draw);
            notify["phase"].connect (queue_draw);
        }

        ~WaveGauge () {
            var child = get_first_child ();
            if (child != null) {
                child.unparent ();
            }
        }

        public void set_values (string big, string caption) {
            value_label.label = big;
            caption_label.label = caption;
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            int w = get_width ();
            int h = get_height ();
            if (w <= 0 || h <= 0) {
                base.snapshot (snapshot);
                return;
            }

            var bounds = Graphene.Rect ();
            bounds.init (0, 0, w, h);
            var rrect = Gsk.RoundedRect ();
            rrect.init_from_rect (bounds, (float) CORNER);
            snapshot.push_rounded_clip (rrect);

            // The wave-filled region, drawn with Cairo (a sine top edge is
            // fiddlier as a Gsk path). Colour = the CSS `color` (accent).
            double frac = fraction.clamp (0.0, 1.0);
            double base_y = h * (1.0 - frac);
            var cr = snapshot.append_cairo (bounds);
            var c = get_color ();
            cr.set_source_rgba (c.red, c.green, c.blue, FILL_ALPHA);
            cr.move_to (0, h);
            cr.line_to (0, base_y);
            for (double x = 0; x <= w; x += 2.0) {
                double y = base_y
                    + Math.sin ((x / w) * 2.0 * Math.PI * WAVE_CYCLES + phase)
                      * WAVE_AMPLITUDE;
                cr.line_to (x, y);
            }
            cr.line_to (w, h);
            cr.close_path ();
            cr.fill ();

            snapshot.pop ();   // rounded clip

            base.snapshot (snapshot);   // the labels, on top
        }
    }
}
