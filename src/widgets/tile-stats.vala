/* tile-stats.vala
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

    /* A single big-number stat as a pressable tile (à la the mockup's "4
     * lessons today", "8.6 average grade"). The whole tile is a flat button
     * that opens the related page. Subclasses supply the value + caption + the
     * page to open. */
    public abstract class StatWidget : DashboardWidget {

        protected Session? session = null;
        private Label? value_label = null;
        private Label? caption_label = null;

        /* Where pressing the tile navigates ("schedule", "grades", ...). */
        protected abstract string open_section { get; }

        /* Recompute value + caption from the session; return false to show the
         * tile's loading/error state instead (via out `error`). */
        protected abstract bool compute (out string value, out string caption,
                                         out string error);

        /* The Session signal that should re-render this stat. */
        protected abstract void subscribe (Session session, DashboardTile tile);

        public override Gtk.Widget build (DashboardTile tile) {
            return create_presenter (tile);
        }

        public override void bind (Session session, DashboardTile tile) {
            this.session = session;
            subscribe (session, tile);
            render (tile);
        }

        public override void relayout (DashboardTile tile) {
            tile.set_content (create_presenter (tile));
            render (tile);
        }

        private Gtk.Widget create_presenter (DashboardTile tile) {
            value_label = new Label ("—") { halign = Align.CENTER };
            value_label.add_css_class ("title-1");
            caption_label = new Label ("") {
                halign = Align.CENTER,
                wrap = true,
                justify = Justification.CENTER
            };
            caption_label.add_css_class ("dim-label");

            var box = new Box (Orientation.VERTICAL, 2) {
                halign = Align.CENTER,
                valign = Align.CENTER
            };
            box.append (value_label);
            box.append (caption_label);

            var button = new Button () { child = box };
            button.add_css_class ("flat");
            button.add_css_class ("wave-button");   // flush inset like the gauges
            button.clicked.connect (() => navigate (open_section));
            return button;
        }

        protected void render (DashboardTile tile) {
            if (session == null) {
                return;
            }
            string value, caption, error;
            if (!compute (out value, out caption, out error)) {
                tile.show_loading (error);
                return;
            }
            value_label.label = value;
            caption_label.label = caption;
            tile.show_content ();
        }
    }

    /* Number of lessons scheduled today. */
    public class LessonsTodayWidget : StatWidget {
        protected override string open_section { get { return "schedule"; } }

        protected override void subscribe (Session session, DashboardTile tile) {
            track (session, session.timetable_updated.connect (() => render (tile)));
            track (session, session.updated.connect (() => render (tile)));
        }

        protected override bool compute (out string value, out string caption,
                                         out string error) {
            value = "0";
            caption = _("lessons today");
            error = "";
            if (session.timetable_state != LoadState.LOADED) {
                error = session.timetable_state == LoadState.FAILED
                    ? _("Couldn't load lessons.") : "";
                return false;
            }
            var today = new DateTime.now_local ().format ("%Y-%m-%d");
            var model = session.timetable.get_day_for_key (today);
            value = ((int) (model != null ? model.get_n_items () : 0)).to_string ();
            return true;
        }
    }

    /* Mean of the numeric grades (non-numeric ones — pass/fail — are skipped). */
    public class AverageGradeWidget : StatWidget {
        protected override string open_section { get { return "grades"; } }

        protected override void subscribe (Session session, DashboardTile tile) {
            track (session.grades, session.grades.items_changed.connect (() => render (tile)));
            track (session, session.updated.connect (() => render (tile)));
        }

        protected override bool compute (out string value, out string caption,
                                         out string error) {
            value = "—";
            caption = _("average grade");
            error = "";
            if (session.grades_state != LoadState.LOADED) {
                error = session.grades_state == LoadState.FAILED
                    ? _("Couldn't load grades.") : "";
                return false;
            }
            double sum = 0.0;
            int n = 0;
            for (uint i = 0; i < session.grades.get_n_items (); i++) {
                var g = (GradeItem) session.grades.get_item (i);
                double v;
                if (double.try_parse (g.grade_value.replace (",", "."), out v)) {
                    sum += v;
                    n++;
                }
            }
            if (n == 0) {
                caption = _("no numeric grades");
                return true;   // value stays "—"
            }
            value = "%.1f".printf (sum / n);
            return true;
        }
    }
}
