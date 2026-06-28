/* school-provider.vala
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

    /* Multiple results from one load call (plain fields — mutated directly). */
    public class AbsenceData : GLib.Object {     // GetUserAbsence = list + summary
        public GLib.GenericArray<AbsenceItem> items = new GLib.GenericArray<AbsenceItem> ();
        public AbsenceSummary? summary = null;
    }
    public class AppConfig : GLib.Object {       // login AppSettings, token-free
        public GLib.GenericArray<LinkItem> links = new GLib.GenericArray<LinkItem> ();
        public int call_in_sick_cutoff = -1;     // minutes; -1 = none
    }

    /* The contract every language school's backend must satisfy.
     *
     * This is the seam that lets the app talk to several different schools: the
     * rest of the program depends only on this interface and the normalized
     * models, never on a specific school's API or wire format. A provider owns
     * its transport, its parsing, AND its offline caching — `load_*` returns ready
     * app models (or throws when it has neither network nor cache). Everything
     * above (Session) only orchestrates: stores, load state, signals. */
    public interface SchoolProvider : GLib.Object {

        /* Which school this provider serves. */
        public abstract School school { get; }

        /* Bind the provider to an account so it can build its per-account cache.
         * Called once before any load_*, after login/resume. */
        public abstract void use_account (string username);

        /* Authenticate. Returns true on success; throws on bad credentials. */
        public abstract async bool login (string username, string password)
            throws GLib.Error;

        /* End the server-side session, each backend its own way (default no-op).
         * Best effort — the caller logs out locally regardless. */
        public virtual async void logout () throws GLib.Error {}

        /* The student's timetable. */
        public abstract async GLib.GenericArray<TimetableItem> load_timetable ()
            throws GLib.Error;

        /* The student's reported absences + attendance summary. */
        public abstract async AbsenceData load_absence () throws GLib.Error;

        /* The student's grades (sorted, scale applied). */
        public abstract async GLib.GenericArray<GradeItem> load_grades ()
            throws GLib.Error;

        /* The student's profile, or null when there's nothing to update. */
        public abstract async UserInfoItem? load_user_info () throws GLib.Error;

        /* Which profile fields the school lets the student edit, or null. */
        public abstract async UserInfoSettings? load_user_info_settings ()
            throws GLib.Error;

        /* The student's own (editable) future absences (sorted). */
        public abstract async GLib.GenericArray<FutureAbsenceItem> load_future_absence ()
            throws GLib.Error;

        /* The school's absence policy (reason window, etc.), or null. Not cached. */
        public abstract async AbsenceSettings? load_absence_settings ()
            throws GLib.Error;

        /* Links + call-in-sick cutoff, from the (cached) login config. */
        public abstract async AppConfig load_app_config () throws GLib.Error;

        /* Persist the editable profile fields of `info`. Returns true on success. */
        public abstract async bool update_user_info (UserInfoItem info)
            throws GLib.Error;

        /* Upload a new profile picture (raw image bytes). It becomes a pending,
         * not-yet-approved picture server-side. Returns true on success. */
        public abstract async bool update_user_image (GLib.Bytes image)
            throws GLib.Error;

        /* Discard the pending (awaiting-approval) profile picture. Returns true
         * on success. */
        public abstract async bool delete_pending_image () throws GLib.Error;

        /* Download a profile picture by URL (raw image bytes), or null. */
        public abstract async GLib.Bytes? fetch_picture (string url)
            throws GLib.Error;

        /* Abort all in-flight requests immediately (e.g. connectivity lost), so
         * they fail now instead of stalling until their timeout. */
        public abstract void abort_requests ();

        /* Report a future absence; returns the new absence id. ISO datetimes are
         * "yyyy-MM-ddTHH:mm:ss". */
        public abstract async int create_future_absence (string reason,
                                                         string start_iso,
                                                         string end_iso)
            throws GLib.Error;

        /* Update an existing future absence (identified by `id`). The backend's
         * only way to edit any absence — even a past one — is to update its
         * future record. ISO datetimes are "yyyy-MM-ddTHH:mm:ss". */
        public abstract async void update_future_absence (int id, string reason,
                                                          string start_iso,
                                                          string end_iso)
            throws GLib.Error;

        /* Delete a future absence by id. */
        public abstract async void delete_future_absence (int id) throws GLib.Error;

        /* Describe (create or edit) the reason for one or more past absent lessons
         * at once, each keyed by its server + timetable ids (ServerId/EventId in
         * the absence response). The two arrays are parallel. */
        public abstract async void create_absence_reason (int[] server_ids,
                                                          string[] timetable_ids,
                                                          string reason)
            throws GLib.Error;

        /* Report today's absence ("call in sick"). Returns the backend's
         * (code, message) so the caller can surface the message. */
        public abstract async void student_call_in_sick (string reason, int type,
                                                         out int code,
                                                         out string message)
            throws GLib.Error;
    }
}
