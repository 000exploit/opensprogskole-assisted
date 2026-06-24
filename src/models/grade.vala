/* grade.vala
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

    /* A colour intent for a grade, independent of any particular grading scale.
     * The Grades widget maps a tone to a chip colour and nothing more, so the
     * widget never has to know whether a school uses points, pass/fail, letters
     * or anything else. Per-school scales are turned into a tone + a label by a
     * normalizer (see apply_danish_scale), keeping the widget scale-agnostic. */
    public enum GradeTone {
        NEUTRAL,
        SUCCESS,
        ACCENT,
        WARNING,
        ERROR;

        /* CSS class applied to the chip for this tone (see styles.vala). */
        public string css_class () {
            switch (this) {
                case SUCCESS: return "grade-success";
                case ACCENT:  return "grade-accent";
                case WARNING: return "grade-warning";
                case ERROR:   return "grade-error";
                default:      return "grade-neutral";
            }
        }
    }

    /* A single grade as the UI wants to show it: already normalized to a short
     * chip label plus a tone. The course / assessment / date are display text.
     *
     * Keeping the model presentation-normalized (rather than carrying a raw
     * value + a scale) means a new school only needs a new normalizer; no
     * widget or model change is required to support a different grading scale. */
    public class GradeItem : Entity {
        // Fields filled from the backend JSON (PascalCase -> snake_case via the
        // Entity base, e.g. "DueDate" -> due_date, "GradeValue" -> grade_value).
        public string course { get; set; default = ""; }
        public string course_level { get; set; default = ""; }
        public string course_description { get; set; default = ""; }
        public string course_short_description { get; set; default = ""; }
        public string due_date { get; set; default = ""; }
        public string grade_value { get; set; default = ""; }
        public string grade_value_description { get; set; default = ""; }
        public string grade_scale { get; set; default = ""; }
        public string grade_scale_description { get; set; default = ""; }
        public string evaluation_form { get; set; default = ""; }
        public string evaluation_form_description { get; set; default = ""; }
        public string ects { get; set; default = ""; } // acronym: not auto-mapped

        // Presentation fields, set by a normalizer (not from JSON).
        public string display_label { get; set; default = ""; }
        public GradeTone tone { get; set; default = GradeTone.NEUTRAL; }

        public GradeItem (string course, string grade_scale, string display_label,
                      GradeTone tone, string due_date) {
            Object (
                course: course,
                grade_scale: grade_scale,
                display_label: display_label,
                tone: tone,
                due_date: due_date
            );
        }

        /* Set display_label + tone from this grade's grade_value, for the Danish
         * school context: the 7-point scale (12, 10, 7, 4, 02, 00, -3) and
         * pass/fail (bestået / ikke bestået, in any case). Call this after
         * deserializing a real GetGrades item so the widget has a tone to show.
         *
         * A different country/school adds its own apply_* normalizer; the widget
         * is unaffected. */
        public void apply_danish_scale () {
            string raw = grade_value.strip ();
            string label = raw;
            GradeTone t;

            switch (raw.down ()) {
                case "12":
                case "10":
                    t = GradeTone.SUCCESS;
                    break;
                case "7":
                case "4":
                    t = GradeTone.ACCENT;
                    break;
                case "02":
                    t = GradeTone.WARNING;
                    break;
                case "00":
                case "-3":
                    t = GradeTone.ERROR;
                    break;
                case "bestået":
                    t = GradeTone.SUCCESS;
                    label = "✓";
                    break;
                case "ikke bestået":
                    t = GradeTone.ERROR;
                    label = "✗";
                    break;
                default:
                    t = GradeTone.NEUTRAL;
                    break;
            }

            display_label = label;
            tone = t;
        }
    }
}
