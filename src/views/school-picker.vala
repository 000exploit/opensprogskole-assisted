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
        [GtkChild] private unowned Label api_note;
        [GtkChild] private unowned Label custom_note;
        [GtkChild] private unowned Button use_button;
        [GtkChild] private unowned Button paste_button;
        [GtkChild] private unowned Button copy_button;
        [GtkChild] private unowned Revealer paste_note_revealer;
        [GtkChild] private unowned Label paste_note;
        [GtkChild] private unowned Adw.AlertDialog paste_dialog;

        // The Blueprint-defined resting strings, captured before code ever
        // overwrites them (a dynamic parse error, the "Copied" feedback).
        private string default_paste_error;
        private string default_copy_label;

        /* The chosen school (a registry entry or a hand-entered Custom one). */
        public signal void school_chosen (School school);

        // The schools currently shown on the list page, with their rows, so the
        // search field can filter them in place.
        private GLib.GenericArray<School> listed = new GLib.GenericArray<School> ();
        private GLib.GenericArray<Adw.ActionRow> listed_rows =
            new GLib.GenericArray<Adw.ActionRow> ();

        construct {
            default_paste_error = paste_note.label;
            default_copy_label = copy_button.label;
            build_families ();

            backend_row.model = new StringList ({ _("UMS (username / password)"),
                                                  _("LUDUS (OIDC / MitID)") });

            custom_button.clicked.connect (() => nav.push_by_tag ("custom"));
            search_entry.search_changed.connect (filter_schools);
            backend_row.notify["selected"].connect (sync_backend);
            url_row.changed.connect (validate_custom);
            use_button.clicked.connect (on_use_custom);
            paste_button.clicked.connect (on_paste_config);
            copy_button.clicked.connect (on_copy_config);
            paste_dialog.response.connect ((response) => {
                if (response == "use" && pasted != null) {
                    choose (pasted);
                }
            });
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

        private void sync_backend () {
            bool ludus = backend_row.selected == 1;
            realm_row.visible = ludus;
            custom_note.visible = ludus;
            validate_custom ();
        }

        /* Gate "Use this provider" on a valid URL and flag problems inline.
         * The scheme is a hard requirement (credential safety); the UMS
         * "/api" shape is only a warning — an instance may serve the API
         * elsewhere, so the button stays on. The notes only appear once
         * something is typed — an empty field just leaves the button off.
         * The policies live with the config parser (SchoolConfig) so pasted
         * configs share them. */
        private void validate_custom () {
            string url = url_row.text.strip ();
            bool ums = backend_row.selected == 0;   // LUDUS not implemented
            bool scheme_ok = SchoolConfig.valid_base_url (url);
            url_note.visible = url != "" && !scheme_ok;
            api_note.visible = url != "" && scheme_ok && ums
                && !SchoolConfig.valid_ums_base_url (url);
            if (url_note.visible) {
                url_row.add_css_class ("error");
            } else {
                url_row.remove_css_class ("error");
            }
            use_button.sensitive = ums && scheme_ok;
            // A copied config is exactly what "Use this provider" would use.
            copy_button.sensitive = use_button.sensitive;
        }

        private void on_use_custom () {
            if (backend_row.selected != 0
                || !SchoolConfig.valid_base_url (url_row.text.strip ())) {
                return;
            }
            choose (custom_ums_school (name_row.text.strip (), url_row.text.strip ()));
        }

        // --- Config sharing -----------------------------------------------------

        // How long the Copy button confirms before its label reverts.
        private const uint COPY_FEEDBACK_MS = 1500;

        // A parsed-but-unconfirmed pasted config, kept while paste_dialog asks.
        private School? pasted = null;

        private uint copy_feedback_source = 0;

        /* Read a config from the clipboard and, when it parses, confirm the
         * school (name + the URL credentials would go to) before using it.
         * Pasted configs are session-only — nothing is written anywhere. */
        private void on_paste_config () {
            paste_note_revealer.reveal_child = false;
            var clipboard = get_clipboard ();
            clipboard.read_text_async.begin (null, (obj, res) => {
                string? text = null;
                try {
                    text = clipboard.read_text_async.end (res);
                } catch (GLib.Error e) {
                    // Fall through to the empty-clipboard message.
                }
                if (text == null || text.strip () == "") {
                    show_paste_error ();
                    return;
                }
                try {
                    pasted = SchoolConfig.from_json (text);
                } catch (SchoolConfigError e) {
                    show_paste_error (e.message);
                    return;
                }
                string body = "%s\n%s".printf (pasted.name, pasted.base_url);
                if (!SchoolConfig.valid_ums_base_url (pasted.base_url)) {
                    // Reuse the form's Blueprint-defined warning verbatim.
                    body += "\n\n" + api_note.label;
                }
                paste_dialog.body = body;
                paste_dialog.present (this);
            });
        }

        /* Copy the school the form would produce, to share or keep. */
        private void on_copy_config () {
            copy_button.get_clipboard ().set_text (SchoolConfig.to_json (
                custom_ums_school (name_row.text.strip (), url_row.text.strip ())));
            copy_button.label = _("Copied");
            if (copy_feedback_source != 0) {
                GLib.Source.remove (copy_feedback_source);
            }
            copy_feedback_source = GLib.Timeout.add (COPY_FEEDBACK_MS, () => {
                copy_button.label = default_copy_label;
                copy_feedback_source = 0;
                return GLib.Source.REMOVE;
            });
        }

        /* Reveal the error note: a dynamic message (parse failure), or with
         * no argument the label's Blueprint default (empty clipboard). */
        private void show_paste_error (string? message = null) {
            paste_note.label = message ?? default_paste_error;
            paste_note_revealer.reveal_child = true;
        }

        private void choose (School school) {
            school_chosen (school);
            close ();
        }

        /* A runtime School for a hand-entered UMS instance. */
        public static School custom_ums_school (string name, string base_url) {
            var school = new School ("custom",
                                     name != "" ? name : _("Custom school"),
                                     "", "★",
                                     SchoolConfig.normalize_base_url (base_url),
                                     "1030", 2, 0, 0, 1, "ums");
            school.is_custom = true;
            return school;
        }
    }
}
