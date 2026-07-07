/* ums-endpoints.vala
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

    /* The UMS REST surface in one place (the official C# app keeps the same
     * kind of registry). Each constant is the fixed part of the path; query
     * strings and trailing segments are appended by the caller. describe()
     * maps a path back to a user-facing operation name for error reporting. */
    namespace UmsEndpoints {

        public const string AUTHENTICATE          = "/Login/Authenticate";
        public const string DELETE_TOKEN          = "/Login/DeleteToken";
        public const string GET_TIMETABLE         = "/Timetable/GetTimetable";
        public const string GET_GRADES            = "/Grades/GetGrades";
        public const string GET_USER_ABSENCE      = "/Absence/GetUserAbsence";
        public const string GET_ABSENCE_SETTINGS  = "/Absence/GetAbsenceSettings";
        public const string CREATE_ABSENCE_REASON = "/Absence/CreateAbsenceReason";
        public const string CALL_IN_SICK          = "/Absence/StudentCallInSick";
        public const string GET_FUTURE_ABSENCE    = "/Absence/GetFutureStudentAbsence";
        public const string CREATE_FUTURE_ABSENCE = "/Absence/CreateFutureStudentAbsence";
        public const string UPDATE_FUTURE_ABSENCE = "/Absence/UpdateFutureStudentAbsence";
        public const string DELETE_FUTURE_ABSENCE = "/Absence/DeleteFutureStudentAbsence";
        public const string GET_USER_INFO         = "/UserInfo/GetUserInfo";
        public const string GET_USER_INFO_SETTINGS = "/UserInfo/GetUserInfoSettings";
        public const string UPDATE_USER_INFO      = "/UserInfo/UpdateUserInfo";
        public const string UPDATE_USER_IMAGE     = "/UserInfo/UpdateUserImage";
        public const string DELETE_PENDING_IMAGE  = "/UserInfo/DeletePendingImage";

        /* The user-facing name of the operation behind `path` (a URI path,
         * possibly with the /api base and trailing segments), or null for a
         * path outside the registry. Matched by containment because the
         * base prefix varies; GET_USER_INFO_SETTINGS must be checked before
         * its prefix GET_USER_INFO. */
        public unowned string? describe (string path) {
            if (path.contains (AUTHENTICATE))           return _("Login");
            if (path.contains (DELETE_TOKEN))           return _("Logout");
            if (path.contains (GET_TIMETABLE))          return _("Timetable");
            if (path.contains (GET_GRADES))             return _("Grades");
            if (path.contains (GET_USER_ABSENCE))       return _("Absence");
            if (path.contains (GET_ABSENCE_SETTINGS))   return _("Absence settings");
            if (path.contains (CREATE_ABSENCE_REASON))  return _("Absence reason");
            if (path.contains (CALL_IN_SICK))           return _("Call in sick");
            if (path.contains (GET_FUTURE_ABSENCE))     return _("Reported absences");
            if (path.contains (CREATE_FUTURE_ABSENCE))  return _("Report absence");
            if (path.contains (UPDATE_FUTURE_ABSENCE))  return _("Update reported absence");
            if (path.contains (DELETE_FUTURE_ABSENCE))  return _("Delete reported absence");
            if (path.contains (GET_USER_INFO_SETTINGS)) return _("Profile settings");
            if (path.contains (UPDATE_USER_INFO))       return _("Save profile");
            if (path.contains (UPDATE_USER_IMAGE))      return _("Upload profile picture");
            if (path.contains (DELETE_PENDING_IMAGE))   return _("Remove pending picture");
            if (path.contains (GET_USER_INFO))          return _("Profile");
            return null;
        }
    }
}
