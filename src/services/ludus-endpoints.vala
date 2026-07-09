/* ludus-endpoints.vala
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

    /* The LUDUS REST surface on the API gateway. Paths are recovered from the
     * Flutter app dump. Query strings / trailing segments are appended
     * by the caller.
     *
     * NOTE: only the school directory (info-service/schools) is verified live.
     * The rest are path-only — their response shapes are unconfirmed, so the
     * provider's parsing is best-effort until checked against a real account. */
    namespace LudusEndpoints {

        // Reads.
        public const string TIMETABLE       = "/skema/v1";
        public const string TIMETABLE_ELEMS = "/skemaElementer";
        public const string ABSENCE         = "/fravaer/v1/bruger";
        public const string ABSENCE_OVERVIEW = "/fravaersoversigt";
        public const string ABSENCE_REASONS = "/fravaersaarsager";
        public const string MISSING_REASONS = "/manglendefravaersaarsager";
        public const string ASSIGNMENTS     = "/opgaver";
        public const string MESSAGES        = "/beskeder";
        public const string STUDENT         = "/students/v1";
        public const string PROFILE_PICTURE = "/profile-picture";
        public const string CONFIGURATIONS  = "/configurations/v1";

        // Writes.
        public const string ABSENCE_REGISTRATION = "/absenceRegistration";
        public const string MARK_AS_READ    = "/markAsRead";
        public const string MARK_AS_UNREAD  = "/markAsUnread";

        /* The user-facing name of the operation behind `path`, or null when it
         * isn't one of ours — feeds the error reporter's friendly summaries. */
        public unowned string? describe (string path) {
            if (path.contains (TIMETABLE))            return _("Timetable");
            if (path.contains (ABSENCE_REASONS))      return _("Absence reasons");
            if (path.contains (ABSENCE_OVERVIEW))     return _("Absence");
            if (path.contains (ABSENCE))              return _("Absence");
            if (path.contains (ASSIGNMENTS))          return _("Assignments");
            if (path.contains (MESSAGES))             return _("Messages");
            if (path.contains (STUDENT))              return _("Profile");
            if (path.contains (PROFILE_PICTURE))      return _("Profile picture");
            if (path.contains (CONFIGURATIONS))       return _("Configuration");
            if (path.contains (ABSENCE_REGISTRATION)) return _("Report absence");
            return null;
        }
    }
}
