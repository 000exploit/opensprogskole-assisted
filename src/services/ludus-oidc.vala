/* ludus-oidc.vala
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

    public errordomain LudusAuthError {
        FLOW,        // the browser redirect failed (state mismatch, error param, cancel)
        TOKEN,       // the token endpoint rejected the request
        MALFORMED    // the token response wasn't the JSON we expected
    }

    /* One Keycloak token response, plus the absolute expiry we derive from
     * `expires_in` at receipt time. `refresh_token` is what we persist to
     * resume a session without another browser round-trip. */
    public class LudusTokens : GLib.Object {
        public string access_token { get; construct; }
        public string refresh_token { get; construct; }
        public string id_token { get; construct; }
        public int64 expires_at { get; construct; }   // unix seconds; 0 = unknown

        public LudusTokens (string access_token, string refresh_token,
                            string id_token, int64 expires_at) {
            Object (access_token: access_token, refresh_token: refresh_token,
                    id_token: id_token, expires_at: expires_at);
        }

        public LudusTokens.from_json (Json.Object obj) throws LudusAuthError {
            string access = obj.get_string_member_with_default ("access_token", "");
            if (access == "") {
                throw new LudusAuthError.MALFORMED ("No access_token in token response");
            }
            int64 ttl = obj.get_int_member_with_default ("expires_in", 0);
            Object (
                access_token: access,
                refresh_token: obj.get_string_member_with_default ("refresh_token", ""),
                id_token: obj.get_string_member_with_default ("id_token", ""),
                expires_at: ttl > 0 ? (new DateTime.now_utc ().to_unix () + ttl) : 0
            );
        }
    }

    /* The OIDC Authorization-Code-with-PKCE machinery for LUDUS's Keycloak:
     * the pure pieces (PKCE pair, authorization URL, redirect parsing) plus the
     * token-endpoint calls. UI-free — the provider drives the browser and feeds
     * the redirect back in. See docs/ludus-api.md. */
    namespace LudusOidc {

        // RFC 7636 verifier length (43–128 chars); 32 random bytes → 43 base64url.
        private const int VERIFIER_BYTES = 32;

        /* A fresh PKCE code verifier: base64url(32 random bytes), unpadded —
         * within the RFC's unreserved-character set. */
        public string new_verifier () {
            uint8 raw[VERIFIER_BYTES];
            for (int i = 0; i < VERIFIER_BYTES; i++) {
                raw[i] = (uint8) Random.int_range (0, 256);
            }
            return base64url (raw);
        }

        /* The S256 challenge for a verifier: base64url(sha256(verifier)). */
        public string challenge_for (string verifier) {
            var sha = new Checksum (ChecksumType.SHA256);
            sha.update (verifier.data, verifier.data.length);
            uint8 digest[32];
            size_t len = digest.length;
            sha.get_digest (digest, ref len);
            return base64url (digest);
        }

        /* An opaque value for the OIDC `state` (CSRF guard / flow correlation). */
        public string new_state () {
            uint8 raw[16];
            for (int i = 0; i < 16; i++) {
                raw[i] = (uint8) Random.int_range (0, 256);
            }
            return base64url (raw);
        }

        /* The authorization URL to open in the browser. `challenge` is the S256
         * challenge of the verifier the caller keeps for the exchange; `nonce`
         * is an opaque replay guard (the official app sends one). */
        public string authorization_url (string realm, string state, string nonce,
                                         string challenge) {
            var b = new GLib.StringBuilder (
                LudusConfig.endpoint_for (realm, LudusConfig.Endpoint.AUTHORIZE));
            b.append_c ('?');
            append_query (b, "client_id", LudusConfig.CLIENT_ID, true);
            append_query (b, "redirect_uri", LudusConfig.REDIRECT_URI, false);
            append_query (b, "response_type", "code", false);
            append_query (b, "scope", LudusConfig.SCOPE, false);
            append_query (b, "state", state, false);
            append_query (b, "nonce", nonce, false);
            // Force a fresh login rather than silently reusing a Keycloak SSO
            // cookie — matches the official app and avoids a stuck "already
            // signed in as someone else" state.
            append_query (b, "prompt", "login", false);
            append_query (b, "code_challenge", challenge, false);
            append_query (b, "code_challenge_method", "S256", false);
            return b.str;
        }

        /* Pull the authorization code out of the redirect URI, verifying it
         * matches the flow's `state` and carries no error. Throws FLOW
         * otherwise (including the user cancelling, which Keycloak returns as
         * error=access_denied). */
        public string code_from_redirect (string redirect_uri, string expected_state)
            throws LudusAuthError {
            var query = query_of (redirect_uri);
            string? error = query.lookup ("error");
            if (error != null) {
                string? desc = query.lookup ("error_description");
                throw new LudusAuthError.FLOW (desc != null ? desc : error);
            }
            string? state = query.lookup ("state");
            if (state != expected_state) {
                throw new LudusAuthError.FLOW ("Sign-in state mismatch");
            }
            string? code = query.lookup ("code");
            if (code == null || code == "") {
                throw new LudusAuthError.FLOW ("No authorization code in the redirect");
            }
            return code;
        }

        /* Exchange an authorization code (+ its verifier) for tokens. */
        public async LudusTokens exchange_code (Soup.Session session, string realm,
                                                string code, string verifier,
                                                GLib.Cancellable? cancellable)
            throws GLib.Error {
            var form = new GLib.HashTable<string, string> (str_hash, str_equal);
            form.insert ("grant_type", "authorization_code");
            form.insert ("client_id", LudusConfig.CLIENT_ID);
            form.insert ("redirect_uri", LudusConfig.REDIRECT_URI);
            form.insert ("code", code);
            form.insert ("code_verifier", verifier);
            return yield post_token (session, realm, form, cancellable);
        }

        /* Refresh an access token from a stored refresh token. */
        public async LudusTokens refresh (Soup.Session session, string realm,
                                          string refresh_token,
                                          GLib.Cancellable? cancellable)
            throws GLib.Error {
            var form = new GLib.HashTable<string, string> (str_hash, str_equal);
            form.insert ("grant_type", "refresh_token");
            form.insert ("client_id", LudusConfig.CLIENT_ID);
            form.insert ("refresh_token", refresh_token);
            return yield post_token (session, realm, form, cancellable);
        }

        private async LudusTokens post_token (Soup.Session session, string realm,
                                              GLib.HashTable<string, string> form,
                                              GLib.Cancellable? cancellable)
            throws GLib.Error {
            var msg = new Soup.Message ("POST",
                LudusConfig.endpoint_for (realm, LudusConfig.Endpoint.TOKEN));
            string body = Soup.Form.encode_hash (form);
            msg.set_request_body_from_bytes ("application/x-www-form-urlencoded",
                                             new Bytes (body.data));

            var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT,
                                                           cancellable);
            if (msg.status_code != 200) {
                throw new LudusAuthError.TOKEN ("Token request failed (HTTP %u)"
                    .printf (msg.status_code));
            }
            var parser = new Json.Parser ();
            parser.load_from_data ((string) bytes.get_data (),
                                   (ssize_t) bytes.get_size ());
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                throw new LudusAuthError.MALFORMED ("Unexpected token response");
            }
            return new LudusTokens.from_json (root.get_object ());
        }

        // --- helpers ------------------------------------------------------------

        /* Base64url without padding (RFC 4648 §5), for PKCE + opaque tokens. */
        private string base64url (uint8[] data) {
            return GLib.Base64.encode (data)
                .replace ("+", "-").replace ("/", "_").replace ("=", "");
        }

        private void append_query (GLib.StringBuilder b, string key, string value,
                                   bool first) {
            if (!first) {
                b.append_c ('&');
            }
            b.append (GLib.Uri.escape_string (key, null, false));
            b.append_c ('=');
            b.append (GLib.Uri.escape_string (value, null, false));
        }

        private GLib.HashTable<string, string> query_of (string uri) {
            try {
                var parsed = GLib.Uri.parse (uri, GLib.UriFlags.NONE);
                string? q = parsed.get_query ();
                if (q != null) {
                    return GLib.Uri.parse_params (q, -1, "&", GLib.UriParamsFlags.NONE);
                }
            } catch (GLib.Error e) {
                // Fall through to an empty table — treated as a malformed flow.
            }
            return new GLib.HashTable<string, string> (str_hash, str_equal);
        }
    }
}
