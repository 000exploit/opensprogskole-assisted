/* secret-store.vala
 *
 * Copyright 2026 flex
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

    /* Stores the account password in the system keyring via libsecret (the same
     * mechanism GNOME apps like Tuba use). Entries are keyed by school + username
     * so several accounts can coexist. Only the password is secret — the school
     * id and username are kept in GSettings.
     *
     * On a desktop this is the freedesktop Secret Service; on platforms with a
     * different backend (e.g. an Android port) libsecret routes to whatever is
     * available, so the app code does not change. */
    namespace SecretStore {

        private Secret.Schema? _schema = null;

        private Secret.Schema schema () {
            if (_schema == null) {
                var types = new GLib.HashTable<string, Secret.SchemaAttributeType> (
                    str_hash, str_equal);
                types.insert ("school", Secret.SchemaAttributeType.STRING);
                types.insert ("username", Secret.SchemaAttributeType.STRING);
                // "password" or "token" — lets both secrets coexist per account.
                types.insert ("kind", Secret.SchemaAttributeType.STRING);
                _schema = new Secret.Schema.newv ("moe.ekusu.sprogskole.Account",
                                                  Secret.SchemaFlags.NONE, types);
            }
            return _schema;
        }

        private GLib.HashTable<string, string> attributes (string school, string username,
                                                           string kind) {
            var attrs = new GLib.HashTable<string, string> (str_hash, str_equal);
            attrs.insert ("school", school);
            attrs.insert ("username", username);
            attrs.insert ("kind", kind);
            return attrs;
        }

        private async void store_secret (string school, string username, string kind,
                                         string label, string secret) throws GLib.Error {
            yield Secret.password_storev (
                schema (), attributes (school, username, kind),
                Secret.COLLECTION_DEFAULT, label, secret, null);
        }

        private async string? lookup_secret (string school, string username, string kind)
            throws GLib.Error {
            return yield Secret.password_lookupv (
                schema (), attributes (school, username, kind), null);
        }

        private async void clear_secret (string school, string username, string kind)
            throws GLib.Error {
            yield Secret.password_clearv (
                schema (), attributes (school, username, kind), null);
        }

        /* Account password. */
        public async void store (string school, string username, string password)
            throws GLib.Error {
            yield store_secret (school, username, "password",
                                "OpenSprogskole — %s".printf (username), password);
        }

        public async string? lookup (string school, string username) throws GLib.Error {
            return yield lookup_secret (school, username, "password");
        }

        public async void clear (string school, string username) throws GLib.Error {
            yield clear_secret (school, username, "password");
        }

        /* Session token (Bearer). Stored so a still-valid session can be resumed
         * on next launch without re-sending the password. */
        public async void store_token (string school, string username, string token)
            throws GLib.Error {
            yield store_secret (school, username, "token",
                                "OpenSprogskole token — %s".printf (username), token);
        }

        public async string? lookup_token (string school, string username)
            throws GLib.Error {
            return yield lookup_secret (school, username, "token");
        }

        public async void clear_token (string school, string username) throws GLib.Error {
            yield clear_secret (school, username, "token");
        }
    }
}
