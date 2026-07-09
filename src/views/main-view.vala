/* main-view.vala
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

    /* The post-login shell, adaptive via Adw.MultiLayoutView: a width breakpoint
     * picks the "wide" layout (sidebar drives the sections) or the "narrow" one
     * (bottom ViewSwitcherBar) — one at a time, identical on every backend. Both
     * nav controls drive the same ViewStack; secondary sections (News/Homework/
     * Links) and the profile-edit drill-in push onto the content NavigationView. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/main-view.ui")]
    public class MainView : Adw.Bin {

        [GtkChild] private unowned Adw.MultiLayoutView multi;
        [GtkChild] private unowned Adw.Avatar school_avatar;
        [GtkChild] private unowned Label school_label;
        [GtkChild] private unowned Label connection_label;
        [GtkChild] private unowned Gtk.ListBox nav_list;
        [GtkChild] private unowned Gtk.ListBox more_list;
        [GtkChild] private unowned Adw.NavigationView content_nav;
        [GtkChild] private unowned Adw.ViewStack view_stack;
        [GtkChild] private unowned NavBar nav_bar;
        [GtkChild] private unowned Gtk.MenuButton menu_button;
        [GtkChild] private unowned Gtk.Revealer bottom_revealer;
        [GtkChild] private unowned Adw.WindowTitle content_title;
        [GtkChild] private unowned Adw.Banner offline_banner;
        [GtkChild] private unowned Button profile_button;
        [GtkChild] private unowned Adw.Avatar profile_avatar;
        [GtkChild] private unowned Label profile_name;
        [GtkChild] private unowned DashboardView overview;
        [GtkChild] private unowned ScheduleView schedule;
        [GtkChild] private unowned AbsencePage absence;
        [GtkChild] private unowned GradesPage grades_page;
        [GtkChild] private unowned ProfilePage profile;
        [GtkChild] private unowned LinksPage links_page;

        private Session? session = null;
        private GLib.SimpleAction edit_action;

        // The core sections shown as ViewStack tabs (vs. the secondary pages that
        // are pushed onto content_nav).
        private const string[] TABS = { "overview", "schedule", "grades", "absence", "profile" };

        // row -> page tag
        private GLib.HashTable<Gtk.ListBoxRow, string> page_of
            = new GLib.HashTable<Gtk.ListBoxRow, string> (direct_hash, direct_equal);

        construct {
            // Establish the default layout here, not in the .blp: setting
            // layout-name as a template property runs before the layouts are
            // added (Adwaita-CRITICAL) and leaves the width breakpoint without a
            // valid value to save/restore. Set once the template (and its
            // layouts) exist.
            multi.layout_name = "wide";

            // Both nav controls (sidebar rows + bottom-bar buttons) are built from
            // one shared section list in bind(), once the provider is known — see
            // build_nav(). Their activation is wired here (works for rows/buttons
            // added later).
            nav_list.row_activated.connect ((row) => navigate (page_of[row]));
            more_list.row_activated.connect ((row) => navigate (page_of[row]));
            nav_bar.section_activated.connect (navigate);
            profile_button.clicked.connect (() => navigate ("profile"));
            overview.report_absence_requested.connect (open_absence_dialog);
            absence.report_absence_requested.connect (open_absence_dialog);
            overview.section_requested.connect ((tag) => {
                navigate (tag);
                if (tag == "schedule") {
                    schedule.focus_upcoming ();
                }
            });
            profile.edit_requested.connect (open_profile_edit);

            // "view.refresh" backs the refresh buttons in both layouts' headers
            // (one action, no duplicated logic).
            var view_group = new GLib.SimpleActionGroup ();
            var refresh_action = new GLib.SimpleAction ("refresh", null);
            refresh_action.activate.connect (() => {
                if (session != null) {
                    session.refresh_all ();
                }
            });
            view_group.add_action (refresh_action);
            insert_action_group ("view", view_group);

            // "nav.section" backs the header menu's secondary-section items; the
            // string target is the page tag to open.
            var nav_group = new GLib.SimpleActionGroup ();
            var section_action = new GLib.SimpleAction ("section", GLib.VariantType.STRING);
            section_action.activate.connect ((param) => navigate (param.get_string ()));
            nav_group.add_action (section_action);
            insert_action_group ("nav", nav_group);

            // "profile.edit" backs the menus' "Edit information" item; disabled
            // until we learn the school allows editing.
            var profile_group = new GLib.SimpleActionGroup ();
            edit_action = new GLib.SimpleAction ("edit", null);
            edit_action.set_enabled (false);
            edit_action.activate.connect (() => open_profile_edit ());
            profile_group.add_action (edit_action);
            insert_action_group ("profile", profile_group);

            Connectivity.get_default ().notify["online"].connect (() => {
                update_connection_status ();
                sync_footer ();
            });
            update_connection_status ();

            // Hide the bottom bar while a secondary page is pushed (the tab shell
            // is "tabs"); show it on the tab shell. Adw.ViewSwitcherBar has no
            // re-tap signal, so a persistent bar can't reliably close a drill-in
            // — hiding it sidesteps that and keeps drill-ins focused.
            content_nav.notify["visible-page"].connect (update_bottom_bar);

            // The ViewStack is the source of truth: whichever control (sidebar or
            // bottom bar) switches it, reflect that in the sidebar highlight and
            // the content header title.
            view_stack.notify["visible-child"].connect (sync_selection);
            content_nav.notify["visible-page"].connect (sync_selection);
            sync_selection ();
            update_bottom_bar ();
        }

        public void bind (Session session) {
            this.session = session;
            school_label.label = session.school.name;
            school_avatar.text = session.school.short_code;

            // Build both nav controls from the provider's available sections, then
            // reflect the current tab on the freshly-built rows/buttons.
            build_nav (session.provider);
            sync_selection ();

            overview.bind (session);
            schedule.use_store (session.timetable);
            schedule.session = session;
            absence.bind (session);
            grades_page.bind (session);
            profile.bind (session);
            links_page.bind (session);

            sync_footer ();
            session.updated.connect (sync_footer);
        }

        /* Connectivity in both the sidebar status line and the content banner. */
        private void update_connection_status () {
            bool online = Connectivity.get_default ().online;
            connection_label.label = online ? _("Connected") : _("Offline");
            if (online) {
                connection_label.remove_css_class ("warning");
            } else {
                connection_label.add_css_class ("warning");
            }
            offline_banner.revealed = !online;
        }

        /* Footer label + avatar + the "Edit information" action's enabled state.
         * Editing is a write, so it also needs a connection. */
        private void sync_footer () {
            if (session == null) {
                return;
            }
            profile_name.label = session.display_name;
            profile_avatar.text = session.display_name;
            load_profile_avatar.begin ();
            edit_action.set_enabled (
                session.user_settings != null && session.user_settings.any_editable
                && Connectivity.get_default ().online);
        }

        private async void load_profile_avatar () {
            if (session == null) {
                return;
            }
            // May assign twice: the cached picture at once, the revalidated
            // one when it differs (see AvatarCache).
            yield session.load_avatar ((paintable) => {
                profile_avatar.custom_image = paintable;
            });
        }

        /* Bottom bar shows on the tab shell, hides while a secondary page is
         * pushed (so the drill-in is full-height and the bar can't sit there
         * half-working). */
        private void update_bottom_bar () {
            var page = content_nav.visible_page;
            bottom_revealer.reveal_child = page != null && page.tag == "tabs";
        }

        /* A core section switches the ViewStack tab; a secondary section is
         * pushed on top. Returning to the tab shell first means we never stack. */
        private void navigate (string tag) {
            content_nav.pop_to_tag ("tabs");
            if (tag in TABS) {
                view_stack.visible_child_name = tag;
            } else {
                content_nav.push_by_tag (tag);
            }
        }

        private void open_profile_edit () {
            if (session == null || session.user_info == null) {
                return;
            }
            var page = new EditProfilePage (session);
            page.done.connect (() => content_nav.pop ());
            content_nav.push (page);
        }

        private void open_absence_dialog () {
            if (session != null) {
                var dialog = new AbsenceDialog (session);
                dialog.show_absences_requested.connect (() => navigate ("absence"));
                dialog.present (this);
            }
        }

        /* Populate both nav controls from the shared section catalog — the
         * "adding cycle" — filtered to what this provider can serve. The sidebar
         * takes every available section (PRIMARY→nav_list, others→more_list); the
         * bottom bar takes the PRIMARY ones only (parity with the old
         * ViewSwitcherBar, which mirrored the core ViewStack pages). */
        private void build_nav (SchoolProvider provider) {
            var bar_sections = new GLib.GenericArray<NavSection> ();
            // The narrow header menu's secondary section, built from the same
            // catalog so it lists exactly the sidebar's "More" entries.
            var secondary_menu = new GLib.Menu ();
            foreach (var s in NavSection.catalog ()) {
                if (!s.available_for (provider)) {
                    continue;
                }
                if (s.placement == NavPlacement.PRIMARY) {
                    add_nav (nav_list, s.icon_name, s.title, s.tag);
                    bar_sections.add (s);
                } else {
                    add_nav (more_list, s.icon_name, s.title, s.tag);
                    // "nav.section::<tag>" — the string-target detailed action.
                    secondary_menu.append (s.title, @"nav.section::$(s.tag)");
                }
            }
            nav_bar.set_sections (bar_sections);
            // Prepend as the header menu's first section — only when the school
            // actually has any (LUDUS has none → no empty separator). The menu is
            // the mutable GMenu built from primary_menu in the .blp.
            if (secondary_menu.get_n_items () > 0) {
                var menu = menu_button.menu_model as GLib.Menu;
                if (menu != null) {
                    menu.prepend_section (null, secondary_menu);
                }
            }
        }

        private void add_nav (Gtk.ListBox list, string icon, string label, string page) {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
                margin_top = 6, margin_bottom = 6, margin_start = 6, margin_end = 6
            };
            box.append (new Gtk.Image.from_icon_name (icon));
            box.append (new Gtk.Label (label) { halign = Gtk.Align.START, hexpand = true });

            var row = new Gtk.ListBoxRow () { child = box };
            page_of[row] = page;
            list.append (row);
        }

        /* Keep the sidebar highlight and the content title on whatever is shown:
         * a pushed secondary page, or the current tab in the stack. */
        private void sync_selection () {
            var page = content_nav.visible_page;
            string tag = (page != null && page.tag != "tabs")
                ? page.tag
                : view_stack.visible_child_name;

            select_row_for_tag (nav_list, tag);
            select_row_for_tag (more_list, tag);
            nav_bar.select (tag);
            if (tag in TABS) {
                content_title.title = tab_title (tag);
            }
        }

        private string tab_title (string tag) {
            switch (tag) {
                case "schedule": return _("Schedule");
                case "grades":   return _("Grades");
                case "absence":  return _("Absence");
                case "profile":  return _("Your information");
                default:         return _("Overview");
            }
        }

        private void select_row_for_tag (Gtk.ListBox list, string tag) {
            for (int i = 0; ; i++) {
                var row = list.get_row_at_index (i);
                if (row == null) {
                    break;
                }
                if (page_of[row] == tag) {
                    list.select_row (row);
                    return;
                }
            }
            list.unselect_all ();
        }

        /* One step of back navigation for the Android system-back handler: pop a
         * pushed secondary page, else fall back from a tab to Overview, else
         * report nothing left so the app may leave. */
        public bool handle_back () {
            if (content_nav.navigation_stack.get_n_items () > 1) {
                content_nav.pop ();
                return true;
            }
            if (view_stack.visible_child_name != "overview") {
                view_stack.visible_child_name = "overview";
                return true;
            }
            return false;
        }
    }
}
