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

    /* Profile-picture loader, stale-while-revalidate with an on-disk cache.
     *
     * The backend serves avatars from a *stable* per-user URL
     * (getImage.ashx?id=<user-hash>…) whose bytes change in place when the user
     * uploads a new photo, so freshness can only be judged by the bytes
     * themselves. load() therefore delivers the cached copy immediately (the
     * backend is slow — seconds per request), revalidates in the background,
     * and delivers a second time only when the downloaded bytes differ. A
     * failed fetch with no cached copy delivers null and the caller falls back
     * to initials — a missing avatar is never fatal. */
    namespace AvatarCache {

        /* Receives the picture at most twice: the cached copy first (when one
         * exists), then the freshly fetched one only if it changed. Called
         * with null only when there is neither a cache nor a fetch result. */
        public delegate void Sink (Gdk.Paintable? paintable);

        /* Deliver the picture at `url` into `sink`, cached copy first. The
         * async call completes when revalidation is done. */
        public async void load (SchoolProvider provider, string url, owned Sink sink) {
            GLib.Bytes? cached = read_bytes (cache_file (url));
            bool delivered = false;
            if (cached != null) {
                try {
                    sink (Gdk.Texture.from_bytes (cached));
                    delivered = true;
                } catch (GLib.Error e) {
                    warning ("avatar cache decode failed: %s", e.message);
                    cached = null;   // corrupt: don't let it veto the fresh copy
                }
            }

            var fresh = yield revalidate (provider, url, cached);
            if (fresh != null) {
                try {
                    sink (Gdk.Texture.from_bytes (fresh));
                    delivered = true;
                } catch (GLib.Error e) {
                    warning ("avatar decode failed: %s", e.message);
                }
            }

            // Offline or undecodable response with nothing shown yet.
            if (!delivered) {
                sink (null);
            }
        }

        /* Warm the on-disk copy for `url` without touching any UI type: the
         * background sync calls this so the avatar renders offline. */
        public async void prefetch (SchoolProvider provider, string url) {
            yield revalidate (provider, url, read_bytes (cache_file (url)));
        }

        /* Fetch `url` and refresh the on-disk copy when it changed. Returns
         * the fresh bytes only when they differ from `cached`; null means
         * unchanged, empty response or a failed fetch (never fatal — the
         * caller falls back to whatever it already has). Bytes only, so it
         * works headless. */
        private async GLib.Bytes? revalidate (SchoolProvider provider, string url,
                                              GLib.Bytes? cached) {
            try {
                GLib.Bytes? bytes = yield provider.fetch_picture (url);
                if (bytes != null && bytes.get_size () > 0
                        && (cached == null || cached.compare (bytes) != 0)) {
                    save (cache_file (url), bytes);   // refresh the offline fallback
                    return bytes;
                }
            } catch (GLib.Error e) {
                warning ("avatar fetch failed: %s", e.message);
            }
            return null;
        }

        private static GLib.Bytes? read_bytes (GLib.File file) {
            try {
                uint8[] contents;
                if (file.load_contents (null, out contents, null)) {
                    return new GLib.Bytes.take ((owned) contents);
                }
            } catch (GLib.Error e) {
                // No cached copy yet — the common first-run case.
            }
            return null;
        }

        private static GLib.File cache_file (string url) {
            string dir = cache_dir ();
            DirUtils.create_with_parents (dir, 0700);
            string name = Checksum.compute_for_string (ChecksumType.SHA256, url);
            return GLib.File.new_for_path (Path.build_filename (dir, name));
        }

        /* The on-disk avatar directory (shared across accounts — entries are
         * keyed by URL hash, not by account). */
        private static string cache_dir () {
            return Path.build_filename (
                Environment.get_user_cache_dir (), "opensprogskole", "avatars");
        }

        /* Drop every cached avatar — on logout and from Preferences → Clear, so
         * a previous user's photo doesn't outlive their session. Best effort. */
        public void clear_all () {
            var dir = GLib.File.new_for_path (cache_dir ());
            try {
                var children = dir.enumerate_children (
                    FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
                FileInfo info;
                while ((info = children.next_file ()) != null) {
                    try {
                        dir.get_child (info.get_name ()).delete ();
                    } catch (GLib.Error e) {
                        warning ("avatar evict failed: %s", e.message);
                    }
                }
            } catch (GLib.Error e) {
                // No avatar dir yet — nothing to clear.
            }
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
