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

    /* The "Your information" page: the profile from GetUserInfo, plus the quick
     * settings the school allows (GetUserInfoSettings). Read-only details live in
     * the About/Contact groups; the SMS preference and picture visibility are
     * interactive rows that save immediately. Editing the contact text fields
     * happens on a separate pushed page (see edit_requested). */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/profile-page.ui")]
    public class ProfilePage : Adw.Bin {

        [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
        [GtkChild] private unowned Adw.Avatar avatar;
        [GtkChild] private unowned Button avatar_edit_button;
        [GtkChild] private unowned Label name_label;
        [GtkChild] private unowned Label sub_label;
        [GtkChild] private unowned Adw.Banner error_banner;
        [GtkChild] private unowned Adw.Banner pending_banner;
        [GtkChild] private unowned Adw.PreferencesGroup about_group;
        [GtkChild] private unowned Adw.PreferencesGroup contact_group;
        [GtkChild] private unowned Adw.PreferencesGroup prefs_group;
        [GtkChild] private unowned Adw.SwitchRow sms_row;
        [GtkChild] private unowned MenuButton sms_warning_button;
        [GtkChild] private unowned Adw.ComboRow privacy_row;
        [GtkChild] private unowned Button edit_button;

        /* The user asked to edit the contact text fields. */
        public signal void edit_requested ();

        private Session? session = null;
        // True while reload() pushes server state into the rows, so the row
        // change handlers don't mistake it for a user edit and save it back.
        private bool syncing = false;
        // Rows currently shown in the dynamic groups, with their owning group, so
        // they can be removed on reload.
        private GLib.GenericArray<Adw.PreferencesRow> dynamic_rows
            = new GLib.GenericArray<Adw.PreferencesRow> ();
        private GLib.GenericArray<unowned Adw.PreferencesGroup> dynamic_groups
            = new GLib.GenericArray<unowned Adw.PreferencesGroup> ();

        construct {
            privacy_row.model = new Gtk.StringList ({
                _("Everyone"), _("School only"), _("Nobody")
            });
            edit_button.clicked.connect (() => edit_requested ());
            avatar_edit_button.clicked.connect (on_change_photo);
            pending_banner.button_clicked.connect (() => remove_pending.begin ());
            sms_row.notify["active"].connect (on_sms_toggled);
            privacy_row.notify["selected"].connect (on_privacy_changed);
        }

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
            load_avatar.begin ();

            var info = session.user_info;
            sub_label.label = info != null && info.department_name != ""
                ? info.department_name : session.school.name;

            clear_dynamic_rows ();
            if (info != null) {
                fill_about (info);
                fill_contact (info);
            }
            sync_settings ();
        }

        // --- Read-only sections ---------------------------------------------

        private void fill_about (UserInfoItem info) {
            add_row (about_group, _("Name"), info.full_name);
            add_row (about_group, _("Date of birth"), format_birthday (info.birth_day));
            add_row (about_group, _("Address"), join_nonempty (" · ",
                info.address, "%s %s".printf (info.zip_code, info.city).strip ()));
            add_row (about_group, _("Department"), info.department_name);
            add_row (about_group, _("Course length"),
                format_period (info.start_date_time, info.end_date_time));
            add_row (about_group, _("Card number"), info.card_id);
        }

        private void fill_contact (UserInfoItem info) {
            add_row (contact_group, _("Phone"), info.phone_number);
            add_row (contact_group, _("Mobile"), info.private_mobile_phone);
            add_row (contact_group, _("Work phone"), info.work_phone_number);
            add_row (contact_group, _("Work mobile"), info.work_mobile_phone);
            add_row (contact_group, _("Email"), info.private_mail);
            add_row (contact_group, _("Work email"), info.work_mail);
        }

        /* Append a titled row, skipping empty values (which arrive as "" or null). */
        private void add_row (Adw.PreferencesGroup group, string label, string? value) {
            if (value == null || value.strip () == "") {
                return;
            }
            // ".property" renders the title as a small dimmed caption above the
            // prominent value, matching the GNOME "About" rows.
            var row = new Adw.ActionRow () {
                title = label,
                subtitle = value,
                subtitle_selectable = true
            };
            row.add_css_class ("property");

            var copy = new Button () {
                icon_name = "edit-copy-symbolic",
                valign = Align.CENTER,
                tooltip_text = _("Copy")
            };
            copy.add_css_class ("flat");
            copy.clicked.connect (() => {
                copy.get_clipboard ().set_text (value);
                toast (_("Copied to clipboard"));
            });
            row.add_suffix (copy);

            group.add (row);
            dynamic_rows.add (row);
            dynamic_groups.add (group);
        }

        private void clear_dynamic_rows () {
            for (uint i = 0; i < dynamic_rows.length; i++) {
                dynamic_groups[i].remove (dynamic_rows[i]);
            }
            dynamic_rows.remove_range (0, dynamic_rows.length);
            dynamic_groups.remove_range (0, dynamic_groups.length);
        }

        // --- Interactive settings -------------------------------------------

        /* Mirror the live user_info/user_settings into the setting rows without
         * triggering their change handlers. */
        private void sync_settings () {
            var info = session.user_info;
            var s = session.user_settings;

            syncing = true;

            bool sms_editable = info != null && s != null && s.never_receive_sms_allow_edit;
            sms_row.visible = sms_editable;
            if (sms_editable) {
                sms_row.active = !info.never_receive_sms;
            }
            sms_warning_button.visible = sms_editable && info.never_receive_sms;

            bool privacy_editable = info != null && s != null
                && s.picture_privacy_setting_allow_edit;
            privacy_row.visible = privacy_editable;
            if (privacy_editable) {
                privacy_row.selected = clamp_privacy (info.picture_privacy_setting);
            }

            prefs_group.visible = sms_editable || privacy_editable;
            edit_button.visible = s != null && s.any_editable;

            // Picture upload / pending removal, gated by the selfie permission.
            bool selfie = s != null && s.selfie_enabled;
            avatar_edit_button.visible = selfie;
            pending_banner.revealed = selfie && info != null
                && info.pending_picture_url.strip () != "";

            syncing = false;
        }

        private void on_sms_toggled () {
            var info = session != null ? session.user_info : null;
            if (syncing || info == null) {
                return;
            }
            bool old = info.never_receive_sms;
            bool want_never = !sms_row.active;
            if (want_never == old) {
                return;
            }
            info.never_receive_sms = want_never;
            sms_warning_button.visible = want_never;
            if (want_never) {
                toast (_("SMS reminders are off — you may miss reminders."));
            }
            persist (() => { info.never_receive_sms = old; });
        }

        private void on_privacy_changed () {
            var info = session != null ? session.user_info : null;
            if (syncing || info == null) {
                return;
            }
            int old = info.picture_privacy_setting;
            int want = (int) privacy_row.selected;
            if (want == old) {
                return;
            }
            info.picture_privacy_setting = want;
            persist (() => { info.picture_privacy_setting = old; });
        }

        /* Save the (already mutated) user_info; on failure run `revert` to undo
         * the in-memory change, re-sync the rows and surface the error. */
        private void persist (owned RevertAction revert) {
            error_banner.revealed = false;
            session.save_user_info.begin ((obj, res) => {
                try {
                    session.save_user_info.end (res);
                } catch (GLib.Error e) {
                    warning ("save user info failed: %s", e.message);
                    revert ();
                    sync_settings ();
                    error_banner.title = _("Couldn't save your change. Please try again.");
                    error_banner.revealed = true;
                }
            });
        }

        // Undoes an in-memory setting change when its save failed.
        private delegate void RevertAction ();

        private async void load_avatar () {
            if (session == null) {
                return;
            }
            // Setting null reverts to initials (e.g. after removing a pending
            // photo), so assign unconditionally.
            avatar.custom_image = yield session.load_avatar ();
        }

        private void toast (string text) {
            toast_overlay.add_toast (new Adw.Toast (text));
        }

        // --- Profile picture -------------------------------------------------

        private void on_change_photo () {
            var dialog = new Gtk.FileDialog () {
                title = _("Choose a profile photo")
            };
            var filter = new Gtk.FileFilter () { name = _("Images") };
            filter.add_pixbuf_formats ();
            var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
            filters.append (filter);
            dialog.filters = filters;
            dialog.default_filter = filter;

            dialog.open.begin (get_root () as Gtk.Window, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file != null) {
                        upload_photo.begin (file);
                    }
                } catch (GLib.Error e) {
                    // Dialog dismissed/cancelled — nothing to do.
                }
            });
        }

        private async void upload_photo (GLib.File file) {
            if (session == null) {
                return;
            }
            avatar_edit_button.sensitive = false;
            try {
                string etag;
                var bytes = yield file.load_bytes_async (null, out etag);
                yield session.upload_avatar (bytes);
                toast (_("Photo uploaded — awaiting approval"));
            } catch (GLib.Error e) {
                warning ("avatar upload failed: %s", e.message);
                toast (_("Couldn't upload the photo. Please try again."));
            }
            avatar_edit_button.sensitive = true;
        }

        private async void remove_pending () {
            if (session == null) {
                return;
            }
            try {
                yield session.remove_pending_avatar ();
                toast (_("Pending photo removed"));
            } catch (GLib.Error e) {
                warning ("remove pending avatar failed: %s", e.message);
                toast (_("Couldn't remove the photo. Please try again."));
            }
        }

        // --- Formatting helpers ---------------------------------------------

        private static uint clamp_privacy (int value) {
            return (uint) (value < 0 ? 0 : (value > 2 ? 2 : value));
        }

        /* "ddMMyy" (e.g. "241089") -> "24.10.89"; passed through otherwise. */
        private static string format_birthday (string raw) {
            if (raw.length != 6) {
                return raw;
            }
            return "%s.%s.%s".printf (raw.substring (0, 2),
                                      raw.substring (2, 2), raw.substring (4, 2));
        }

        private static string format_period (DateTime? start, DateTime? end) {
            if (start == null || end == null) {
                return "";
            }
            return "%s – %s".printf (start.format ("%-d %b %Y"), end.format ("%-d %b %Y"));
        }

        private static string join_nonempty (string sep, string a, string b) {
            if (a.strip () == "") return b.strip ();
            if (b.strip () == "") return a.strip ();
            return a.strip () + sep + b.strip ();
        }
    }
}
