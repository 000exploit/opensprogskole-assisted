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

    /* The contract every language school's backend must satisfy.
     *
     * This is the seam that lets the app talk to several different schools: the
     * rest of the program depends only on this interface and on the normalized
     * models (TimetableItem, Grade), never on a specific school's API. A
     * concrete provider (added later, using libsoup) logs in, fetches the
     * school-specific JSON and is responsible for handing back data the common
     * models can consume.
     *
     * The fetch_* methods return raw JSON so a provider may massage a school's
     * peculiar payload before it reaches TimetableStore; only the network/auth
     * details differ per school. No implementation ships in this round — API
     * logic is out of scope here. */
    public interface SchoolProvider : GLib.Object {

        /* Which school this provider serves. */
        public abstract School school { get; }

        /* Authenticate. Returns true on success; throws on bad credentials. */
        public abstract async bool login (string username, string password)
            throws GLib.Error;

        /* The student's timetable as a JSON array suitable for
         * TimetableStore.load(). */
        public abstract async Json.Node? fetch_timetable () throws GLib.Error;

        /* The student's reported absences (JSON array of events). */
        public abstract async Json.Node? fetch_absence () throws GLib.Error;

        /* The student's grades as a JSON array. */
        public abstract async Json.Node? fetch_grades () throws GLib.Error;

        /* The student's profile (JSON object). */
        public abstract async Json.Node? fetch_user_info (string username)
            throws GLib.Error;

        /* Which profile fields the school lets the student edit (JSON object). */
        public abstract async Json.Node? fetch_user_info_settings ()
            throws GLib.Error;

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

        /* The student's own (editable) future absences as a JSON array. */
        public abstract async Json.Node? fetch_future_absence () throws GLib.Error;

        /* Update an existing future absence (identified by `id`). The backend's
         * only way to edit any absence — even a past one — is to update its
         * future record. ISO datetimes are "yyyy-MM-ddTHH:mm:ss". */
        public abstract async void update_future_absence (int id, string reason,
                                                          string start_iso,
                                                          string end_iso)
            throws GLib.Error;

        /* Delete a future absence by id. */
        public abstract async void delete_future_absence (int id) throws GLib.Error;

        /* The school's absence policy (JSON object), e.g. how far back a reason
         * may still be described. */
        public abstract async Json.Node? fetch_absence_settings () throws GLib.Error;

        /* Describe (create or edit) the reason for a past absent lesson, keyed by
         * its server + timetable ids (ServerId/EventId in the absence response). */
        public abstract async void create_absence_reason (int server_id,
                                                          string timetable_id,
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
