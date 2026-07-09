/* tile-grades.vala
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

    /* Grades tile. FULL: the Grades list. MINI: a wave gauge filled to the
     * share of "successful" works — a positive grade (passed / bestået, or a
     * good mark on the numeric scale), which GradeItem already classifies via
     * its tone. */
    public class RecentGradesWidget : DashboardWidget {

        private const uint WAVE_PERIOD_MS = 2600;

        private Session? session = null;

        // FULL presenter.
        private Grades? list = null;

        // MINI presenter.
        private WaveGauge? gauge = null;
        private Adw.TimedAnimation? wave = null;

        private static bool is_mini (DashboardTile tile) {
            return tile.config.size == WidgetSize.MINI;
        }

        public override Gtk.Widget build (DashboardTile tile) {
            return create_presenter (tile);
        }

        public override void bind (Session session, DashboardTile tile) {
            this.session = session;
            session.grades.items_changed.connect (() => render (tile));
            session.updated.connect (() => render (tile));
            render (tile);
        }

        public override void relayout (DashboardTile tile) {
            tile.set_content (create_presenter (tile));
            render (tile);
        }

        private Gtk.Widget create_presenter (DashboardTile tile) {
            if (is_mini (tile)) {
                list = null;
                gauge = new WaveGauge ();
                var target = new Adw.CallbackAnimationTarget ((v) => gauge.phase = v);
                wave = new Adw.TimedAnimation (gauge, 0.0, 2.0 * Math.PI,
                                               WAVE_PERIOD_MS, target);
                wave.easing = Adw.Easing.LINEAR;
                wave.repeat_count = 0;
                wave.play ();
                // The whole mini is a button → opens the Grades page.
                var button = new Button () { child = gauge };
                button.add_css_class ("flat");
                button.add_css_class ("wave-button");
                button.clicked.connect (() => navigate ("grades"));
                return button;
            }
            gauge = null;
            wave = null;
            list = new Grades ();
            // NOTE: bind to the model in render(), not here — build() runs
            // before bind(), so `session` is still null at this point (that was
            // the "grades empty until resized" bug).
            return list;
        }

        private void render (DashboardTile tile) {
            if (session == null) {
                return;
            }
            if (session.grades_state != LoadState.LOADED) {
                tile.show_loading (session.grades_state == LoadState.FAILED
                    ? _("Couldn't load grades.") : "");
                return;
            }
            if (gauge != null) {
                render_mini ();
                tile.show_content ();
                return;
            }
            // FULL: (re)bind the list to the live model now that we have the
            // session — safe to call repeatedly.
            list.bind (session.grades);
            if (session.grades.get_n_items () == 0) {
                tile.show_empty (_("No grades yet"),
                    _("Grades will appear here once your school posts them."),
                    "starred-symbolic");
                return;
            }
            tile.show_content ();
        }

        private void render_mini () {
            int passed = 0;
            int assessed = 0;
            for (uint i = 0; i < session.grades.get_n_items (); i++) {
                var g = (GradeItem) session.grades.get_item (i);
                // NEUTRAL = not really an assessment (e.g. a note); skip it.
                if (g.tone == GradeTone.NEUTRAL) {
                    continue;
                }
                assessed++;
                if (g.tone == GradeTone.SUCCESS || g.tone == GradeTone.ACCENT) {
                    passed++;
                }
            }
            if (assessed == 0) {
                gauge.set_values ("—", _("no grades"));
                animate_fill (0.0);
                return;
            }
            double rate = (double) passed / assessed;
            gauge.set_values ("%.0f%%".printf (rate * 100.0), _("passed"));
            animate_fill (rate);
        }

        private void animate_fill (double target_fraction) {
            var target = new Adw.CallbackAnimationTarget ((v) => gauge.fraction = v);
            var spring = new Adw.SpringAnimation (gauge, gauge.fraction, target_fraction,
                new Adw.SpringParams (0.9, 1.0, 180.0), target);
            spring.epsilon = 0.001;
            spring.play ();
        }
    }
}
