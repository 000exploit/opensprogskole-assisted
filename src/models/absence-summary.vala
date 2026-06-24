/* absence-summary.vala
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

    /* Attendance totals, mirroring GetUserAbsence -> "StudentAbsence". All
     * figures are in minutes. The overview's donut is built directly from these
     * (present / illegal = "not approved" / late), exactly as in the mockup. */
    public class AbsenceSummary : Entity {
        public int total_minutes { get; set; default = 0; }
        public int present { get; set; default = 0; }
        public int late { get; set; default = 0; }
        public int legal { get; set; default = 0; }    // approved absence
        public int illegal { get; set; default = 0; }  // "not approved"
        public int trend { get; set; default = 0; }
        public string name { get; set; default = ""; }
        public string login { get; set; default = ""; }

        /* Falls back to the sum of parts if TotalMinutes is missing. */
        public int total {
            get {
                return total_minutes > 0 ? total_minutes
                    : present + late + legal + illegal;
            }
        }

        public double present_percent {
            get { return total > 0 ? (double) present / total * 100.0 : 0.0; }
        }
    }
}
