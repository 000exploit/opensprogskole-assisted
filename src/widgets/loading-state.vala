/* loading-state.vala
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

namespace Opensprogskole {

    /* The "still loading" / "load failed" page of a Stack while a slow endpoint
     * streams in (lessons, attendance, absences, grades). Shows a spinner with
     * `label`; if `error` is set non-empty it flips to an error icon + that text
     * instead, so a failed load reads as an error rather than an endless spinner.
     * Clearing `error` (e.g. when a retry begins) returns it to the spinner. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/loading-state.ui")]
    public class LoadingState : Adw.Bin {

        [GtkChild] private unowned Gtk.Stack stack;
        [GtkChild] private unowned Gtk.Label caption;
        [GtkChild] private unowned Gtk.Label error_caption;

        /* The text shown under the spinner, e.g. "Loading absences…". */
        public string label { get; set; default = ""; }
        /* When non-empty, the widget shows this as an error instead of spinning. */
        public string error { get; set; default = ""; }

        construct {
            bind_property ("label", caption, "label", BindingFlags.SYNC_CREATE);
            bind_property ("error", error_caption, "label", BindingFlags.SYNC_CREATE);
            notify["error"].connect (update_mode);
            update_mode ();
        }

        private void update_mode () {
            stack.visible_child_name = error == "" ? "loading" : "error";
        }
    }
}
