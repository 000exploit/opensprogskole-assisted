/* timetable-item.vala
 *
 * Copyright 2026 flex
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

    /* One lesson / event in the timetable.
     *
     * This is the *normalized* in-app representation of a single entry of the
     * backend's timetable JSON. The raw JSON uses PascalCase keys (e.g.
     * "StartTime", "TimeTableRealStartDateTime") and HTML fragments inside some
     * fields, so two things happen here:
     *
     *   1. Deserialization is inherited from Entity: it maps PascalCase JSON
     *      members to the snake_case properties and parses ISO 8601 datetimes
     *      into real GLib.DateTime values, so json-glib fills the properties
     *      automatically (see TimetableItem.from_json_array).
     *
     *   2. Normalization. The values that are still awkward — "A, B, C" lists and
     *      HTML — are exposed through computed read-only getters, so the messy
     *      parsing lives in one obvious place instead of being smeared across the
     *      widgets.
     *
     * Only the fields the UI currently needs are declared as properties; any
     * other JSON member simply has no matching property and is ignored. */
    public class TimetableItem : Entity {

        // --- Raw fields, filled directly from JSON --------------------------

        public string subject { get; set; default = ""; }
        public string start_time { get; set; default = ""; }     // "08:15"
        public string end_time { get; set; default = ""; }       // "09:45"
        public string room { get; set; default = ""; }           // may contain <br>
        public string location { get; set; default = ""; }       // "201, 202, ..."
        public string teacher { get; set; default = ""; }        // "MAL, AKH, ..."
        public string homework { get; set; default = ""; }
        public string comment { get; set; default = ""; }
        public string body { get; set; default = ""; }           // HTML blob
        public string color { get; set; default = ""; }          // "Yellow", ...
        public string activity { get; set; default = ""; }       // "1BILABON2026F<br>"

        // Parsed by Entity from ISO 8601 (e.g. "2026-05-20T08:15:00") into real
        // GLib.DateTime values; null when the JSON omits them.
        public DateTime? time_table_real_start_date_time { get; set; }
        public DateTime? time_table_real_end_date_time { get; set; }
        // Day stamp (midnight), e.g. "2026-05-20T00:00:00".
        public DateTime? time_table_real_date { get; set; }

        // Per-lesson absence status (UMS "AbsenceStatus"); -1 = none reported.
        // Used to compute the attendance percentage on the overview.
        public int absence_status { get; set; default = -1; }

        // --- Computed helpers (normalization) -------------------------------

        /* "yyyy-mm-dd" key used to bucket the item by day in TimetableStore. */
        public string date_key {
            owned get {
                var stamp = time_table_real_date;
                return stamp != null ? stamp.format ("%Y-%m-%d") : "";
            }
        }

        /* Short aliases for the parsed start/end, or null if absent. */
        public DateTime? start_datetime {
            owned get { return time_table_real_start_date_time; }
        }

        public DateTime? end_datetime {
            owned get { return time_table_real_end_date_time; }
        }

        /* "08:15 – 09:45", falling back to whatever parts we have. */
        public string time_range {
            owned get {
                if (start_time != "" && end_time != "") {
                    return "%s – %s".printf (start_time, end_time);
                }
                return start_time + end_time;
            }
        }

        /* Teacher codes split out of the "MAL, AKH, ..." string. */
        public string[] teachers {
            owned get { return split_list (teacher); }
        }

        /* Room names. The "Room" field is an HTML list ("201 - Undervisning<br>
         * 202 - ..."); "Location" is a plain "201, 202, ..." list. Prefer the
         * cleaner Location, fall back to the stripped Room field. */
        public string[] rooms {
            owned get {
                if (location.strip () != "") {
                    return split_list (location);
                }
                return split_list (strip_html (room));
            }
        }

        /* The activity / course code without the trailing "<br>". */
        public string activity_code {
            owned get {
                string code = strip_html (activity).strip ();
                while (code.has_suffix (",")) {
                    code = code.substring (0, code.length - 1).strip ();
                }
                return code;
            }
        }

        /* A short label for the calendar marker: the first word of the subject
         * (e.g. "Dansk", "Branche/IT"). Heuristic — good enough for a dot. */
        public string short_label {
            owned get {
                var trimmed = subject.strip ();
                int space = trimmed.index_of (" ");
                return space > 0 ? trimmed.substring (0, space) : trimmed;
            }
        }

        // --- Construction from JSON -----------------------------------------

        /* Deserialize a JSON array of timetable entries into a list of items. */
        public static GLib.GenericArray<TimetableItem> from_json_array (Json.Array array) {
            var items = new GLib.GenericArray<TimetableItem> ();
            array.foreach_element ((arr, index, node) => {
                var obj = Json.gobject_deserialize (typeof (TimetableItem), node);
                items.add ((TimetableItem) obj);
            });
            return items;
        }

        // --- Static helpers --------------------------------------------------
        // (JSON member -> property mapping and ISO 8601 -> DateTime parsing are
        // handled by the Entity base class.)

        private static string strip_html (string value) {
            // Replace the <br> separators with commas, then drop any remaining
            // tags. Good enough for the simple fragments the backend sends.
            string text = value.replace ("<br>", ", ").replace ("\r", " ").replace ("\n", " ");
            var builder = new StringBuilder ();
            bool in_tag = false;
            for (int i = 0; i < text.length; i++) {
                char c = text[i];
                if (c == '<') {
                    in_tag = true;
                } else if (c == '>') {
                    in_tag = false;
                } else if (!in_tag) {
                    builder.append_c (c);
                }
            }
            return builder.str;
        }

        private static string[] split_list (string value) {
            var result = new GLib.GenericArray<string> ();
            foreach (string part in value.split (",")) {
                string trimmed = part.strip ();
                if (trimmed != "") {
                    result.add (trimmed);
                }
            }
            return result.steal ();
        }
    }
}
