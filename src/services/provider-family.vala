/* provider-family.vala
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

    /* A backend "family": a group of schools that share a transport. Onboarding
     * drives off this — it lists families, then a family's schools; the chosen
     * school's provider then reports its login methods (see SchoolProvider). A
     * family can be marked unavailable so it shows greyed-out. */
    public interface ProviderFamily : GLib.Object {
        public abstract string id { get; }
        public abstract string display_name { owned get; }
        public abstract string icon_name { get; }
        // false ⇒ shown in the picker but unselectable, with `unavailable_note`.
        public abstract bool available { get; }
        public abstract string unavailable_note { owned get; }

        /* The selectable schools in this family, synchronously — for families
         * with a static registry (UMS, Demo). Families that fetch a directory
         * return empty here and override fetch_schools. */
        public abstract GLib.GenericArray<School> list_schools ();

        /* The selectable schools, possibly fetched from a directory. The picker
         * calls this (with a spinner); the default just wraps the static
         * list_schools so registry families need no async code. */
        public virtual async GLib.GenericArray<School> fetch_schools (
            GLib.Cancellable? cancellable = null) throws GLib.Error {
            return list_schools ();
        }

        /* Build the provider for a chosen school. device_* are used by UMS; other
         * families ignore them. */
        public abstract SchoolProvider create_provider (School school,
                                                        string device_name,
                                                        string device_id);
    }

    /* Sprogcenter Midt & friends — the UMS backend, username/password. */
    public class UmsFamily : GLib.Object, ProviderFamily {
        public string id { get { return "ums"; } }
        public string display_name { owned get { return _("UMS schools"); } }
        public string icon_name { get { return "accessories-dictionary-symbolic"; } }
        public bool available { get { return true; } }
        public string unavailable_note { owned get { return ""; } }

        public GLib.GenericArray<School> list_schools () {
            return Schools.ums ();
        }

        public SchoolProvider create_provider (School school, string device_name,
                                               string device_id) {
            return new UmsProvider (school, device_name, device_id);
        }
    }

    /* A credential-free sample account with canned data, for trying the app and
     * for screenshots. */
    public class DemoFamily : GLib.Object, ProviderFamily {
        public string id { get { return "demo"; } }
        public string display_name { owned get { return _("Demo"); } }
        public string icon_name { get { return "applications-games-symbolic"; } }
        public bool available { get { return true; } }
        public string unavailable_note { owned get { return ""; } }

        public GLib.GenericArray<School> list_schools () {
            var list = new GLib.GenericArray<School> ();
            list.add (Schools.demo ());
            return list;
        }

        public SchoolProvider create_provider (School school, string device_name,
                                               string device_id) {
            return new DemoProvider (school);
        }
    }

    /* LUDUS (EG) schools — OIDC/MitID. Sign-in (LudusProvider) is implemented;
     * the school directory is fetched live from the API gateway. NOTE: the data
     * endpoints past sign-in are still stubbed (LudusError.NOT_MAPPED) pending a
     * live check of their response shapes — see docs/ludus-api.md. */
    public class LudusFamily : GLib.Object, ProviderFamily {
        public string id { get { return "ludus"; } }
        public string display_name { owned get { return _("LUDUS schools"); } }
        public string icon_name { get { return "network-workgroup-symbolic"; } }
        public bool available { get { return false; } }
        public string unavailable_note { owned get { return "In early development"; } }

        // Palette index for the (identical) LUDUS school avatars in the picker.
        private const int LUDUS_ACCENT = 5;

        /* A LUDUS School is fully determined by its institution number (the
         * "ludus:<number>" id) and display name — everything else is shared
         * constants. One builder, so the directory fetch and the saved-session
         * rebuild (SessionController.resolve_saved_school) can't drift. */
        public static School for_institution (string number, string name) {
            return new School ("ludus:" + number, name, "", "L",
                               LudusConfig.API_GATEWAY,
                               "1030", LUDUS_ACCENT, 0, 0, 1, "ludus");
        }

        public GLib.GenericArray<School> list_schools () {
            return new GLib.GenericArray<School> ();   // directory: see fetch_schools
        }

        /* Fetch the EG school directory and turn each entry into a School. The
         * live response carries institutionName + institutionNumber (verified);
         * the number identifies the school for API calls and rides in the id
         * ("ludus:<number>"). The Keycloak realm is a single shared constant
         * (LudusConfig.REALM), not per-school. */
        public async GLib.GenericArray<School> fetch_schools (
            GLib.Cancellable? cancellable = null) throws GLib.Error {
            var arr = yield new LudusClient ().fetch_schools (cancellable);
            var list = new GLib.GenericArray<School> ();
            for (uint i = 0; i < arr.get_length (); i++) {
                var node = arr.get_element (i);
                if (node.get_node_type () != Json.NodeType.OBJECT) {
                    continue;
                }
                var obj = node.get_object ();
                string inst = obj.get_string_member_with_default ("institutionNumber", "");
                if (inst == "") {
                    continue;   // no API identity — unusable
                }
                string name = obj.get_string_member_with_default ("institutionName", "");
                if (name == "") {
                    name = obj.get_string_member_with_default ("name", inst);
                }
                list.add (for_institution (inst, name));
            }
            return list;
        }

        public SchoolProvider create_provider (School school, string device_name,
                                               string device_id) {
            return new LudusProvider (school);   // device_* are UMS-only
        }
    }

    /* The known provider families, in picker order. */
    namespace Families {

        public GLib.GenericArray<ProviderFamily> all () {
            var list = new GLib.GenericArray<ProviderFamily> ();
            list.add (new UmsFamily ());
            list.add (new DemoFamily ());
            list.add (new LudusFamily ());
            return list;
        }

        public ProviderFamily by_id (string id) {
            var families = all ();
            for (uint i = 0; i < families.length; i++) {
                if (families[i].id == id) {
                    return families[i];
                }
            }
            return new UmsFamily ();   // default
        }
    }
}
