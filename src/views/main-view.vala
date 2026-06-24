/* main-view.vala
 *
 * Copyright 2026 flex
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
        [GtkChild] private unowned Gtk.ListBox nav_list;
        [GtkChild] private unowned Gtk.ListBox more_list;
        [GtkChild] private unowned Adw.NavigationPage content_page;
        [GtkChild] private unowned Adw.NavigationView content_nav;
        [GtkChild] private unowned Button profile_button;
        [GtkChild] private unowned Adw.Avatar profile_avatar;
        [GtkChild] private unowned Label profile_name;
        [GtkChild] private unowned OverviewPage overview;
        [GtkChild] private unowned ScheduleView schedule;
        [GtkChild] private unowned AbsencePage absence;
        [GtkChild] private unowned ProfilePage profile;

        private Session? session = null;

        // row -> (page name, title)
        private GLib.HashTable<Gtk.ListBoxRow, string> page_of
            = new GLib.HashTable<Gtk.ListBoxRow, string> (direct_hash, direct_equal);
        private GLib.HashTable<Gtk.ListBoxRow, string> title_of
            = new GLib.HashTable<Gtk.ListBoxRow, string> (direct_hash, direct_equal);

        construct {
            add_nav (nav_list, "view-grid-symbolic", _("Overview"), "overview");
            add_nav (nav_list, "x-office-calendar-symbolic", _("Schedule"), "schedule");
            add_nav (nav_list, "starred-symbolic", _("Grades"), "grades");
            add_nav (nav_list, "appointment-missed-symbolic", _("Absence"), "absence");
            add_nav (nav_list, "mail-send-symbolic", _("Report absence"), "report");
            add_nav (nav_list, "avatar-default-symbolic", _("Your information"), "profile");

            add_nav (more_list, "emblem-documents-symbolic", _("News"), "news");
            add_nav (more_list, "object-select-symbolic", _("Homework"), "homework");
            add_nav (more_list, "web-browser-symbolic", _("Links"), "links");

            nav_list.row_activated.connect ((row) => navigate (page_of[row]));
            more_list.row_activated.connect ((row) => navigate (page_of[row]));
            profile_button.clicked.connect (() => navigate ("profile"));
            overview.report_absence_requested.connect (open_absence_dialog);
            overview.open_schedule.connect (() => navigate ("schedule"));
            overview.open_grades.connect (() => navigate ("grades"));

            content_nav.replace_with_tags ({ "overview" });
            content_nav.notify["visible-page"].connect (sync_to_visible_page);
            sync_to_visible_page ();
        }

        public void bind (Session session) {
            this.session = session;
            school_label.label = session.school.name;
            school_avatar.text = session.school.short_code;
            profile_name.label = session.display_name;
            profile_avatar.text = session.display_name;

            overview.bind (session);
            schedule.use_store (session.timetable);
            absence.bind (session);
            profile.bind (session);

            // Keep the profile/footer label fresh once user info arrives.
            session.updated.connect (() => {
                profile_name.label = session.display_name;
                profile_avatar.text = session.display_name;
            });
        }

        private void add_nav (Gtk.ListBox list, string icon, string label, string page) {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
                margin_top = 6, margin_bottom = 6, margin_start = 6, margin_end = 6
            };
            box.append (new Gtk.Image.from_icon_name (icon));
            box.append (new Gtk.Label (label) { halign = Gtk.Align.START, hexpand = true });

            var row = new Gtk.ListBoxRow () { child = box };
            page_of[row] = page;
            title_of[row] = label;
            list.append (row);
        }

        /* Push a section on top of the Overview root (back arrow returns to it);
         * "overview" just pops back to the root. Reveals content when collapsed. */
        private void navigate (string tag) {
            // "Report absence" is an action, not a page — open the dialog and keep
            // the sidebar highlight on whatever page is actually shown.
            if (tag == "report") {
                open_absence_dialog ();
                sync_to_visible_page ();
                return;
            }
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

        private void open_absence_dialog () {
            if (session != null) {
                new AbsenceDialog (session).present (this);
            }
        }

        /* Keep the sidebar highlight on whatever page is actually visible — the
         * single source of truth, so the two can never desync. */
        private void sync_to_visible_page () {
            var page = content_nav.visible_page;
            if (page == null) {
                return;
            }
            select_row_for_tag (nav_list, page.tag);
            select_row_for_tag (more_list, page.tag);
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
