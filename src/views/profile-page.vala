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
        [GtkChild] private unowned Adw.Banner pending_banner;
        [GtkChild] private unowned Adw.PreferencesGroup about_group;
        [GtkChild] private unowned Adw.PreferencesGroup contact_group;
        [GtkChild] private unowned Adw.PreferencesGroup prefs_group;
        [GtkChild] private unowned Adw.SwitchRow sms_row;
        [GtkChild] private unowned MenuButton sms_warning_button;
        [GtkChild] private unowned Adw.ComboRow privacy_row;
        [GtkChild] private unowned Gtk.Box sync_dot;
        [GtkChild] private unowned Label sync_label;
        [GtkChild] private unowned Button edit_button;

        // True while an account setting is being saved. A property, so its notify
        // drives the status dot — set it and the UI follows, no manual refresh.
        private bool saving { get; set; default = false; }

        /* The user asked to edit the contact text fields. */
        public signal void edit_requested ();

        private Session? session = null;
        // True while reload() pushes server state into the rows, so the row
        // change handlers don't mistake it for a user edit and save it back.
        private bool syncing = false;
        // True while a picture upload is in flight (keeps the avatar button off).
        private bool uploading = false;
        // Rows currently shown in the dynamic groups, with their owning group, so
        // they can be removed on reload.
        private GLib.GenericArray<Adw.PreferencesRow> dynamic_rows
            = new GLib.GenericArray<Adw.PreferencesRow> ();
        private GLib.GenericArray<unowned Adw.PreferencesGroup> dynamic_groups
            = new GLib.GenericArray<unowned Adw.PreferencesGroup> ();

        construct {
            privacy_row.model = new Gtk.StringList ({
                _("Everyone"), _("School only"), _("No one")
            });
            edit_button.clicked.connect (() => edit_requested ());
            avatar_edit_button.clicked.connect (on_change_photo);
            pending_banner.button_clicked.connect (() => remove_pending.begin ());
            sms_row.notify["active"].connect (on_sms_toggled);
            privacy_row.notify["selected"].connect (on_privacy_changed);

            // These are all writes: disable them while offline. The avatar button
            // also toggles its own sensitivity during an upload, so it folds
            // `online` in by hand instead of a plain bind (see update_avatar_button).
            var conn = Connectivity.get_default ();
            conn.bind_writable (edit_button);
            conn.bind_writable (pending_banner);
            conn.notify["online"].connect (update_avatar_button);
            // sms_row/privacy_row sensitivity folds in BOTH connectivity and the
            // per-field allow-edit flag (school-managed), so it's recomputed in
            // sync_settings rather than a plain bind.
            conn.notify["online"].connect (() => {
                if (session != null) {
                    sync_settings ();
                }
            });
            // The status dot is signal-driven: re-renders whenever the saving
            // state or connectivity changes.
            notify["saving"].connect (update_sync_status);
            conn.notify["online"].connect (update_sync_status);
            update_sync_status ();
            update_avatar_button ();
        }

        private void update_avatar_button () {
            avatar_edit_button.sensitive =
                !uploading && Connectivity.get_default ().online;
        }

        public void bind (Session session) {
            this.session = session;
            session.updated.connect (reload);
            reload ();
        }

        /* The sync-status dot + label in the Account group header: yellow while
         * saving, red offline, green (synced) otherwise. */
        private void update_sync_status () {
            sync_dot.remove_css_class ("online");
            sync_dot.remove_css_class ("saving");
            sync_dot.remove_css_class ("offline");
            if (saving) {
                sync_dot.add_css_class ("saving");
                sync_label.label = _("Saving…");
            } else if (!Connectivity.get_default ().online) {
                sync_dot.add_css_class ("offline");
                sync_label.label = _("Offline");
            } else {
                sync_dot.add_css_class ("online");
                sync_label.label = _("Synced");
            }
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

            bool have = info != null && s != null;
            bool online = Connectivity.get_default ().online;

            // School-managed (allow-edit false) rows stay visible but disabled,
            // with a "Managed by your school" subtitle, rather than vanishing.
            bool sms_editable = have && s.never_receive_sms_allow_edit;
            sms_row.sensitive = sms_editable && online;
            sms_row.subtitle = sms_editable
                ? _("Reminders about lessons and absence, sent to your phone")
                : _("Managed by your school");
            if (have) {
                sms_row.active = !info.never_receive_sms;
            }
            sms_warning_button.visible = sms_editable && info.never_receive_sms;

            bool privacy_editable = have && s.picture_privacy_setting_allow_edit;
            privacy_row.sensitive = privacy_editable && online;
            privacy_row.subtitle = privacy_editable
                ? _("Who can see your photo")
                : _("Managed by your school");
            if (have) {
                privacy_row.selected = clamp_privacy (info.picture_privacy_setting);
            }

            prefs_group.visible = have;
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
         * the in-memory change, re-sync the rows and toast the error. */
        private void persist (owned RevertAction revert) {
            saving = true;   // notify::saving → the dot turns yellow
            session.save_user_info.begin ((obj, res) => {
                try {
                    session.save_user_info.end (res);
                } catch (GLib.Error e) {
                    warning ("save user info failed: %s", e.message);
                    revert ();
                    sync_settings ();
                    toast (_("Couldn't save your change — check your connection."));
                }
                saving = false;   // notify::saving → back to green/red
            });
        }

        // Undoes an in-memory setting change when its save failed.
        private delegate void RevertAction ();

        private async void load_avatar () {
            if (session == null) {
                return;
            }
            // Setting null reverts to initials (e.g. after removing a pending
            // photo), so assign unconditionally. May assign twice: the cached
            // picture at once, the revalidated one when it differs.
            yield session.load_avatar ((paintable) => {
                avatar.custom_image = paintable;
            });
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
            uploading = true;
            update_avatar_button ();
            try {
                string etag;
                var bytes = yield file.load_bytes_async (null, out etag);
                yield session.upload_avatar (bytes);
                toast (_("Photo uploaded — awaiting approval"));
            } catch (GLib.Error e) {
                warning ("avatar upload failed: %s", e.message);
                toast (_("Couldn't upload the photo — check your connection."));
            }
            uploading = false;
            update_avatar_button ();
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
