/* school-picker.vala
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

using Gtk;

namespace Opensprogskole {

    /* The "choose your school" dialog: provider families → a searchable list of
     * each family's schools → emit the pick. A footer offers a manual (Custom)
     * entry path. All of the chrome lives in the Blueprint; this only fills the
     * data-driven rows, filters them, and drives the custom form. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/school-picker.ui")]
    public class SchoolPicker : Adw.Dialog {

        [GtkChild] private unowned Adw.NavigationView nav;
        [GtkChild] private unowned Adw.PreferencesGroup families_group;
        [GtkChild] private unowned Button custom_button;
        [GtkChild] private unowned Stack list_stack;
        [GtkChild] private unowned SearchEntry search_entry;
        [GtkChild] private unowned Adw.PreferencesGroup schools_group;
        [GtkChild] private unowned Adw.StatusPage empty_page;
        [GtkChild] private unowned Adw.ComboRow backend_row;
        [GtkChild] private unowned Adw.EntryRow name_row;
        [GtkChild] private unowned Adw.EntryRow url_row;
        [GtkChild] private unowned Adw.EntryRow realm_row;
        [GtkChild] private unowned Label url_note;
        [GtkChild] private unowned Label custom_note;
        [GtkChild] private unowned Button use_button;

        /* The chosen school (a registry entry or a hand-entered Custom one). */
        public signal void school_chosen (School school);

        // The schools currently shown on the list page, with their rows, so the
        // search field can filter them in place.
        private GLib.GenericArray<School> listed = new GLib.GenericArray<School> ();
        private GLib.GenericArray<Adw.ActionRow> listed_rows =
            new GLib.GenericArray<Adw.ActionRow> ();

        construct {
            build_families ();

            backend_row.model = new StringList ({ _("UMS (username / password)"),
                                                  _("LUDUS (OIDC / MitID)") });

            custom_button.clicked.connect (() => nav.push_by_tag ("custom"));
            search_entry.search_changed.connect (filter_schools);
            backend_row.notify["selected"].connect (sync_backend);
            url_row.changed.connect (validate_custom);
            use_button.clicked.connect (on_use_custom);
            validate_custom ();
        }

        /* One row per family; tapping it opens that family's school list. */
        private void build_families () {
            var families = Families.all ();
            for (uint i = 0; i < families.length; i++) {
                var family = families[i];
                var row = new Adw.ActionRow () {
                    title = family.display_name,
                    activatable = true
                };
                if (!family.available) {
                    row.subtitle = family.unavailable_note;
                }
                row.add_prefix (new Image.from_icon_name (family.icon_name));
                row.add_suffix (new Image.from_icon_name ("go-next-symbolic"));
                row.activated.connect (() => open_family (family));
                families_group.add (row);
            }
        }

        /* Populate (and show) the shared school-list page for `family`. A family
         * with no schools — e.g. LUDUS until its directory is wired up — shows an
         * empty state instead. */
        private void open_family (ProviderFamily family) {
            for (uint i = 0; i < listed_rows.length; i++) {
                schools_group.remove (listed_rows[i]);
            }
            listed_rows = new GLib.GenericArray<Adw.ActionRow> ();
            listed = family.list_schools ();

            if (listed.length == 0) {
                empty_page.icon_name = family.available
                    ? "system-search-symbolic" : "network-workgroup-symbolic";
                empty_page.title = family.available
                    ? _("No schools yet") : family.unavailable_note;
                empty_page.description = family.available
                    ? _("This provider has no schools listed.")
                    : _("Sign-in for this provider isn't available yet.");
                list_stack.visible_child_name = "empty";
            } else {
                for (uint i = 0; i < listed.length; i++) {
                    var school = listed[i];
                    var row = new Adw.ActionRow () {
                        title = school.name,
                        subtitle = school.city,
                        activatable = true
                    };
                    row.add_suffix (new Image.from_icon_name ("go-next-symbolic"));
                    row.activated.connect (() => choose (school));
                    schools_group.add (row);
                    listed_rows.add (row);
                }
                search_entry.text = "";
                list_stack.visible_child_name = "list";
            }
            nav.push_by_tag ("school-list");
        }

        private void filter_schools () {
            string q = search_entry.text.strip ().down ();
            for (uint i = 0; i < listed_rows.length; i++) {
                var s = listed[i];
                listed_rows[i].visible = q == "" || s.name.down ().contains (q)
                                                  || s.city.down ().contains (q);
            }
        }

        // --- Custom form --------------------------------------------------------

        // Hosts a plain-http base URL is tolerated for: loopback only, so a
        // developer can point at a local backend without ever letting a real
        // password travel unencrypted.
        private const string[] PLAIN_HTTP_ALLOWED_HOSTS = { "localhost", "127.0.0.1", "::1" };

        private void sync_backend () {
            bool ludus = backend_row.selected == 1;
            realm_row.visible = ludus;
            custom_note.visible = ludus;
            validate_custom ();
        }

        /* Whether a hand-entered base URL is safe to log in against: parseable,
         * with a host, and https — credentials would otherwise go out in
         * cleartext. Plain http passes only toward loopback (local testing). */
        private static bool valid_custom_url (string url) {
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

        /* Gate "Use this provider" on a valid URL and flag a bad one inline.
         * The note only appears once something is typed — an empty field just
         * leaves the button off. */
        private void validate_custom () {
            string url = url_row.text.strip ();
            bool valid = valid_custom_url (url);
            bool problem = url != "" && !valid;
            url_note.visible = problem;
            if (problem) {
                url_row.add_css_class ("error");
            } else {
                url_row.remove_css_class ("error");
            }
            use_button.sensitive = valid
                && backend_row.selected == 0;   // LUDUS not implemented
        }

        private void on_use_custom () {
            if (backend_row.selected != 0 || !valid_custom_url (url_row.text.strip ())) {
                return;
            }
            choose (custom_ums_school (name_row.text.strip (), url_row.text.strip ()));
        }

        private void choose (School school) {
            school_chosen (school);
            close ();
        }

        /* A runtime School for a hand-entered UMS instance. */
        public static School custom_ums_school (string name, string base_url) {
            var school = new School ("custom",
                                     name != "" ? name : _("Custom school"),
                                     "", "★", base_url, "1030", 2, 0, 0, 1, "ums");
            school.is_custom = true;
            return school;
        }
    }
}
