/* ums-client.vala
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

        // Cap how long a request may stall before failing — the backstop when a
        // connection dies mid-flight and the OS doesn't report it (so our
        // connectivity cancel can't fire). Generous, since the backend itself is
        // slow (~8s is a normal call). libsoup's own default would be 60s.
        private const uint REQUEST_TIMEOUT_SECONDS = 25;

        private Soup.Session session = new Soup.Session () {
            timeout = REQUEST_TIMEOUT_SECONDS
        };

        public string base_url { get; construct; }   // ".../api"
        public string token { get; set; default = ""; }
        // Unix seconds the token expires (from the JWT 'exp' claim); 0 = unknown.
        public int64 token_expires_at { get; set; default = 0; }
        // The AppSettings subtree of the last Authenticate response (Links,
        // AbsenceCallInSickSettings, ...). A sibling of Token, so it carries no
        // credential. Null until a fresh login happens (token-resume skips auth).
        public Json.Node? app_settings { get; private set; default = null; }

        public UmsClient (string base_url) {
            Object (base_url: base_url);
        }

        /* Best-effort cancel of every in-flight request when connectivity is lost.
         *
         * NOTE: this does NOT actually unstick a request blocked on a dead HTTP/2
         * socket. Measured: neither the per-request GCancellable nor this
         * session.abort() interrupts the read — the connection sits in a kernel
         * ESTABLISHED state (the peer sent no FIN/RST, the network simply vanished),
         * and libsoup only gives up when its own socket I/O timeout fires (our
         * REQUEST_TIMEOUT_SECONDS). It still helps on reconnect (drops the dead
         * pooled connection so a retry opens a fresh one).
         *
         * The real fix belongs in libsoup/GLib: honour the GCancellable on a
         * blocked HTTP/2 connection read, or expose TCP_USER_TIMEOUT (or a
         * keepalive PING deadline) so a dead peer is detected in seconds instead of
         * waiting out the full I/O timeout. Until then the timeout is our only bound. */
        public void abort () {
            session.abort ();
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

            var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, Connectivity.get_default ().cancellable);

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
            token_expires_at = decode_jwt_exp (token);
            // Keep the (token-free) AppSettings subtree for the caller to cache.
            app_settings = root.get_object ().has_member ("AppSettings")
                ? root.get_object ().get_member ("AppSettings") : null;
        }

        /* Read the 'exp' (unix seconds) claim from a JWT, or 0 if absent/
         * unparseable. The login response carries no expiry of its own, so this
         * is how we learn when the token lapses. */
        public static int64 decode_jwt_exp (string token) {
            string[] parts = token.split (".");
            if (parts.length < 2) {
                return 0;
            }
            string payload = parts[1].replace ("-", "+").replace ("_", "/");
            switch (payload.length % 4) {
                case 2: payload += "=="; break;
                case 3: payload += "="; break;
                case 1: return 0;   // not valid base64
            }
            uint8[] data = GLib.Base64.decode (payload);
            if (data.length == 0) {
                return 0;
            }
            try {
                var parser = new Json.Parser ();
                parser.load_from_data ((string) data, data.length);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                    return 0;
                }
                return root.get_object ().get_int_member_with_default ("exp", 0);
            } catch (GLib.Error e) {
                return 0;
            }
        }

        /* Build an authenticated request to base_url + path carrying the standard
         * UMS headers. A JSON body, if any, is attached by the caller. */
        private Soup.Message authed (string method, string path, string version) {
            var msg = new Soup.Message (method, base_url + path);
            msg.request_headers.append ("X-UMS-AppMaui", "1");
            msg.request_headers.append ("X-UMS-Version", version);
            if (token != "") {
                msg.request_headers.append ("Authorization", "Bearer " + token);
            }
            return msg;
        }

        /* Authenticated GET returning the parsed JSON root. */
        public async Json.Node get_json (string path, string version = "2")
            throws GLib.Error {
            var msg = authed ("GET", path, version);
            var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, Connectivity.get_default ().cancellable);
            if (msg.status_code != 200) {
                throw new UmsError.HTTP ("HTTP %u for %s".printf (msg.status_code, path));
            }
            var root = parse (bytes);
            if (root == null) {
                throw new UmsError.MALFORMED ("Empty/invalid JSON for %s".printf (path));
            }
            return root;
        }

        /* Authenticated POST with no body; the response is ignored. Used for
         * fire-and-forget endpoints like DeleteToken. */
        public async void post (string path, string version = "2") throws GLib.Error {
            var msg = authed ("POST", path, version);
            yield session.send_and_read_async (msg, Priority.DEFAULT, Connectivity.get_default ().cancellable);
        }

        /* Authenticated POST with no body whose status is checked (the response
         * body is still ignored). For action endpoints where success matters,
         * e.g. DeletePendingImage. */
        public async void post_action (string path, string version = "2")
            throws GLib.Error {
            var msg = authed ("POST", path, version);
            yield session.send_and_read_async (msg, Priority.DEFAULT, Connectivity.get_default ().cancellable);
            check_post_status (msg.status_code, path);
        }

        /* Authenticated multipart/form-data POST of a single file part; the
         * response body is ignored, the status is checked. Used to upload the
         * profile picture (UpdateUserImage). */
        public async void post_multipart (string path, string control_name,
                                          string filename, string content_type,
                                          GLib.Bytes body, string version = "2")
            throws GLib.Error {
            var multipart = new Soup.Multipart ("multipart/form-data");
            multipart.append_form_file (control_name, filename, content_type, body);

            var msg = new Soup.Message.from_multipart (base_url + path, multipart);
            msg.request_headers.append ("X-UMS-AppMaui", "1");
            msg.request_headers.append ("X-UMS-Version", version);
            if (token != "") {
                msg.request_headers.append ("Authorization", "Bearer " + token);
            }

            yield session.send_and_read_async (msg, Priority.DEFAULT, Connectivity.get_default ().cancellable);
            check_post_status (msg.status_code, path);
        }

        /* Authenticated POST with a JSON body, returning the parsed response.
         * Throws on a non-200 status. */
        public async Json.Node post_json (string path, string body, string version = "2")
            throws GLib.Error {
            var msg = authed ("POST", path, version);
            msg.set_request_body_from_bytes ("application/json", new Bytes (body.data));

            var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, Connectivity.get_default ().cancellable);
            check_post_status (msg.status_code, path);
            var root = parse (bytes);
            if (root == null) {
                throw new UmsError.MALFORMED ("Empty/invalid JSON for %s".printf (path));
            }
            return root;
        }

        /* Authenticated POST with a JSON body whose response body is ignored.
         * For endpoints that reply 200 with empty/non-JSON content (UpdateUserInfo). */
        public async void post_void (string path, string body, string version = "2")
            throws GLib.Error {
            var msg = authed ("POST", path, version);
            msg.set_request_body_from_bytes ("application/json", new Bytes (body.data));
            yield session.send_and_read_async (msg, Priority.DEFAULT, Connectivity.get_default ().cancellable);
            check_post_status (msg.status_code, path);
        }

        /* Authenticated PUT with a JSON body whose response body is ignored; the
         * status is checked. Used for UpdateFutureStudentAbsence. */
        public async void put_void (string path, string body, string version = "2")
            throws GLib.Error {
            var msg = authed ("PUT", path, version);
            msg.set_request_body_from_bytes ("application/json", new Bytes (body.data));
            yield session.send_and_read_async (msg, Priority.DEFAULT, Connectivity.get_default ().cancellable);
            check_post_status (msg.status_code, path);
        }

        /* Authenticated DELETE; the response body is ignored, the status checked.
         * Used for DeleteFutureStudentAbsence (the id rides in the query string). */
        public async void delete_void (string path, string version = "2")
            throws GLib.Error {
            var msg = authed ("DELETE", path, version);
            yield session.send_and_read_async (msg, Priority.DEFAULT, Connectivity.get_default ().cancellable);
            check_post_status (msg.status_code, path);
        }

        /* GET raw bytes from an absolute URL (a profile picture), carrying the
         * Bearer token only when the URL stays on the API's own origin — the
         * URL is server-supplied data, so a third-party host must not receive
         * the credential. Returns null on any non-200 instead of throwing — a
         * missing avatar is not an error worth propagating. */
        public async GLib.Bytes? fetch_picture (string url) {
            var msg = new Soup.Message ("GET", url);
            if (msg == null) {
                warning ("picture fetch skipped: invalid URL");
                return null;
            }
            if (token != "" && same_origin_as_base (url)) {
                msg.request_headers.append ("Authorization", "Bearer " + token);
            }
            try {
                var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, Connectivity.get_default ().cancellable);
                return msg.status_code == 200 ? bytes : null;
            } catch (GLib.Error e) {
                warning ("picture fetch failed: %s", e.message);
                return null;
            }
        }

        /* Whether `url` shares scheme + host + port with base_url. Anything
         * unparseable counts as foreign — the safe default for a credential. */
        private bool same_origin_as_base (string url) {
            try {
                var target = GLib.Uri.parse (url, GLib.UriFlags.NONE);
                var origin = GLib.Uri.parse (base_url, GLib.UriFlags.NONE);
                string? target_host = target.get_host ();
                string? origin_host = origin.get_host ();
                return target.get_scheme () == origin.get_scheme ()
                    && target_host != null && origin_host != null
                    && target_host.down () == origin_host.down ()
                    && effective_port (target) == effective_port (origin);
            } catch (GLib.Error e) {
                return false;
            }
        }

        /* The URI's port with the scheme default filled in, so implicit and
         * explicit forms of the same origin compare equal. */
        private static int effective_port (GLib.Uri uri) {
            int port = uri.get_port ();
            if (port != -1) {
                return port;
            }
            switch (uri.get_scheme ()) {
                case "https": return 443;
                case "http":  return 80;
                default:      return -1;
            }
        }

        private static void check_post_status (uint status, string path) throws UmsError {
            if (status == 400 || status == 401) {
                throw new UmsError.UNAUTHORIZED ("Request rejected (HTTP %u)".printf (status));
            }
            if (status != 200) {
                throw new UmsError.HTTP ("HTTP %u for %s".printf (status, path));
            }
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
