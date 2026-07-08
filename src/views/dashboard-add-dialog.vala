/* dashboard-add-dialog.vala
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

    /* The add-widget picker: registry widgets not already placed, filtered to
     * what this school's provider can fill. Emits widget_chosen(type_id). */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/dashboard-add-dialog.ui")]
    public class DashboardAddDialog : Adw.Dialog {

        [GtkChild] private unowned Gtk.Stack stack;
        [GtkChild] private unowned Adw.PreferencesGroup group;

        public signal void widget_chosen (string type_id);

        public DashboardAddDialog (Session session, GLib.GenericArray<string> taken) {
            var all = DashboardWidgetRegistry.get_default ().all ();
            int shown = 0;
            for (uint i = 0; i < all.length; i++) {
                var info = all[i];
                if (!session.provider.supports (info.required_capability)) {
                    continue;
                }
                if (has_id (taken, info.type_id)) {
                    continue;   // one of each type for now
                }
                var row = new Adw.ActionRow () {
                    title = info.title,
                    activatable = true
                };
                row.add_prefix (new Image.from_icon_name (info.icon_name));
                row.add_suffix (new Image.from_icon_name ("go-next-symbolic"));
                string id = info.type_id;
                row.activated.connect (() => {
                    widget_chosen (id);
                    close ();
                });
                group.add (row);
                shown++;
            }
            stack.visible_child_name = shown > 0 ? "list" : "empty";
        }

        private static bool has_id (GLib.GenericArray<string> arr, string needle) {
            for (uint i = 0; i < arr.length; i++) {
                if (arr[i] == needle) {
                    return true;
                }
            }
            return false;
        }
    }
}
