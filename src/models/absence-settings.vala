/* absence-settings.vala
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

    /* The school's absence policy, mirroring /api/Absence/GetAbsenceSettings.
     * Only the fields the client acts on are declared; the rest of the (large)
     * payload is ignored. Entity maps the PascalCase members. */
    public class AbsenceSettings : Entity {
        // How many days back a student may still describe an absence reason.
        // 0 means describing past absences is disabled for this school.
        public int student_reason_days_back { get; set; default = 0; }
        // Whether the school surfaces absence reasons to students at all.
        public bool show_absence_reason { get; set; default = false; }
    }
}
