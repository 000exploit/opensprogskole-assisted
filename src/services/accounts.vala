/* accounts.vala
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

    /* One saved account: everything a relaunch needs to rebuild the school
     * and resume the session offline — no registry lookup, no directory
     * fetch. The secrets themselves stay in the keyring (SecretStore); this
     * is only the identity and its non-secret companions. */
    public class AccountRecord : GLib.Object {

        public string school_id { get; set; default = ""; }
        public string school_name { get; set; default = ""; }
        // Hand-entered (custom) schools only; registry/LUDUS ones re-derive.
        public string base_url { get; set; default = ""; }
        public string family_id { get; set; default = ""; }
        public string username { get; set; default = ""; }
        public string login_method { get; set; default = ""; }
        // JWT 'exp' (unix seconds); 0 = no expiry claim, still tried.
        public int64 token_valid_until { get; set; default = 0; }

        /* The key this account's cache store and secrets are filed under. */
        public string hash () {
            return Session.account_hash (school_id, username);
        }

        public GLib.Variant serialize () {
            var b = new GLib.VariantDict ();
            b.insert_value ("school-id", new GLib.Variant.string (school_id));
            b.insert_value ("school-name", new GLib.Variant.string (school_name));
            b.insert_value ("base-url", new GLib.Variant.string (base_url));
            b.insert_value ("family-id", new GLib.Variant.string (family_id));
            b.insert_value ("username", new GLib.Variant.string (username));
            b.insert_value ("login-method", new GLib.Variant.string (login_method));
            b.insert_value ("token-valid-until", new GLib.Variant.int64 (token_valid_until));
            return b.end ();
        }

        public static AccountRecord deserialize (GLib.Variant v) {
            var d = new GLib.VariantDict (v);
            var r = new AccountRecord ();
            string s = "";
            int64 i = 0;
            if (d.lookup ("school-id", "s", out s)) r.school_id = s;
            if (d.lookup ("school-name", "s", out s)) r.school_name = s;
            if (d.lookup ("base-url", "s", out s)) r.base_url = s;
            if (d.lookup ("family-id", "s", out s)) r.family_id = s;
            if (d.lookup ("username", "s", out s)) r.username = s;
            if (d.lookup ("login-method", "s", out s)) r.login_method = s;
            if (d.lookup ("token-valid-until", "x", out i)) r.token_valid_until = i;
            return r;
        }
    }

    /* The account registry, GVDB-backed under the durable data dir. Identity
     * is state, not preference: it doesn't belong in GSettings, and it must
     * survive both cache cleaning and the in-app "clear cached data" (which
     * wipe the cache tree where the per-account stores live).
     *
     * Records are keyed by account hash with an "active" pointer beside them.
     * Today exactly one record exists (the controller drives a single
     * account); the shape is the multi-account manager's foundation —
     * enumerating records and moving the pointer is all a switcher needs. */
    public class Accounts : GLib.Object {

        private const string ACTIVE_KEY = "active";

        private static Accounts? _default = null;

        public static unowned Accounts get_default () {
            if (_default == null) {
                _default = new Accounts ();
            }
            return _default;
        }

        private Storage store;

        private Accounts () {
            store = new Storage.durable ("accounts");
        }

        public AccountRecord? active () {
            GLib.Variant? pointer = store.get_value (ACTIVE_KEY);
            if (pointer == null) {
                return null;
            }
            GLib.Variant? record = store.get_value (pointer.get_string ());
            return record != null ? AccountRecord.deserialize (record) : null;
        }

        /* Upsert the record and point "active" at it. */
        public void save_active (AccountRecord record) {
            store.set_value (record.hash (), record.serialize ());
            store.set_value (ACTIVE_KEY, new GLib.Variant.string (record.hash ()));
        }

        /* Logout: drop the record and the pointer. */
        public void remove_active () {
            GLib.Variant? pointer = store.get_value (ACTIVE_KEY);
            if (pointer != null) {
                store.remove (pointer.get_string ());
                store.remove (ACTIVE_KEY);
            }
        }

        /* One-time import of the pre-registry GSettings slot, so existing
         * installs stay signed in across the upgrade. The legacy keys remain
         * in the schema (reading them requires that) but are blanked — the
         * registry is authoritative from here on. */
        public void migrate_legacy (GLib.Settings settings) {
            if (store.get_value (ACTIVE_KEY) != null) {
                return;   // already on records
            }
            string username = settings.get_string ("username");
            if (username == "") {
                return;   // nothing ever saved
            }
            var r = new AccountRecord ();
            r.school_id = settings.get_string ("active-school");
            r.school_name = settings.get_string ("active-school-name");
            r.base_url = settings.get_string ("custom-base-url");
            r.family_id = settings.get_string ("custom-family");
            r.username = username;
            r.login_method = settings.get_string ("login-method");
            r.token_valid_until = settings.get_int64 ("token-valid-until");
            if (r.school_id == "custom" && r.school_name == "") {
                r.school_name = settings.get_string ("custom-name");
            }
            save_active (r);

            foreach (var key in new string[] {
                "active-school", "active-school-name", "username",
                "login-method", "token-valid-until",
                "custom-name", "custom-base-url", "custom-family",
            }) {
                settings.reset (key);
            }
            debug ("migrated the saved account into the registry");
        }
    }
}
