/* school-config.vala
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

    public errordomain SchoolConfigError {
        MALFORMED,      // not JSON / not an object
        UNSUPPORTED,    // provider family we can't sign in against
        BAD_URL         // missing base URL, or one that would leak a password
    }

    /* A School as copyable/pastable JSON, so an unlisted school can be shared
     * (issue tracker, chat) and entered in one paste instead of a form. The
     * member names are the School property names ("base-url", "login-type",
     * ...); anything omitted keeps the property's default. Nothing here is
     * persisted — a pasted config lives only for the session it signs in. */
    namespace SchoolConfig {

        // Hosts a plain-http base URL is tolerated for: loopback only, so a
        // developer can point at a local backend without ever letting a real
        // password travel unencrypted.
        private const string[] PLAIN_HTTP_ALLOWED_HOSTS = { "localhost", "127.0.0.1", "::1" };

        // Family that can actually sign in from a hand-entered config today.
        private const string SUPPORTED_FAMILY = "ums";

        /* Pretty-printed, ready for the clipboard. */
        public string to_json (School school) {
            var gen = new Json.Generator () {
                root = Json.gobject_serialize (school),
                pretty = true,
                indent = 2
            };
            return gen.to_data (null);
        }

        /* Parse and validate a pasted config. The result is always a Custom
         * school (id "custom", is_custom set) regardless of the id in the
         * text — pasted configs must never shadow a registry entry. */
        public School from_json (string text) throws SchoolConfigError {
            var parser = new Json.Parser ();
            try {
                parser.load_from_data (text, -1);
            } catch (GLib.Error e) {
                throw new SchoolConfigError.MALFORMED (_("Not a valid school config: %s").printf (e.message));
            }
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                throw new SchoolConfigError.MALFORMED (_("Not a valid school config (a JSON object was expected)."));
            }

            // Members absent from the JSON come out as null/0 (GObject pspec
            // defaults, not the constructor's) — normalize before validating.
            var parsed = (School) Json.gobject_deserialize (typeof (School), root);
            string family = fallback (parsed.family_id, School.DEFAULT_FAMILY);
            if (family != SUPPORTED_FAMILY) {
                throw new SchoolConfigError.UNSUPPORTED (
                    _("Sign-in for the “%s” provider isn't available yet.").printf (family));
            }
            string base_url = normalize_base_url (parsed.base_url ?? "");
            if (base_url == "") {
                throw new SchoolConfigError.BAD_URL (_("The config has no base URL (\"base-url\")."));
            }
            if (!valid_base_url (base_url)) {
                throw new SchoolConfigError.BAD_URL (
                    _("The base URL must use https:// — plain http would send your password unencrypted."));
            }
            // No "/api" shape check here: it's advisory (valid_ums_base_url),
            // surfaced as a warning by the UI — an instance may serve the
            // API from a different path.

            int weekday = parsed.first_weekday;
            if (weekday < 1 || weekday > 7) {
                weekday = School.DEFAULT_FIRST_WEEKDAY;
            }
            string[]? methods = parsed.login_methods;
            if (methods != null && methods.length == 0) {
                methods = null;   // let the constructor apply its fallback
            }
            var school = new School ("custom",
                                     fallback (parsed.name, _("Custom school")),
                                     parsed.city ?? "",
                                     fallback (parsed.short_code, "★"),
                                     base_url,
                                     fallback (parsed.language, School.DEFAULT_LANGUAGE),
                                     parsed.accent_index > 0
                                         ? parsed.accent_index : School.DEFAULT_ACCENT_INDEX,
                                     parsed.login_type,
                                     parsed.auth_type,
                                     weekday,
                                     SUPPORTED_FAMILY,
                                     methods);
            school.is_custom = true;
            return school;
        }

        private string fallback (string? value, string fallback_value) {
            return value != null && value != "" ? value : fallback_value;
        }

        /* A base URL as the client expects it: no trailing slashes, since
         * request paths are appended as base + "/Endpoint". */
        public string normalize_base_url (string url) {
            string result = url.strip ();
            while (result.has_suffix ("/")) {
                result = result.substring (0, result.length - 1);
            }
            return result;
        }

        /* Backend-specific shape on top of valid_base_url: UMS conventionally
         * serves its REST surface under "/api", so anything else likely fails
         * on the first request. Advisory only — the UI warns but lets the
         * user proceed, in case an instance mounts the API elsewhere. */
        public bool valid_ums_base_url (string url) {
            string normalized = normalize_base_url (url);
            if (!valid_base_url (normalized)) {
                return false;
            }
            try {
                var uri = GLib.Uri.parse (normalized, GLib.UriFlags.NONE);
                string? path = uri.get_path ();
                return path != null && path.has_suffix ("/api");
            } catch (GLib.Error e) {
                return false;
            }
        }

        /* Whether a hand-entered base URL is safe to log in against: parseable,
         * with a host, and https — credentials would otherwise go out in
         * cleartext. Plain http passes only toward loopback (local testing). */
        public bool valid_base_url (string url) {
            try {
                var uri = GLib.Uri.parse (url, GLib.UriFlags.NONE);
                string? host = uri.get_host ();
                if (host == null || host == "") {
                    return false;
                }
                if (uri.get_scheme () == "https") {
                    return true;
                }
                if (uri.get_scheme () == "http") {
                    foreach (string allowed in PLAIN_HTTP_ALLOWED_HOSTS) {
                        if (host.down () == allowed) {
                            return true;
                        }
                    }
                }
                return false;
            } catch (GLib.Error e) {
                return false;
            }
        }
    }
}
