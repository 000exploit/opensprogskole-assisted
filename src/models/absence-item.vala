/* absence-item.vala
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

    /* One registered absence, mirroring an element of the backend's
     * GetUserAbsence -> "StudentRegisteredAbsence" array. Entity maps the
     * PascalCase members and parses the ISO datetimes. */
    public class AbsenceItem : Entity {
        public string event_id { get; set; default = ""; }
        public string activity_short_description { get; set; default = ""; }
        public string activity_description { get; set; default = ""; }
        public string student_reason { get; set; default = ""; }
        public DateTime? start_date { get; set; }
        public DateTime? start_time { get; set; }
        public DateTime? end_time { get; set; }
        public int status { get; set; default = 0; }
        public int minutes_absence { get; set; default = 0; }
        public int minutes_total { get; set; default = 0; }

        /* The lesson this absence is for. */
        public string subject {
            owned get {
                return activity_short_description != ""
                    ? activity_short_description : activity_description;
            }
        }

        /* "Wed, 17 Jun 2026 · 13:40 – 14:45" style summary for a row. */
        public string when_label {
            owned get {
                if (start_time == null) {
                    return "";
                }
                string day = start_time.format ("%a, %-d %b %Y");
                if (end_time != null) {
                    return "%s · %s – %s".printf (day,
                        start_time.format ("%H:%M"), end_time.format ("%H:%M"));
                }
                return day;
            }
        }
    }
}
