/* avatar-cache.vala
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

    /* Profile-picture loader with an on-disk offline fallback.
     *
     * The backend serves avatars from a *stable* per-user URL
     * (getImage.ashx?id=<user-hash>…) whose bytes change in place when the user
     * uploads a new photo. A URL-keyed cache therefore can't tell a new picture
     * from the old one, so we fetch network-first and keep the last download
     * only as a fallback for when the request fails (offline). A failure with no
     * cached copy yields null and the caller falls back to initials — a missing
     * avatar is never fatal. */
    namespace AvatarCache {

        /* Return the current picture at `url` as a paintable. Fetches fresh;
         * on a failed fetch, returns the last cached copy if there is one, else
         * null. */
        public async Gdk.Paintable? load (SchoolProvider provider, string url) {
            var file = cache_file (url);

            /* TODO: stale-while-revalidate — return the cached copy immediately,
             * fetch in the background and swap the widget's image only if the
             * bytes changed, to avoid a network GET on every load. */
            try {
                GLib.Bytes? bytes = yield provider.fetch_picture (url);
                if (bytes != null && bytes.get_size () > 0) {
                    var texture = Gdk.Texture.from_bytes (bytes);
                    save (file, bytes);   // refresh the offline fallback
                    return texture;
                }
            } catch (GLib.Error e) {
                warning ("avatar fetch failed: %s", e.message);
            }

            // Offline or undecodable response: use the previous copy if present.
            try {
                if (file.query_exists ()) {
                    return Gdk.Texture.from_file (file);
                }
            } catch (GLib.Error e) {
                warning ("avatar cache read failed: %s", e.message);
            }
            return null;
        }

        private static GLib.File cache_file (string url) {
            string dir = Path.build_filename (
                Environment.get_user_cache_dir (), "opensprogskole", "avatars");
            DirUtils.create_with_parents (dir, 0700);
            string name = Checksum.compute_for_string (ChecksumType.SHA256, url);
            return GLib.File.new_for_path (Path.build_filename (dir, name));
        }

        private static void save (GLib.File file, GLib.Bytes bytes) {
            try {
                file.replace_contents (bytes.get_data (), null, false,
                                       FileCreateFlags.PRIVATE, null, null);
            } catch (GLib.Error e) {
                // Caching is best-effort; the texture is already decoded.
                warning ("avatar cache write failed: %s", e.message);
            }
        }
    }
}
