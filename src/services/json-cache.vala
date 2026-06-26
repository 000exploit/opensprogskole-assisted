/* json-cache.vala
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

    /* On-disk cache of raw API JSON, per account, so the last successful
     * GetUserInfo / GetTimetable can still be shown when the backend is
     * unreachable. Mirrors AvatarCache: best-effort and network-first (this is
     * only the fallback), so a read/write failure is never fatal. Keyed by an
     * opaque `account` hash (school + username) so accounts never collide; the
     * whole account folder is wiped on logout. */
    namespace JsonCache {

        /* Save `node` under (account, key), replacing any previous copy. The
         * file's modification time doubles as "when this was cached". */
        public void save (string account, string key, Json.Node node) {
            var generator = new Json.Generator ();
            generator.set_root (node);
            try {
                var file = cache_file (account, key);
                file.replace_contents (generator.to_data (null).data, null, false,
                                       FileCreateFlags.PRIVATE, null, null);
            } catch (GLib.Error e) {
                warning ("json cache write failed (%s): %s", key, e.message);
            }
        }

        /* The cached node for (account, key), or null when absent/unreadable. */
        public Json.Node? load (string account, string key) {
            try {
                var file = cache_file (account, key);
                if (!file.query_exists ()) {
                    return null;
                }
                uint8[] data;
                file.load_contents (null, out data, null);

                var parser = new Json.Parser ();
                parser.load_from_data ((string) data, data.length);
                return parser.get_root ();
            } catch (GLib.Error e) {
                warning ("json cache read failed (%s): %s", key, e.message);
                return null;
            }
        }

        /* When (account, key) was last written, or null if there is no cache.
         * Lets a future change decide what counts as a "future" lesson when
         * showing stale data; for now it just relies on the file's mtime. */
        public DateTime? timestamp (string account, string key) {
            try {
                var file = cache_file (account, key);
                if (!file.query_exists ()) {
                    return null;
                }
                var info = file.query_info (FileAttribute.TIME_MODIFIED,
                                            FileQueryInfoFlags.NONE);
                return info.get_modification_date_time ();
            } catch (GLib.Error e) {
                return null;
            }
        }

        /* Drop every cached file for an account (logout). Best effort. */
        public void clear (string account) {
            var dir = GLib.File.new_for_path (account_dir (account));
            try {
                var children = dir.enumerate_children (
                    FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
                FileInfo info;
                while ((info = children.next_file ()) != null) {
                    try {
                        dir.get_child (info.get_name ()).delete ();
                    } catch (GLib.Error e) {
                        warning ("json cache evict failed: %s", e.message);
                    }
                }
            } catch (GLib.Error e) {
                // No cache dir yet — nothing to clear.
            }
        }

        private string account_dir (string account) {
            return Path.build_filename (
                Environment.get_user_cache_dir (), "opensprogskole", "data", account);
        }

        private GLib.File cache_file (string account, string key) {
            string dir = account_dir (account);
            DirUtils.create_with_parents (dir, 0700);
            return GLib.File.new_for_path (Path.build_filename (dir, key + ".json"));
        }
    }
}
