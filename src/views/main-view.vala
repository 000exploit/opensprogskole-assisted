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

    /* The post-login shell: an Adw.NavigationSplitView (sidebar + content) that
     * collapses to a single pane under the breakpoint for narrow screens. The
     * sidebar lists the sections (no school switcher — just a "connected to"
     * label); the content side is a stack of pages. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/main-view.ui")]
    public class MainView : Adw.Bin {

        [GtkChild] private unowned Adw.NavigationSplitView split;
        [GtkChild] private unowned Adw.Avatar school_avatar;
        [GtkChild] private unowned Label school_label;
        [GtkChild] private unowned Label connection_label;
        [GtkChild] private unowned Gtk.ListBox nav_list;
        [GtkChild] private unowned Gtk.ListBox more_list;
        [GtkChild] private unowned Button refresh_button;
        [GtkChild] private unowned Adw.NavigationView content_nav;
        [GtkChild] private unowned Button profile_button;
        [GtkChild] private unowned Adw.Avatar profile_avatar;
        [GtkChild] private unowned Label profile_name;
        [GtkChild] private unowned OverviewPage overview;
        [GtkChild] private unowned ScheduleView schedule;
        [GtkChild] private unowned AbsencePage absence;
        [GtkChild] private unowned GradesPage grades_page;
        [GtkChild] private unowned ProfilePage profile;
        [GtkChild] private unowned LinksPage links_page;

        private Session? session = null;
        private GLib.SimpleAction edit_action;

        // row -> page tag
        private GLib.HashTable<Gtk.ListBoxRow, string> page_of
            = new GLib.HashTable<Gtk.ListBoxRow, string> (direct_hash, direct_equal);

        construct {
            add_nav (nav_list, "view-grid-symbolic", _("Overview"), "overview");
            add_nav (nav_list, "x-office-calendar-symbolic", _("Schedule"), "schedule");
            add_nav (nav_list, "starred-symbolic", _("Grades"), "grades");
            add_nav (nav_list, "appointment-soon-symbolic", _("Absence"), "absence");
            add_nav (nav_list, "avatar-default-symbolic", _("Your information"), "profile");

            add_nav (more_list, "application-rss+xml-symbolic", _("News"), "news");
            add_nav (more_list, "folder-documents-symbolic", _("Homework"), "homework");
            add_nav (more_list, "web-browser-symbolic", _("Links"), "links");

            nav_list.row_activated.connect ((row) => navigate (page_of[row]));
            more_list.row_activated.connect ((row) => navigate (page_of[row]));
            profile_button.clicked.connect (() => navigate ("profile"));
            refresh_button.clicked.connect (() => {
                if (session != null) {
                    session.refresh_all ();
                }
            });
            overview.report_absence_requested.connect (open_absence_dialog);
            absence.report_absence_requested.connect (open_absence_dialog);
            overview.open_schedule.connect (() => navigate ("schedule"));
            overview.open_grades.connect (() => navigate ("grades"));
            profile.edit_requested.connect (open_profile_edit);

            // "profile.edit" backs the profile popover's "Edit information" item;
            // it stays disabled until we learn the school allows editing.
            var group = new GLib.SimpleActionGroup ();
            edit_action = new GLib.SimpleAction ("edit", null);
            edit_action.set_enabled (false);
            edit_action.activate.connect (() => open_profile_edit ());
            group.add_action (edit_action);
            insert_action_group ("profile", group);

            // Connectivity drives the sidebar status line and (via sync_footer)
            // the edit action's enabled state.
            Connectivity.get_default ().notify["online"].connect (() => {
                update_connection_status ();
                sync_footer ();
            });
            update_connection_status ();

            content_nav.replace_with_tags ({ "overview" });
            content_nav.notify["visible-page"].connect (sync_to_visible_page);
            sync_to_visible_page ();
        }

        public void bind (Session session) {
            this.session = session;
            school_label.label = session.school.name;
            school_avatar.text = session.school.short_code;

            overview.bind (session);
            schedule.use_store (session.timetable);
            schedule.session = session;
            absence.bind (session);
            grades_page.bind (session);
            profile.bind (session);
            links_page.bind (session);

            // Sync the footer chrome now (the session's initial updated() fires
            // during refresh(), before this bind connects — so we can't rely on
            // the signal for the first paint) and again whenever data changes.
            sync_footer ();
            session.updated.connect (sync_footer);
        }

        /* Reflect connectivity in the sidebar status line under the school name. */
        private void update_connection_status () {
            bool online = Connectivity.get_default ().online;
            connection_label.label = online ? _("Connected") : _("Offline");
            if (online) {
                connection_label.remove_css_class ("warning");
            } else {
                connection_label.add_css_class ("warning");
            }
        }

        /* Footer label + avatar + the "Edit information" action's enabled state,
         * kept in step with the session (incl. after a picture upload). Editing is
         * a write, so it also needs a connection. */
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

        /* Mirror the profile picture into the sidebar footer avatar; leaves the
         * initials in place when there is none. */
        private async void load_profile_avatar () {
            if (session == null) {
                return;
            }
            var paintable = yield session.load_avatar ();
            profile_avatar.custom_image = paintable;
        }

        /* Push the editable profile page on top of the profile page; pops back
         * to it on a successful save. */
        private void open_profile_edit () {
            if (session == null || session.user_info == null) {
                return;
            }
            var page = new EditProfilePage (session);
            page.done.connect (() => content_nav.pop ());
            content_nav.push (page);
            if (split.collapsed) {
                split.show_content = true;
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

        /* Push a section on top of the Overview root (back arrow returns to it);
         * "overview" just pops back to the root. Reveals content when collapsed. */
        private void navigate (string tag) {
            // "Report absence" is an action, not a page — open the dialog and keep
            // the sidebar highlight on whatever page is actually shown.
            if (tag == "overview") {
                content_nav.pop_to_tag ("overview");
            } else {
                content_nav.pop_to_tag ("overview");
                content_nav.push_by_tag (tag);
            }
            if (split.collapsed) {
                split.show_content = true;
            }
        }

        /* One step of back navigation, for the Android system-back handler:
         * pop a pushed section, else (when collapsed) return from the content to
         * the sidebar. Returns false when already at the root with nowhere left
         * to go — the window then treats back as "leave the app". */
        public bool handle_back () {
            if (content_nav.navigation_stack.get_n_items () > 1) {
                content_nav.pop ();
                return true;
            }
            if (split.collapsed && split.show_content) {
                split.show_content = false;   // back to the sidebar/menu
                return true;
            }
            return false;
        }

        private void open_absence_dialog () {
            if (session != null) {
                var dialog = new AbsenceDialog (session);
                // "Earlier" has no create flow — it sends the user to the Absence
                // page, where existing absences can be edited or removed.
                dialog.show_absences_requested.connect (() => navigate ("absence"));
                dialog.present (this);
            }
        }

        /* Keep the sidebar highlight on whatever page is actually visible — the
         * single source of truth, so the two can never desync. */
        private void sync_to_visible_page () {
            var page = content_nav.visible_page;
            if (page == null) {
                return;
            }
            // The edit sub-page lives "under" profile — keep that row highlighted.
            string tag = page.tag == "profile-edit" ? "profile" : page.tag;
            select_row_for_tag (nav_list, tag);
            select_row_for_tag (more_list, tag);
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
    }
}
