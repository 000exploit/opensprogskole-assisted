/* future-absence-item.vala
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

    /* One element of GetFutureStudentAbsence — a student-reported absence the
     * student still owns, so it can be edited (UpdateFutureStudentAbsence) or
     * removed (DeleteFutureStudentAbsence). These are the *editable* counterpart
     * to the read-only registered absences (AbsenceItem): the backend's only way
     * to change an absence — even one now in the past — is to update its future
     * record, so this is what the Absence page exposes edit/delete actions on.
     *
     * Not an Entity: the JSON keys are all-caps ("ID", "SLI_ID") which the
     * PascalCase→kebab mapper would mangle, so it's parsed by hand from the
     * Json.Object instead. */
    public class FutureAbsenceItem : GLib.Object {

        // Identifies the record for update/delete. SLI_ID is sent back on
        // update for completeness, but only ID actually matters to the backend.
        public int id { get; set; default = 0; }
        public int sli_id { get; set; default = 0; }
        public string reason { get; set; default = ""; }
        public DateTime? start_date_time { get; set; }
        public DateTime? end_date_time { get; set; }
        // Server's "computed at" stamp; opaque to us, kept only to round-trip.
        public string when_calculated { get; set; default = ""; }

        /* "Wed, 1 Jul 2026 · 08:30 – 14:45" style summary for a list row. */
        public string when_label {
            owned get {
                if (start_date_time == null) {
                    return "";
                }
                string day = start_date_time.format ("%a, %-d %b %Y");
                if (end_date_time != null) {
                    return "%s · %s – %s".printf (day,
                        start_date_time.format ("%H:%M"),
                        end_date_time.format ("%H:%M"));
                }
                return day;
            }
        }

        /* Parse one array element; null if it isn't an object. */
        public static FutureAbsenceItem? from_json (Json.Node element) {
            if (element.get_node_type () != Json.NodeType.OBJECT) {
                return null;
            }
            var o = element.get_object ();
            return new FutureAbsenceItem () {
                id = (int) o.get_int_member_with_default ("ID", 0),
                sli_id = (int) o.get_int_member_with_default ("SLI_ID", 0),
                reason = o.get_string_member_with_default ("Reason", ""),
                start_date_time = parse_iso (o, "StartDateTime"),
                end_date_time = parse_iso (o, "EndDateTime"),
                when_calculated = o.get_string_member_with_default ("WhenCalculated", "")
            };
        }

        private static DateTime? parse_iso (Json.Object o, string key) {
            if (!o.has_member (key)) {
                return null;
            }
            var node = o.get_member (key);
            if (node.get_node_type () != Json.NodeType.VALUE) {
                return null;
            }
            string? s = node.get_string ();
            if (s == null || s == "") {
                return null;
            }
            return new DateTime.from_iso8601 (s, new TimeZone.local ());
        }
    }
}
