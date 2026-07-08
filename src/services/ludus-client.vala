/* ludus-client.vala
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

    public errordomain LudusError {
        HTTP,          // non-200 from the API gateway
        MALFORMED,     // response wasn't the JSON we expected
        NOT_MAPPED     // endpoint known but its response shape isn't wired yet
    }

    /* Thin libsoup wrapper around the LUDUS API gateway. Holds the OIDC access
     * token and attaches it as a Bearer to every authed call; the token itself
     * is obtained/refreshed by LudusOidc, driven by LudusProvider. Speaks raw
     * JSON — turning it into models is the provider's job.
     *
     * NOTE: the data endpoints' response shapes are not yet mapped (see
     * docs/ludus-api.md); only the token plumbing and the unauthenticated
     * school directory are wired. */
    public class LudusClient : GLib.Object {

        private const uint REQUEST_TIMEOUT_SECONDS = 25;

        private Soup.Session session = new Soup.Session () {
            timeout = REQUEST_TIMEOUT_SECONDS
        };

        public string access_token { get; set; default = ""; }

        /* The Soup.Session, shared with LudusOidc so token calls reuse the same
         * connection pool and timeout. */
        public Soup.Session soup { get { return session; } }

        /* GET the unauthenticated school directory. Static (no token), so it can
         * run before sign-in to populate the picker. Returns a bare array of
         * school objects (fields: institutionName, institutionNumber,
         * ludusWebUrl — verified live; see docs/ludus-api.md). */
        public async Json.Array fetch_schools (GLib.Cancellable? cancellable = null)
            throws GLib.Error {
            var msg = new Soup.Message ("GET",
                LudusConfig.API_GATEWAY + LudusConfig.SCHOOLS_PATH);
            var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT,
                                                           cancellable);
            if (msg.status_code != 200) {
                throw new LudusError.HTTP ("Schools request failed (HTTP %u)"
                    .printf (msg.status_code));
            }
            var root = parse (bytes);
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) {
                throw new LudusError.MALFORMED ("Unexpected schools response");
            }
            return root.get_array ();
        }

        /* Authenticated GET returning the parsed JSON root. */
        public async Json.Node get_json (string path,
                                         GLib.Cancellable? cancellable = null)
            throws GLib.Error {
            var msg = new Soup.Message ("GET", LudusConfig.API_GATEWAY + path);
            if (access_token != "") {
                msg.request_headers.append ("Authorization", "Bearer " + access_token);
            }
            var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT,
                                                           cancellable);
            if (msg.status_code != 200) {
                throw new LudusError.HTTP ("HTTP %u for %s".printf (msg.status_code, path));
            }
            var root = parse (bytes);
            if (root == null) {
                throw new LudusError.MALFORMED ("Empty/invalid JSON for %s".printf (path));
            }
            return root;
        }

        public void abort () {
            session.abort ();
        }

        private static Json.Node? parse (GLib.Bytes bytes) throws GLib.Error {
            var parser = new Json.Parser ();
            parser.load_from_data ((string) bytes.get_data (), (ssize_t) bytes.get_size ());
            return parser.get_root ();
        }
    }
}
