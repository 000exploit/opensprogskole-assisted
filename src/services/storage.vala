/* storage.vala
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

    /* Per-account on-disk key/value store, persisted as a single GVDB file (the
     * GVariant database format behind GSettings/GResource). Values are GVariants;
     * a JSON bridge (json-glib's gvariant (de)serialize) lets callers round-trip
     * raw API payloads, and StorageNode gives typed reads without hand-parsing.
     *
     * Best-effort / volatile: a missing or unreadable store is simply empty and
     * gets rebuilt from the next successful fetch — never fatal. */
    public class Storage : GLib.Object {

        // In-memory source of truth; the whole map is rewritten on each change.
        private GLib.HashTable<string, Variant> values
            = new GLib.HashTable<string, Variant> (str_hash, str_equal);
        private string file_path;

        public Storage (string account) {
            file_path = Path.build_filename (account_dir (account), "store.gvdb");
            load ();
        }

        public Variant? get_value (string key) {
            return values.lookup (key);
        }

        public void set_value (string key, Variant value) {
            values.insert (key, value);
            persist ();
        }

        public bool has (string key) {
            return values.contains (key);
        }

        public void remove (string key) {
            if (values.remove (key)) {
                persist ();
            }
        }

        /* A value as a JSON tree, for model deserialization / interop. */
        public Json.Node? get_json (string key) {
            var v = values.lookup (key);
            return v != null ? Json.gvariant_serialize (v) : null;
        }

        /* Store a JSON tree (e.g. a raw API payload) as a value. */
        public void set_json (string key, Json.Node node) {
            try {
                var v = Json.gvariant_deserialize (node, null);
                if (v != null) {
                    set_value (key, v);
                }
            } catch (GLib.Error e) {
                warning ("storage set_json (%s) failed: %s", key, e.message);
            }
        }

        /* A typed read wrapper over a value, or null if the key is absent. */
        public StorageNode? get_node (string key) {
            var node = get_json (key);
            return node != null ? new StorageNode (node) : null;
        }

        /* When the store was last written (whole-store mtime), or null. */
        public DateTime? timestamp () {
            try {
                var file = File.new_for_path (file_path);
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

        /* Drop an account's whole store (logout). Best effort. */
        public static void clear (string account) {
            var dir = File.new_for_path (account_dir (account));
            try {
                var children = dir.enumerate_children (
                    FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
                FileInfo info;
                while ((info = children.next_file ()) != null) {
                    try {
                        dir.get_child (info.get_name ()).delete ();
                    } catch (GLib.Error e) {
                        warning ("storage evict failed: %s", e.message);
                    }
                }
            } catch (GLib.Error e) {
                // No store dir yet — nothing to clear.
            }
        }

        private void load () {
            try {
                var file = File.new_for_path (file_path);
                if (!file.query_exists ()) {
                    return;
                }
                uint8[] data;
                file.load_contents (null, out data, null);
                values = Gvdb.read (new Bytes (data));
            } catch (GLib.Error e) {
                warning ("storage load failed (%s): %s — starting empty",
                         file_path, e.message);
            }
        }

        private void persist () {
            try {
                DirUtils.create_with_parents (Path.get_dirname (file_path), 0700);
                Gvdb.write (file_path, values);
            } catch (GLib.Error e) {
                warning ("storage write failed (%s): %s", file_path, e.message);
            }
        }

        private static string account_dir (string account) {
            return Path.build_filename (
                Environment.get_user_cache_dir (), "opensprogskole", "data", account);
        }
    }

    /* A typed, read-only view over a JSON subtree. Keeps all json-glib navigation
     * in one place so callers read values/arrays without touching Json.Object. */
    public class StorageNode {

        private Json.Node node;

        public StorageNode (Json.Node node) {
            this.node = node;
        }

        public string get_string (string key, string fallback = "") {
            var o = as_object ();
            return o != null ? o.get_string_member_with_default (key, fallback) : fallback;
        }

        public int64 get_int (string key, int64 fallback = 0) {
            var o = as_object ();
            return o != null ? o.get_int_member_with_default (key, fallback) : fallback;
        }

        public bool get_bool (string key, bool fallback = false) {
            var o = as_object ();
            return o != null ? o.get_boolean_member_with_default (key, fallback) : fallback;
        }

        /* A nested object as its own node, or null. */
        public StorageNode? get_object (string key) {
            var o = as_object ();
            if (o == null || !o.has_member (key)) {
                return null;
            }
            var m = o.get_member (key);
            return m.get_node_type () == Json.NodeType.OBJECT ? new StorageNode (m) : null;
        }

        /* The elements of an array member, each wrapped as a node (empty if the
         * key is missing or not an array). */
        public StorageNode[] get_array (string key) {
            var o = as_object ();
            if (o == null || !o.has_member (key)) {
                return {};
            }
            var m = o.get_member (key);
            if (m.get_node_type () != Json.NodeType.ARRAY) {
                return {};
            }
            StorageNode[] result = {};
            m.get_array ().foreach_element ((arr, i, element) => {
                result += new StorageNode (element);
            });
            return result;
        }

        public Json.Node to_json () {
            return node;
        }

        private Json.Object? as_object () {
            return node.get_node_type () == Json.NodeType.OBJECT ? node.get_object () : null;
        }
    }
}
