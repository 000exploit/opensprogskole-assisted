/* tile-attendance.vala
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

    /* Attendance tile, two looks by size: a donut Chart + caption when full or
     * half, the expressive wave gauge when mini. The resize button switches
     * between them. */
    public class AttendanceWidget : DashboardWidget {

        private const uint WAVE_PERIOD_MS = 2600;

        private Session? session = null;

        // Donut presenter.
        private Chart? chart = null;
        private Label? caption = null;

        // Mini (wave) presenter.
        private WaveGauge? gauge = null;
        private Adw.TimedAnimation? wave = null;   // loops forever while mini

        private static bool is_mini (DashboardTile tile) {
            return tile.config.size == WidgetSize.MINI;
        }

        public override Gtk.Widget build (DashboardTile tile) {
            return create_presenter (tile);
        }

        public override void bind (Session session, DashboardTile tile) {
            this.session = session;
            session.absence_updated.connect (() => render (tile));
            render (tile);
        }

        public override void relayout (DashboardTile tile) {
            tile.set_content (create_presenter (tile));
            render (tile);
        }

        private Gtk.Widget create_presenter (DashboardTile tile) {
            if (is_mini (tile)) {
                chart = null;
                caption = null;
                gauge = new WaveGauge ();
                // A continuous, linear phase loop — the "alive" wave motion.
                var target = new Adw.CallbackAnimationTarget ((v) => gauge.phase = v);
                wave = new Adw.TimedAnimation (gauge, 0.0, 2.0 * Math.PI,
                                               WAVE_PERIOD_MS, target);
                wave.easing = Adw.Easing.LINEAR;
                wave.repeat_count = 0;   // forever
                wave.play ();
                return gauge;
            }

            gauge = null;
            wave = null;   // old loop stops once its (unmapped) gauge is dropped
            chart = new Chart ();
            caption = new Label ("") {
                wrap = true,
                justify = Justification.CENTER,
                halign = Align.CENTER
            };
            caption.add_css_class ("caption");
            caption.add_css_class ("dim-label");
            var box = new Box (Orientation.VERTICAL, 8) { halign = Align.CENTER };
            box.append (chart);
            box.append (caption);
            return box;
        }

        private void render (DashboardTile tile) {
            if (session == null || session.absence_state != LoadState.LOADED) {
                tile.show_loading (session != null
                    && session.absence_state == LoadState.FAILED
                        ? _("Couldn't load attendance.") : "");
                return;
            }
            if (gauge != null) {
                render_wave ();
            } else {
                render_donut ();
            }
            tile.show_content ();
        }

        private void render_wave () {
            var s = session.absence_summary;
            if (s == null || s.total <= 0) {
                gauge.set_values ("—", _("no data"));
                animate_fill (0.0);
                return;
            }
            gauge.set_values ("%.0f%%".printf (s.present_percent), _("Present"));
            animate_fill (s.present_percent / 100.0);
        }

        private void render_donut () {
            var s = session.absence_summary;
            if (s == null || s.total <= 0) {
                chart.clear ();
                chart.add_segment (1.0, rgba ("#deddda"));
                chart.center_text = "—";
                chart.subtitle = _("no data");
                caption.label = _("No attendance data");
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
            caption.label = _("Present %.1f%% · Not approved %.1f%% · Late %.1f%%")
                .printf (pct (s.present, s.total), pct (s.illegal, s.total),
                         pct (s.late, s.total));
        }

        private void animate_fill (double target_fraction) {
            var target = new Adw.CallbackAnimationTarget ((v) => gauge.fraction = v);
            var spring = new Adw.SpringAnimation (gauge, gauge.fraction, target_fraction,
                new Adw.SpringParams (0.9, 1.0, 180.0), target);
            spring.epsilon = 0.001;
            spring.play ();
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
