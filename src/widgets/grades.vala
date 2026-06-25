/* grades.vala
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

    /* A boxed list of grades. Each row is a Grade model: the widget only reads
     * the model's display_label (chip text) and tone (chip colour). It knows
     * nothing about grading scales — points, pass/fail or anything else are
     * already resolved to a label + tone by a normalizer (see Grade), so the
     * same widget serves every school. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/grades.ui")]
    public class Grades : Adw.Bin {

        [GtkChild]
        private unowned Gtk.ListBox list;

        construct {
            ensure_widget_styles (this);
        }

        /* Append a single grade row. */
        public void add_grade (GradeItem grade) {
            list.append (build_row (grade));
        }

        /* Bind to a live model of Grade objects. Replaces any manually added
         * rows; rows then track the model. */
        public void bind (GLib.ListModel? model) {
            list.bind_model (model, (object) => build_row ((GradeItem) object));
        }

        /* Remove every row (only meaningful when not bound to a model). */
        public void clear () {
            Gtk.Widget? child;
            while ((child = list.get_first_child ()) != null) {
                list.remove (child);
            }
        }

        private static Gtk.Widget build_row (GradeItem grade) {
            var chip = new Gtk.Label (grade.display_label) {
                valign = Gtk.Align.CENTER,
                halign = Gtk.Align.CENTER
            };
            chip.add_css_class ("grade-chip");
            chip.add_css_class (grade.tone.css_class ());

            var date = new Gtk.Label (grade.due_date_label) {
                valign = Gtk.Align.CENTER
            };
            date.add_css_class ("dim-label");

            var row = new Adw.ActionRow () {
                title = grade.course != "" ? grade.course : grade.grade_scale,
                subtitle = grade.evaluation_form != ""
                    ? grade.evaluation_form : grade.grade_scale_description
            };
            row.add_prefix (chip);
            row.add_suffix (date);
            return row;
        }
    }
}
