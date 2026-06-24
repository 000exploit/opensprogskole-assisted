/* profile-page.vala
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

    /* The "Your information" page: read-only profile from GetUserInfo. The
     * profile picture is shown as initials — the backend's picture URLs are
     * empty in practice (true of the official app too), so no remote fetch. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/profile-page.ui")]
    public class ProfilePage : Adw.Bin {

        [GtkChild] private unowned Adw.Avatar avatar;
        [GtkChild] private unowned Label name_label;
        [GtkChild] private unowned Label sub_label;
        [GtkChild] private unowned Gtk.ListBox about_list;
        [GtkChild] private unowned Gtk.ListBox contact_list;

        private Session? session = null;

        public void bind (Session session) {
            this.session = session;
            session.updated.connect (reload);
            reload ();
        }

        private void reload () {
            if (session == null) {
                return;
            }

            string name = session.display_name;
            avatar.text = name;
            name_label.label = name;

            clear (about_list);
            clear (contact_list);

            var info = session.user_info;
            sub_label.label = info != null && info.department_name != ""
                ? info.department_name : session.school.name;

            if (info == null) {
                return;
            }

            add_row (about_list, info.full_name, _("Name"));
            string address = join_nonempty (" · ",
                info.address, "%s %s".printf (info.zip_code, info.city).strip ());
            add_row (about_list, address, _("Address"));

            add_row (contact_list,
                info.private_mobile_phone != "" ? info.private_mobile_phone : info.mobile_phone,
                _("Mobile"));
            add_row (contact_list,
                info.private_mail != "" ? info.private_mail : info.work_mail,
                _("Email"));
        }

        private void add_row (Gtk.ListBox list, string? value, string label) {
            if (value == null || value.strip () == "") {
                return;
            }
            list.append (new Adw.ActionRow () {
                title = value,
                subtitle = label
            });
        }

        private static string join_nonempty (string sep, string a, string b) {
            if (a.strip () == "") return b.strip ();
            if (b.strip () == "") return a.strip ();
            return a.strip () + sep + b.strip ();
        }

        private static void clear (Gtk.ListBox list) {
            Gtk.Widget? child;
            while ((child = list.get_first_child ()) != null) {
                list.remove (child);
            }
        }
    }
}
