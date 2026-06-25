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

    /* A centered spinner with a caption, for the "still loading" page of a Stack
     * while a slow endpoint streams in (lessons, attendance, absences). The
     * caller sets `label`; everything else is fixed so the loading states stay
     * visually consistent. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/loading-state.ui")]
    public class LoadingState : Adw.Bin {

        [GtkChild] private unowned Gtk.Label caption;

        /* The text shown under the spinner, e.g. "Loading absences…". */
        public string label { get; set; default = ""; }

        construct {
            bind_property ("label", caption, "label", BindingFlags.SYNC_CREATE);
        }
    }
}
