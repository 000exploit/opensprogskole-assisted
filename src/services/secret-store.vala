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
                _schema = new Secret.Schema.newv ("moe.ekusu.sprogskole.Account",
                                                  Secret.SchemaFlags.NONE, types);
            }
            return _schema;
        }

        private GLib.HashTable<string, string> attributes (string school, string username) {
            var attrs = new GLib.HashTable<string, string> (str_hash, str_equal);
            attrs.insert ("school", school);
            attrs.insert ("username", username);
            return attrs;
        }

        /* Save (or replace) the password for an account. */
        public async void store (string school, string username, string password)
            throws GLib.Error {
            yield Secret.password_storev (
                schema (),
                attributes (school, username),
                Secret.COLLECTION_DEFAULT,
                "OpenSprogskole — %s".printf (username),
                password,
                null);
        }

        /* The saved password, or null if there is none. */
        public async string? lookup (string school, string username)
            throws GLib.Error {
            return yield Secret.password_lookupv (
                schema (), attributes (school, username), null);
        }

        /* Forget the saved password. */
        public async void clear (string school, string username)
            throws GLib.Error {
            yield Secret.password_clearv (
                schema (), attributes (school, username), null);
        }
    }
}
