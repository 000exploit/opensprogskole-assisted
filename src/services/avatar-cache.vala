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

    /* On-disk cache for profile pictures. Avatars rarely change and the bytes
     * are reusable across sessions, so the first request downloads via the
     * provider and writes the file; later requests decode straight from disk
     * with no network hit. A failure anywhere yields null and the caller falls
     * back to initials — a missing avatar is never fatal. */
    namespace AvatarCache {

        /* Return the picture at `url` as a paintable, downloading + caching on a
         * miss. null when the bytes can't be fetched or decoded. */
        public async Gdk.Paintable? load (SchoolProvider provider, string url) {
            var file = cache_file (url);
            try {
                if (file.query_exists ()) {
                    return Gdk.Texture.from_file (file);
                }

                GLib.Bytes? bytes = yield provider.fetch_picture (url);
                if (bytes == null || bytes.get_size () == 0) {
                    return null;
                }

                var texture = Gdk.Texture.from_bytes (bytes);
                save (file, bytes);
                return texture;
            } catch (GLib.Error e) {
                warning ("avatar load failed: %s", e.message);
                return null;
            }
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
