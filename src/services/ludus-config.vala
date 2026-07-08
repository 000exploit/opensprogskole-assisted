/* ludus-config.vala
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

    /* LUDUS (EG) backend constants, recovered from the official app — see
     * docs/ludus-api.md for provenance. The Keycloak endpoints carry a
     * per-school realm, filled in at authenticate time (endpoint_for). */
    namespace LudusConfig {

        // Production environment (prod.json). qa/et exist but aren't offered.
        public const string API_GATEWAY = "https://ludus-api.luduseg.dk";
        public const string STS_BASE = "https://sts.egki.dk/auth/realms";

        // OIDC public client (pp.txt object pool; verified live against a real
        // school realm — the client is accepted and shows the MitID login).
        public const string CLIENT_ID = "ludus-mobile";
        public const string REDIRECT_URI = "dk.eg.ludus.mobile://login-callback";
        public const string SCOPE = "openid profile email";

        // The Keycloak realm is per school, named "ludus-<institutionNumber>"
        // (the config's `realm_name` placeholder; verified live, e.g.
        // ludus-280318 = A2B, ludus-000001 = the demo school). NOT a single
        // shared realm.
        public string realm_for (string institution_number) {
            return "ludus-" + institution_number;
        }

        // The URI scheme half of REDIRECT_URI, for the desktop handler.
        public const string REDIRECT_SCHEME = "dk.eg.ludus.mobile";

        // Unauthenticated bootstrap: the school directory (each carries its
        // keycloak_realm).
        public const string SCHOOLS_PATH = "/info-service/schools";

        public enum Endpoint { AUTHORIZE, TOKEN, LOGOUT }

        /* The Keycloak endpoint URL for `realm`. The realm is per-school, so
         * the URL can't be a plain constant. */
        public string endpoint_for (string realm, Endpoint endpoint) {
            string tail;
            switch (endpoint) {
                case Endpoint.AUTHORIZE: tail = "auth";   break;
                case Endpoint.TOKEN:     tail = "token";  break;
                case Endpoint.LOGOUT:    tail = "logout"; break;
                default:                 assert_not_reached ();
            }
            return "%s/%s/protocol/openid-connect/%s".printf (STS_BASE, realm, tail);
        }
    }
}
