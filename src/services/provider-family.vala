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

        /* The selectable schools in this family (static today; a future family may
         * fetch its directory). */
        public abstract GLib.GenericArray<School> list_schools ();

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
        public string icon_name { get { return "school-symbolic"; } }
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

    /* LUDUS (EG) schools — OAuth/MitID. Not usable yet: shown greyed-out until the
     * OAuth flow + per-school directory land. */
    public class LudusFamily : GLib.Object, ProviderFamily {
        public string id { get { return "ludus"; } }
        public string display_name { owned get { return _("LUDUS schools"); } }
        public string icon_name { get { return "globe-symbolic"; } }
        public bool available { get { return false; } }
        public string unavailable_note { owned get { return _("Coming soon"); } }

        public GLib.GenericArray<School> list_schools () {
            return new GLib.GenericArray<School> ();   // fetched later
        }

        public SchoolProvider create_provider (School school, string device_name,
                                               string device_id) {
            assert_not_reached ();   // unavailable — never selected
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
