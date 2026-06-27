/* reason-dialog.vala
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

    /* A tiny, reusable "enter a reason" prompt. It's pure UI: it validates the
     * field is non-empty and emits submitted(reason); the caller (which owns the
     * Session) performs the network call and then drives set_busy()/toast()/close()
     * on this dialog. Used to describe a past absence and to call in sick. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/reason-dialog.ui")]
    public class ReasonDialog : Adw.Dialog {

        [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
        [GtkChild] private unowned Label hint_label;
        [GtkChild] private unowned Adw.EntryRow reason_row;
        [GtkChild] private unowned Adw.Spinner spinner;
        [GtkChild] private unowned Button submit_button;

        /* The user confirmed a non-empty reason. */
        public signal void submitted (string reason);

        public ReasonDialog (string title, string hint, string initial,
                             string submit_label) {
            Object ();
            this.title = title;
            if (hint != "") {
                hint_label.label = hint;
                hint_label.visible = true;
            }
            reason_row.text = initial;
            submit_button.label = submit_label;
        }

        construct {
            submit_button.clicked.connect (() => {
                string reason = reason_row.text.strip ();
                if (reason == "") {
                    toast (_("Please enter a reason."));
                    return;
                }
                submitted (reason);
            });
            reason_row.entry_activated.connect (() => submit_button.activate ());
        }

        /* Toggle the in-flight state while the caller does its network call. */
        public void set_busy (bool busy) {
            spinner.visible = busy;
            submit_button.sensitive = !busy;
            reason_row.sensitive = !busy;
        }

        public void toast (string text) {
            toast_overlay.add_toast (new Adw.Toast (text));
        }
    }
}
