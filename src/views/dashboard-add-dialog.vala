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
     * what this school's provider can fill. Selecting one shows a live preview
     * (a real, bound tile) with a separate "Add" button; confirm emits
     * widget_chosen(type_id). */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/dashboard-add-dialog.ui")]
    public class DashboardAddDialog : Adw.Dialog {

        [GtkChild] private unowned Adw.NavigationView nav;
        [GtkChild] private unowned Gtk.Stack stack;
        [GtkChild] private unowned Adw.PreferencesGroup group;
        [GtkChild] private unowned Adw.Bin preview_slot;
        [GtkChild] private unowned Button add_confirm;

        public signal void widget_chosen (string type_id);

        private Session session;
        private string? pending = null;
        private DashboardTile? preview_tile = null;

        public DashboardAddDialog (Session session, GLib.GenericArray<string> taken) {
            this.session = session;

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
                row.activated.connect (() => show_preview (id));
                group.add (row);
                shown++;
            }
            stack.visible_child_name = shown > 0 ? "list" : "empty";

            add_confirm.clicked.connect (() => {
                if (pending != null) {
                    widget_chosen (pending);
                    close ();
                }
            });
            // Tear down the preview tile's session subscriptions on close.
            closed.connect (drop_preview);
        }

        private void show_preview (string type_id) {
            drop_preview ();
            preview_tile = build_preview (type_id);
            if (preview_tile == null) {
                return;
            }
            pending = type_id;
            preview_slot.child = preview_tile;
            nav.push_by_tag ("preview");
        }

        private void drop_preview () {
            if (preview_tile != null && preview_tile.controller != null) {
                preview_tile.controller.unbind ();
            }
            preview_tile = null;
        }

        /* A real, bound tile at the widget's default size, for the preview page.
         * NOTE: it binds to the live session; its signal subscriptions keep it
         * alive until the session ends — acceptable for a transient picker
         * (only the handful of widget types, opened occasionally). */
        private DashboardTile? build_preview (string type_id) {
            var registry = DashboardWidgetRegistry.get_default ();
            var info = registry.lookup (type_id);
            var controller = registry.create (type_id);
            if (info == null || controller == null) {
                return null;
            }
            var tile = new DashboardTile (new DashboardTileConfig (type_id, info.default_size)) {
                title = info.title,
                icon_name = info.icon_name,
                controller = controller,
                // A preview is look-only: skip the whole tile for pointer events
                // (so its buttons/rows can't open dialogs or navigate) while
                // still rendering live — unlike `sensitive = false`, which would
                // grey it out.
                can_target = false
            };
            tile.set_content (controller.build (tile));
            if (session.provider.supports (info.required_capability)) {
                controller.bind (session, tile);
            } else {
                tile.show_unavailable ();
            }
            return tile;
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
