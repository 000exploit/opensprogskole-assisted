/* error-details-dialog.vala
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

    /* Shows one ErrorDetails: the request summary as the dialog body, the raw
     * server response below it, and a Copy button putting the full report on
     * the clipboard. Opened from the window-level error toast's "Details". */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/error-details-dialog.ui")]
    public class ErrorDetailsDialog : Adw.AlertDialog {

        // How long the Copy button shows its "done" check before reverting.
        // There's no ToastOverlay in an AlertDialog, so the icon swap is the
        // whole feedback (and Copy must not close the dialog).
        private const uint COPY_FEEDBACK_MS = 1500;
        private const string COPY_ICON = "edit-copy-symbolic";
        private const string COPIED_ICON = "object-select-symbolic";

        [GtkChild] private unowned Label header_label;
        [GtkChild] private unowned Button copy_button;
        [GtkChild] private unowned Label body_label;

        private uint copy_feedback_source = 0;

        public ErrorDetailsDialog (ErrorDetails details) {
            Object ();
            // The toast already led with the friendly summary; here the
            // technical request line joins it (or stands alone).
            body = details.operation != ""
                ? "%s\n%s".printf (details.summary (), details.request_line ())
                : details.request_line ();
            header_label.label = details.timestamp.format ("%c");
            body_label.label = details.body != ""
                ? details.body : _("(empty response body)");

            copy_button.clicked.connect (() => {
                copy_button.get_clipboard ().set_text (details.to_clipboard_text ());
                copy_button.icon_name = COPIED_ICON;
                if (copy_feedback_source != 0) {
                    GLib.Source.remove (copy_feedback_source);
                }
                copy_feedback_source = GLib.Timeout.add (COPY_FEEDBACK_MS, () => {
                    copy_button.icon_name = COPY_ICON;
                    copy_feedback_source = 0;
                    return GLib.Source.REMOVE;
                });
            });
        }
    }
}
