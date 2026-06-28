/* school.vala
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

    /* Identity of one language school the user has an account with.
     *
     * The app is meant to handle several schools at once: each school is backed
     * by its own SchoolProvider (see services/school-provider.vala) but is
     * described to the UI by this small, backend-agnostic value object. It is
     * what the sidebar school switcher in the design lists. No behaviour yet —
     * accounts, sessions and stores will hang off this later. */
    public class School : GLib.Object {
        public string id { get; construct; }
        public string name { get; construct; }
        public string city { get; construct; }
        public string short_code { get; construct; }
        // Which provider family this school belongs to (see ProviderFamily).
        public string family_id { get; construct; }
        // Index into the Adwaita accent-ish avatar palette, as in the mockup.
        public int accent_index { get; construct; }

        // Backend (UMS) connection details. Kept here so the network layer is
        // school-agnostic — see services/schools.vala for the concrete values.
        public string base_url { get; construct; }       // ".../api"
        public string language { get; construct; }        // UMS "language" param
        public int login_type { get; construct; }         // X-UMS-LoginType
        public int auth_type { get; construct; }          // X-UMS-AuthType
        public int first_weekday { get; construct; }      // 1 = Monday

        // Which login methods this instance enables (UMS provider maps the ids,
        // e.g. {"password"} or {"password", "sso"}). Static config — no discovery
        // API — and friendly to contributors registering a school.
        public string[] login_methods;

        // True for a school the user entered by hand (Custom tab); its config is
        // persisted separately since it isn't in the static registry.
        public bool is_custom = false;

        public School (string id, string name, string city, string short_code,
                       string base_url, string language = "1030",
                       int accent_index = 1, int login_type = 0,
                       int auth_type = 0, int first_weekday = 1,
                       string family_id = "ums", string[]? login_methods = null) {
            Object (
                id: id,
                name: name,
                city: city,
                short_code: short_code,
                family_id: family_id,
                base_url: base_url,
                language: language,
                accent_index: accent_index,
                login_type: login_type,
                auth_type: auth_type,
                first_weekday: first_weekday
            );
            string[] fallback = { "password" };
            this.login_methods = login_methods ?? fallback;
        }
    }
}
