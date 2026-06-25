/* edit-profile-page.vala
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

    /* The pushed "Edit information" page: an entry per editable contact field
     * (only those GetUserInfoSettings permits). Save writes the edited values
     * back into the session's user_info and POSTs them; on success it emits
     * done() so the shell can pop back to the profile. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/edit-profile-page.ui")]
    public class EditProfilePage : Adw.NavigationPage {

        [GtkChild] private unowned Button save_button;
        [GtkChild] private unowned Adw.Spinner spinner;
        [GtkChild] private unowned Adw.Banner error_banner;
        [GtkChild] private unowned Adw.EntryRow phone_row;
        [GtkChild] private unowned Adw.EntryRow private_mobile_row;
        [GtkChild] private unowned Adw.EntryRow work_phone_row;
        [GtkChild] private unowned Adw.EntryRow work_mobile_row;
        [GtkChild] private unowned Adw.EntryRow private_mail_row;
        [GtkChild] private unowned Adw.EntryRow work_mail_row;
        [GtkChild] private unowned Adw.PreferencesGroup other_group;
        [GtkChild] private unowned Adw.EntryRow other_info_row;

        /* Saved successfully — the shell should pop this page. */
        public signal void done ();

        private Session session;

        public EditProfilePage (Session session) {
            Object ();
            this.session = session;

            var info = session.user_info;
            var s = session.user_settings;
            if (info != null && s != null) {
                init_row (phone_row, s.phone_number_allow_edit, info.phone_number);
                init_row (private_mobile_row, s.private_mobile_phone_allow_edit, info.private_mobile_phone);
                init_row (work_phone_row, s.work_phone_allow_edit, info.work_phone_number);
                init_row (work_mobile_row, s.work_mobile_phone_allow_edit, info.work_mobile_phone);
                init_row (private_mail_row, s.private_mail_allow_edit, info.private_mail);
                init_row (work_mail_row, s.work_mail_allow_edit, info.work_mail);

                other_group.visible = s.other_info_allow_edit;
                init_row (other_info_row, s.other_info_allow_edit, info.other_info);
            }

            save_button.clicked.connect (on_save);
        }

        private static void init_row (Adw.EntryRow row, bool allowed, string? value) {
            row.visible = allowed;
            if (allowed) {
                row.text = value ?? "";
            }
        }

        private void on_save () {
            var info = session.user_info;
            if (info == null) {
                return;
            }

            // Only the visible (editable) rows write back.
            if (phone_row.visible) info.phone_number = phone_row.text;
            if (private_mobile_row.visible) info.private_mobile_phone = private_mobile_row.text;
            if (work_phone_row.visible) info.work_phone_number = work_phone_row.text;
            if (work_mobile_row.visible) info.work_mobile_phone = work_mobile_row.text;
            if (private_mail_row.visible) info.private_mail = private_mail_row.text;
            if (work_mail_row.visible) info.work_mail = work_mail_row.text;
            if (other_info_row.visible) info.other_info = other_info_row.text;

            set_busy (true);
            error_banner.revealed = false;
            session.save_user_info.begin ((obj, res) => {
                try {
                    session.save_user_info.end (res);
                    done ();
                } catch (GLib.Error e) {
                    warning ("profile save failed: %s", e.message);
                    set_busy (false);
                    error_banner.title = _("Couldn't save your changes. Please try again.");
                    error_banner.revealed = true;
                }
            });
        }

        private void set_busy (bool busy) {
            spinner.visible = busy;
            save_button.sensitive = !busy;
        }
    }
}
