/* onboarding-view.vala
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

    /* The pre-login flow: hello → pick a school (family → school in a dialog) →
     * the chosen instance's login methods → welcome. It only collects input and
     * drives navigation; the controller does the authentication. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/onboarding-view.ui")]
    public class OnboardingView : Adw.Bin {

        [GtkChild] private unowned Adw.NavigationView nav;
        [GtkChild] private unowned Button hello_next_button;
        [GtkChild] private unowned Adw.ActionRow school_row;
        [GtkChild] private unowned Adw.Avatar school_avatar;
        [GtkChild] private unowned Adw.PreferencesGroup credentials_group;
        [GtkChild] private unowned Adw.EntryRow username_row;
        [GtkChild] private unowned Adw.PasswordEntryRow password_row;
        [GtkChild] private unowned Adw.SwitchRow save_password_row;
        [GtkChild] private unowned Adw.Banner error_banner;
        [GtkChild] private unowned Adw.Spinner spinner;
        [GtkChild] private unowned Button login_button;
        [GtkChild] private unowned Button continue_button;
        [GtkChild] private unowned Label version_label;

        /* The controller handles this. credentials is an a{sv} of field key→value. */
        public signal void login_request (School school, LoginMethod method,
                                          GLib.Variant credentials, bool remember);
        public signal void finished ();

        private School? selected_school = null;
        private GLib.GenericArray<LoginMethod> methods = new GLib.GenericArray<LoginMethod> ();

        construct {
            version_label.label = _("Version %s").printf (Config.PACKAGE_VERSION);

            hello_next_button.clicked.connect (() => nav.push_by_tag ("login"));
            school_row.activated.connect (present_school_picker);
            login_button.clicked.connect (on_login);
            continue_button.clicked.connect (() => finished ());
        }

        // --- School picker: a ViewStack switching Known schools / Custom backend -
        private void present_school_picker () {
            var dialog = new Adw.Dialog () {
                title = _("Choose your school"),
                content_width = 420,
                content_height = 560
            };

            var stack = new Adw.ViewStack ();
            stack.add_titled_with_icon (build_known_view (dialog), "known",
                                        _("Schools"), "view-list-symbolic");
            stack.add_titled_with_icon (build_custom_view (dialog), "custom",
                                        _("Custom"), "document-edit-symbolic");

            var header = new Adw.HeaderBar () {
                title_widget = new Adw.ViewSwitcher () {
                    stack = stack,
                    policy = Adw.ViewSwitcherPolicy.WIDE
                }
            };
            var view = new Adw.ToolbarView () { content = stack };
            view.add_top_bar (header);
            dialog.child = view;
            dialog.present (this);
        }

        /* Known schools, grouped by family (unavailable families show their note). */
        private Gtk.Widget build_known_view (Adw.Dialog dialog) {
            var box = new Box (Orientation.VERTICAL, 18);
            var families = Families.all ();
            for (uint i = 0; i < families.length; i++) {
                var family = families[i];
                var group = new Adw.PreferencesGroup () { title = family.display_name };
                if (!family.available) {
                    group.description = family.unavailable_note;
                }
                var schools = family.list_schools ();
                for (uint j = 0; j < schools.length; j++) {
                    var school = schools[j];
                    var row = new Adw.ActionRow () {
                        title = school.name,
                        subtitle = school.city,
                        activatable = true
                    };
                    row.add_suffix (new Image.from_icon_name ("go-next-symbolic"));
                    row.activated.connect (() => {
                        select_school (school);
                        dialog.close ();
                    });
                    group.add (row);
                }
                box.append (group);
            }
            return scrolled (box);
        }

        /* Custom backend: pick a provider type and enter its endpoint(s). UMS works
         * (base URL → username/password); LUDUS shows its OIDC fields but isn't
         * wired yet. */
        private Gtk.Widget build_custom_view (Adw.Dialog dialog) {
            var backend = new Adw.ComboRow () {
                title = _("Backend"),
                model = new Gtk.StringList ({ _("UMS (username / password)"),
                                              _("LUDUS (OIDC / MitID)") })
            };
            var name_row = new Adw.EntryRow () { title = _("Display name") };
            var url_row = new Adw.EntryRow () { title = _("Base URL") };
            var realm_row = new Adw.EntryRow () { title = _("Realm (OIDC)"), visible = false };
            var note = new Gtk.Label (_("LUDUS sign-in isn't available yet.")) {
                halign = Align.START, visible = false, margin_start = 4
            };
            note.add_css_class ("dim-label");

            var group = new Adw.PreferencesGroup ();
            group.add (backend);
            group.add (name_row);
            group.add (url_row);
            group.add (realm_row);

            var use_button = new Button.with_label (_("Use this provider")) {
                halign = Align.CENTER, margin_top = 6
            };
            use_button.add_css_class ("suggested-action");
            use_button.add_css_class ("pill");

            backend.notify["selected"].connect (() => {
                bool ludus = backend.selected == 1;
                realm_row.visible = ludus;
                note.visible = ludus;
                use_button.sensitive = !ludus;   // LUDUS not implemented
            });

            use_button.clicked.connect (() => {
                if (backend.selected != 0 || url_row.text.strip () == "") {
                    return;
                }
                select_school (custom_ums_school (name_row.text.strip (), url_row.text.strip ()));
                dialog.close ();
            });

            var box = new Box (Orientation.VERTICAL, 12);
            box.append (group);
            box.append (note);
            box.append (use_button);
            return scrolled (box);
        }

        /* A runtime School for a hand-entered UMS instance. */
        public static School custom_ums_school (string name, string base_url) {
            var school = new School ("custom",
                                     name != "" ? name : _("Custom school"),
                                     "", "★", base_url, "1030", 2, 0, 0, 1, "ums");
            school.is_custom = true;
            return school;
        }

        /* Scrollable, clamped content. */
        private Gtk.Widget scrolled (Gtk.Widget content) {
            var clamp = new Adw.Clamp () {
                maximum_size = 420,
                margin_top = 12, margin_bottom = 18, margin_start = 12, margin_end = 12,
                child = content
            };
            return new ScrolledWindow () {
                hscrollbar_policy = PolicyType.NEVER,
                child = clamp
            };
        }

        // --- Auth section, driven by the chosen school's methods ----------------
        private void select_school (School school) {
            selected_school = school;
            school_row.subtitle = school.name;
            school_avatar.text = school.short_code;
            update_auth.begin ();
        }

        private async void update_auth () {
            if (selected_school == null) {
                return;
            }
            var family = Families.by_id (selected_school.family_id);
            var provider = family.create_provider (selected_school, "", "");
            try {
                methods = yield provider.login_methods ();
            } catch (GLib.Error e) {
                warning ("login methods failed: %s", e.message);
                methods = new GLib.GenericArray<LoginMethod> ();
            }
            render_auth ();
        }

        private void render_auth () {
            credentials_group.visible = has_kind (LoginKind.PASSWORD);
            login_button.label = has_kind (LoginKind.PASSWORD) ? _("Log in") : _("Enter");
            login_button.sensitive = methods.length > 0;
        }

        private bool has_kind (LoginKind kind) {
            for (uint i = 0; i < methods.length; i++) {
                if (methods[i].kind == kind) {
                    return true;
                }
            }
            return false;
        }

        private void on_login () {
            error_banner.revealed = false;
            if (selected_school == null) {
                return;
            }
            var method = chosen_method ();
            if (method == null) {
                return;
            }

            var creds = new GLib.VariantDict ();
            if (method.kind == LoginKind.PASSWORD) {
                // The standard two fields map to the two rows.
                creds.insert_value ("username", new GLib.Variant.string (username_row.text));
                creds.insert_value ("password", new GLib.Variant.string (password_row.text));
            }
            login_request (selected_school, method, creds.end (), save_password_row.active);
        }

        /* Prefer a password method (the form is filled); else the first method. */
        private LoginMethod? chosen_method () {
            for (uint i = 0; i < methods.length; i++) {
                if (methods[i].kind == LoginKind.PASSWORD) {
                    return methods[i];
                }
            }
            return methods.length > 0 ? methods[0] : null;
        }

        // --- Driven by the controller -------------------------------------------
        public void set_busy (bool busy) {
            spinner.visible = busy;
            login_button.sensitive = !busy && methods.length > 0;
            school_row.sensitive = !busy;
            credentials_group.sensitive = !busy;
        }

        public void show_error (string message) {
            error_banner.title = message;
            error_banner.revealed = true;
        }

        public void login_succeeded () {
            error_banner.revealed = false;
            nav.push_by_tag ("welcome");
        }

        /* Pre-fill the username (used when a saved account failed silent login);
         * default-select the first UMS school so the form is usable. */
        public void prefill (string username) {
            select_school (Schools.spc_midt ());
            username_row.text = username;
            nav.push_by_tag ("login");
        }

        public void reset () {
            password_row.text = "";
            error_banner.revealed = false;
            nav.pop_to_tag ("hello");
        }
    }
}
