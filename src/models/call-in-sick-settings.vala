/* call-in-sick-settings.vala
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

    /* The school's "call in sick" policy, mirroring
     * AppSettings.AbsenceCallInSickSettings from the login response. Only the
     * field the client acts on is modelled; the rest of the object is ignored. */
    public class CallInSickSettings : Entity {
        // After this local wall-clock time the backend ignores a call-in-sick,
        // e.g. "20:30". Empty when the school sends none.
        public string ignore_message_start { get; set; default = ""; }

        /* `ignore_message_start` as minutes-since-midnight, or -1 if absent /
         * unparseable. Lets Session.can_call_in_sick compare against "now". */
        public int cutoff_minutes {
            get {
                string[] parts = ignore_message_start.split (":");
                if (parts.length != 2) {
                    return -1;
                }
                int hour = int.parse (parts[0]);
                int minute = int.parse (parts[1]);
                if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
                    return -1;
                }
                return hour * 60 + minute;
            }
        }
    }
}
