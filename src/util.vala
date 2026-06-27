/* util.vala
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

    /* Small, dependency-free helpers shared across the app. */

    /* The current UTC time in the ISO 8601 form the UMS backend emits, e.g.
     * "2026-06-27T19:23:15.0000000+00:00" (zeroed fractional part + explicit
     * UTC offset). Used as the WhenCalculated stamp on absence create/update. */
    public string current_utc_iso8601_time () {
        return new DateTime.now_utc ().format ("%Y-%m-%dT%H:%M:%S.0000000+00:00");
    }
}
