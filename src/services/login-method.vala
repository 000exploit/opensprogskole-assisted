/* login-method.vala
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

    /* How one login method collects credentials. */
    public enum LoginKind {
        NONE,        // nothing to enter (Demo)
        PASSWORD,    // a form of fields, posted for a token
        OAUTH        // browser / OIDC flow, driven by the provider
    }

    /* One credential field of a PASSWORD method — drives a row in the form. */
    public class LoginField : GLib.Object {
        public string key { get; construct; }      // "username" | "password" | "email"
        public string label { get; construct; }
        public bool secret { get; construct; }      // render as a PasswordEntryRow

        public LoginField (string key, string label, bool secret = false) {
            Object (key: key, label: label, secret: secret);
        }
    }

    /* One way to sign in to a school, as the UI needs to present it. The provider
     * lists the ones an instance accepts (login_methods) and performs the chosen
     * one (authenticate). Credentials travel as a GVariant a{ss}, so a single
     * authenticate() handles every method — no overloads. */
    public class LoginMethod : GLib.Object {
        public string id { get; construct; }              // "password" | "sso" | "mitid"
        public LoginKind kind { get; construct; }
        public string display_name { get; construct; }
        public string icon_name { get; construct; }
        // PASSWORD: the fields to collect, in order. NONE/OAUTH: empty.
        public GLib.GenericArray<LoginField> fields = new GLib.GenericArray<LoginField> ();

        public LoginMethod (string id, LoginKind kind, string display_name,
                            string icon_name = "") {
            Object (id: id, kind: kind, display_name: display_name, icon_name: icon_name);
        }

        /* Chainable field add, e.g. password().add_field(...). */
        public unowned LoginMethod add_field (string key, string label, bool secret = false) {
            fields.add (new LoginField (key, label, secret));
            return this;
        }

        /* The standard username/password method (the interface default). */
        public static LoginMethod password () {
            var m = new LoginMethod ("password", LoginKind.PASSWORD,
                                     _("Username & password"), "dialog-password-symbolic");
            m.add_field ("username", _("Username"));
            m.add_field ("password", _("Password"), true);
            return m;
        }

        /* The no-credentials method (Demo). */
        public static LoginMethod none () {
            return new LoginMethod ("none", LoginKind.NONE, _("Enter"));
        }
    }
}
