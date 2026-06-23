/* ums-client.vala
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

    public errordomain UmsError {
        UNAUTHORIZED,   // bad credentials (HTTP 400/401)
        HTTP,           // other non-200 response
        MALFORMED       // response wasn't the JSON we expected
    }

    /* Thin libsoup3 wrapper around one UMS backend. It carries the cross-cutting
     * UMS headers (always X-UMS-AppMaui: 1; a per-request X-UMS-Version) and the
     * Bearer token obtained from authenticate(). It speaks raw JSON — turning
     * that into models is the provider's/session's job. */
    public class UmsClient : GLib.Object {

        // PhoneType sent in the login body. 0 on desktop; an Android build would
        // send 1. It's a plain request field, not a binding concern.
        private const int PHONE_TYPE = 0;

        private Soup.Session session = new Soup.Session ();

        public string base_url { get; construct; }   // ".../api"
        public string token { get; set; default = ""; }

        public UmsClient (string base_url) {
            Object (base_url: base_url);
        }

        /* Log in and keep the Bearer token. Throws UmsError.UNAUTHORIZED on bad
         * credentials. */
        public async void authenticate (string username, string password,
                                        int login_type, int auth_type,
                                        string device_name, string device_id)
            throws GLib.Error {
            var msg = new Soup.Message ("POST", base_url + "/Login/Authenticate");
            msg.request_headers.append ("X-UMS-AppMaui", "1");
            msg.request_headers.append ("X-UMS-Version", "4");
            msg.request_headers.append ("X-UMS-LoginType", login_type.to_string ());
            msg.request_headers.append ("X-UMS-AuthType", auth_type.to_string ());

            string body = login_body (username, password, device_name, device_id);
            msg.set_request_body_from_bytes ("application/json", new Bytes (body.data));

            var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);

            if (msg.status_code == 400 || msg.status_code == 401) {
                throw new UmsError.UNAUTHORIZED ("Invalid username or password");
            }
            if (msg.status_code != 200) {
                throw new UmsError.HTTP ("Login failed (HTTP %u)".printf (msg.status_code));
            }

            var root = parse (bytes);
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                throw new UmsError.MALFORMED ("Unexpected login response");
            }
            token = root.get_object ().get_string_member_with_default ("Token", "");
            if (token == "") {
                throw new UmsError.MALFORMED ("No token in login response");
            }
        }

        /* Authenticated GET returning the parsed JSON root. */
        public async Json.Node get_json (string path, string version = "2")
            throws GLib.Error {
            var msg = new Soup.Message ("GET", base_url + path);
            msg.request_headers.append ("X-UMS-AppMaui", "1");
            msg.request_headers.append ("X-UMS-Version", version);
            if (token != "") {
                msg.request_headers.append ("Authorization", "Bearer " + token);
            }

            var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
            if (msg.status_code != 200) {
                throw new UmsError.HTTP ("HTTP %u for %s".printf (msg.status_code, path));
            }
            var root = parse (bytes);
            if (root == null) {
                throw new UmsError.MALFORMED ("Empty/invalid JSON for %s".printf (path));
            }
            return root;
        }

        /* base64url, used for the UserInfo path segment (username). */
        public static string base64url (string text) {
            string b64 = GLib.Base64.encode (text.data);
            return b64.replace ("+", "-").replace ("/", "_").replace ("=", "");
        }

        private static Json.Node? parse (GLib.Bytes bytes) throws GLib.Error {
            var parser = new Json.Parser ();
            parser.load_from_data ((string) bytes.get_data (), (ssize_t) bytes.get_size ());
            return parser.get_root ();
        }

        private static string login_body (string username, string password,
                                          string device_name, string device_id) {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("Username"); b.add_string_value (username);
            b.set_member_name ("Password"); b.add_string_value (password);
            b.set_member_name ("PhoneType"); b.add_int_value (PHONE_TYPE);
            b.set_member_name ("DeviceName"); b.add_string_value (device_name);
            b.set_member_name ("DeviceId"); b.add_string_value (device_id);
            b.end_object ();

            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());
            return gen.to_data (null);
        }
    }
}
