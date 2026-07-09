/* dashboard-view.vala
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

    /* The modular overview. An ordered ListStore of DashboardTileConfig is the
     * source of truth (persisted per account via session.storage); the WrapBox
     * is a pure projection rebuilt from it. Add/remove/reorder mutate the model,
     * rebuild, and persist. Replaces the old static OverviewPage; keeps its
     * three signals so main-view.vala is unchanged. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/dashboard-view.ui")]
    public class DashboardView : Adw.Bin {

        private const string LAYOUT_KEY = "dashboard-layout";
        private const int LAYOUT_VERSION = 1;

        [GtkChild] private unowned Label greeting;
        [GtkChild] private unowned Label subtitle;
        [GtkChild] private unowned Button report_button;
        [GtkChild] private unowned Button report_button_mobile;
        [GtkChild] private unowned Button add_button;
        [GtkChild] private unowned ToggleButton edit_button;
        [GtkChild] private unowned Adw.WrapBox tiles;
        [GtkChild] private unowned Adw.StatusPage empty_page;

        public signal void report_absence_requested ();
        // A tile asked to open a core section ("schedule", "grades",
        // "absence", ...); main-view switches to it.
        public signal void section_requested (string tag);

        private Session? session = null;

        // Source of truth + a widget cache so reorders reuse tiles (no rebind /
        // refetch / flicker). Keyed by config object identity.
        private GLib.ListStore layout = new GLib.ListStore (typeof (DashboardTileConfig));
        private GLib.HashTable<DashboardTileConfig, DashboardTile> tiles_by_config =
            new GLib.HashTable<DashboardTileConfig, DashboardTile> (direct_hash, direct_equal);

        private bool editing = false;

        construct {
            report_button.clicked.connect (() => report_absence_requested ());
            report_button_mobile.clicked.connect (() => report_absence_requested ());
            Connectivity.get_default ().bind_writable (report_button);
            Connectivity.get_default ().bind_writable (report_button_mobile);

            edit_button.toggled.connect (() => set_editing (edit_button.active));
            add_button.clicked.connect (present_add_dialog);
            add_button.visible = false;

            // Long-press anywhere on the tiles enters edit mode (touch-friendly).
            var long_press = new Gtk.GestureLongPress ();
            long_press.pressed.connect (() => {
                if (!editing) {
                    edit_button.active = true;
                }
            });
            tiles.add_controller (long_press);
            // The narrow-width header/spacing adjustments live in the Blueprint
            // (an Adw.Breakpoint on breakpoint_bin) — no responsive code here.
        }

        public void bind (Session session) {
            this.session = session;
            session.updated.connect (update_header);
            update_header ();

            var node = session.storage.get_json (LAYOUT_KEY);
            var configs = node != null ? parse_configs (node) : default_configs ();
            apply_configs (configs);
        }

        // --- Header -------------------------------------------------------------

        private void update_header () {
            if (session == null) {
                return;
            }
            var now = new DateTime.now_local ();
            string first = session.display_name.split (" ")[0];
            greeting.label = greeting_for (now.get_hour ()).printf (first);
            subtitle.label = "%s · %s".printf (
                now.format ("%A, %-d %B %Y"), session.school.name);
        }

        /* Boundaries: night < 5 ≤ morning < 12 ≤ afternoon < 18 ≤ evening. */
        private static string greeting_for (int hour) {
            if (hour < 5) {
                return _("Good night, %s");
            }
            if (hour < 12) {
                return _("Good morning, %s");
            }
            if (hour < 18) {
                return _("Good afternoon, %s");
            }
            return _("Good evening, %s");
        }

        // --- Model → view -------------------------------------------------------

        /* Replace the whole layout (initial load / reset). Clears the cache so
         * stale tiles are dropped; does NOT persist (the caller decides). */
        private void apply_configs (GLib.GenericArray<DashboardTileConfig> configs) {
            layout.remove_all ();
            tiles_by_config.remove_all ();
            for (uint i = 0; i < configs.length; i++) {
                layout.append (configs[i]);
            }
            rebuild_from_model ();
        }

        /* The only place the WrapBox structure is written. Reuses cached tiles;
         * builds+binds a tile the first time its config appears. */
        private void rebuild_from_model () {
            tiles.remove_all ();
            uint n = layout.get_n_items ();
            empty_page.visible = n == 0;
            tiles.visible = n > 0;

            for (uint i = 0; i < n; i++) {
                var cfg = (DashboardTileConfig) layout.get_item (i);
                var tile = tiles_by_config.lookup (cfg);
                if (tile == null) {
                    tile = make_tile (cfg);
                    if (tile == null) {
                        continue;   // unknown type_id in a saved layout — skip
                    }
                    tiles_by_config.insert (cfg, tile);
                }
                tile.edit_mode = editing;
                tiles.append (tile);
            }
            prune_cache ();
        }

        /* Drop cached tiles whose config is no longer in the layout (removed),
         * finalizing the widget. */
        private void prune_cache () {
            var stale = new GLib.GenericArray<DashboardTileConfig> ();
            tiles_by_config.foreach ((cfg, tile) => {
                if (!layout_contains (cfg)) {
                    stale.add (cfg);
                }
            });
            for (uint i = 0; i < stale.length; i++) {
                tiles_by_config.remove (stale[i]);
            }
        }

        private bool layout_contains (DashboardTileConfig cfg) {
            uint pos;
            return layout.find (cfg, out pos);
        }

        private DashboardTile? make_tile (DashboardTileConfig cfg) {
            var registry = DashboardWidgetRegistry.get_default ();
            var info = registry.lookup (cfg.type_id);
            if (info == null) {
                return null;
            }
            var controller = registry.create (cfg.type_id);
            if (controller == null) {
                return null;
            }
            var tile = new DashboardTile (cfg) {
                title = info.title,
                icon_name = info.icon_name,
                controller = controller,
                can_resize = info.sizes.length > 1
            };
            tile.set_content (controller.build (tile));
            if (session.provider.supports (info.required_capability)) {
                controller.bind (session, tile);
            } else {
                tile.show_unavailable ();
            }
            tile.remove_requested.connect (() => remove_config (cfg));
            tile.size_change_requested.connect (() => resize_tile (cfg));
            controller.navigate.connect ((section) => section_requested (section));
            wire_dnd (tile);
            return tile;
        }

        // --- Add / remove / reorder --------------------------------------------

        private void add_widget (string type_id) {
            var info = DashboardWidgetRegistry.get_default ().lookup (type_id);
            if (info == null) {
                return;
            }
            var cfg = new DashboardTileConfig (type_id, info.default_size);
            layout.append (cfg);
            rebuild_from_model ();
            persist ();
            var tile = tiles_by_config.lookup (cfg);
            if (tile != null) {
                pop_in (tile);
            }
        }

        private void remove_config (DashboardTileConfig cfg) {
            var tile = tiles_by_config.lookup (cfg);
            if (tile == null) {
                do_remove (cfg);
                return;
            }
            var target = new Adw.CallbackAnimationTarget ((v) => {
                tile.opacity = v;
                tile.scale = 0.9 + 0.1 * v;
            });
            var fade = new Adw.TimedAnimation (tile, 1.0, 0.0, 150, target);
            fade.done.connect (() => do_remove (cfg));
            fade.play ();
        }

        /* Cycle the tile to its widget's next supported size: update the config,
         * re-apply the width class, rebuild the presenter for the new size
         * (relayout, no re-subscribe), persist, and settle. */
        private void resize_tile (DashboardTileConfig cfg) {
            var info = DashboardWidgetRegistry.get_default ().lookup (cfg.type_id);
            var tile = tiles_by_config.lookup (cfg);
            if (info == null || tile == null) {
                return;
            }
            cfg.size = info.next_size (cfg.size);
            tile.apply_size_class ();
            if (tile.controller != null) {
                tile.controller.relayout (tile);
            }
            persist ();
            pop_in (tile);
        }

        private void do_remove (DashboardTileConfig cfg) {
            uint pos;
            if (layout.find (cfg, out pos)) {
                layout.remove (pos);
            }
            rebuild_from_model ();
            persist ();
        }

        /* Move `moved` so it lands at `target` (an index in the pre-removal
         * model). Reuses the cached widget, so no refetch. */
        private bool reorder (DashboardTileConfig moved, uint target) {
            uint from;
            if (!layout.find (moved, out from)) {
                return false;
            }
            layout.remove (from);
            uint insert_at = target > from ? target - 1 : target;
            if (insert_at > layout.get_n_items ()) {
                insert_at = layout.get_n_items ();
            }
            layout.insert (insert_at, moved);
            rebuild_from_model ();
            persist ();
            var tile = tiles_by_config.lookup (moved);
            if (tile != null) {
                pop_in (tile);
            }
            return true;
        }

        // --- Drag and drop ------------------------------------------------------

        private void wire_dnd (DashboardTile tile) {
            var src = new Gtk.DragSource () { actions = Gdk.DragAction.MOVE };
            src.prepare.connect ((x, y) => {
                if (!editing) {
                    return null;
                }
                tile.drag_hotspot_x = (int) x;
                tile.drag_hotspot_y = (int) y;
                var v = Value (typeof (DashboardTileConfig));
                v.set_object (tile.config);
                return new Gdk.ContentProvider.for_value (v);
            });
            src.drag_begin.connect ((drag) => {
                var paintable = new Gtk.WidgetPaintable (tile);
                src.set_icon (paintable, tile.drag_hotspot_x, tile.drag_hotspot_y);
                tile.add_css_class ("dragging");
            });
            src.drag_end.connect (() => tile.remove_css_class ("dragging"));
            tile.add_controller (src);

            var dst = new Gtk.DropTarget (typeof (DashboardTileConfig), Gdk.DragAction.MOVE);
            dst.drop.connect ((v, x, y) => {
                var moved = v.get_object () as DashboardTileConfig;
                if (moved == null) {
                    return false;
                }
                uint idx;
                if (!layout.find (tile.config, out idx)) {
                    return false;
                }
                // Drop on the right half → after this tile, else before it.
                uint target = idx + (x > tile.get_width () / 2 ? 1 : 0);
                return reorder (moved, target);
            });
            tile.add_controller (dst);
        }

        // --- Edit mode ----------------------------------------------------------

        private void set_editing (bool on) {
            editing = on;
            add_button.visible = on;
            if (edit_button.active != on) {
                edit_button.active = on;
            }
            tiles_by_config.foreach ((cfg, tile) => tile.edit_mode = on);
        }

        private void present_add_dialog () {
            if (session == null) {
                return;
            }
            var dialog = new DashboardAddDialog (session, taken_type_ids ());
            dialog.widget_chosen.connect (add_widget);
            dialog.present (this);
        }

        private GLib.GenericArray<string> taken_type_ids () {
            var ids = new GLib.GenericArray<string> ();
            for (uint i = 0; i < layout.get_n_items (); i++) {
                ids.add (((DashboardTileConfig) layout.get_item (i)).type_id);
            }
            return ids;
        }

        // --- Persistence --------------------------------------------------------

        private void persist () {
            if (session == null) {
                return;
            }
            session.storage.set_json (LAYOUT_KEY, serialize ());
        }

        private Json.Node serialize () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("version");
            b.add_int_value (LAYOUT_VERSION);
            b.set_member_name ("tiles");
            b.begin_array ();
            for (uint i = 0; i < layout.get_n_items (); i++) {
                var cfg = (DashboardTileConfig) layout.get_item (i);
                b.begin_object ();
                b.set_member_name ("type");
                b.add_string_value (cfg.type_id);
                b.set_member_name ("size");
                b.add_string_value (size_to_string (cfg.size));
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
            return b.get_root ();
        }

        private GLib.GenericArray<DashboardTileConfig> parse_configs (Json.Node node) {
            var result = new GLib.GenericArray<DashboardTileConfig> ();
            if (node.get_node_type () != Json.NodeType.OBJECT) {
                return result;
            }
            var obj = node.get_object ();
            if (!obj.has_member ("tiles")) {
                return result;
            }
            var registry = DashboardWidgetRegistry.get_default ();
            obj.get_array_member ("tiles").foreach_element ((arr, i, element) => {
                if (element.get_node_type () != Json.NodeType.OBJECT) {
                    return;
                }
                var t = element.get_object ();
                string type_id = t.get_string_member_with_default ("type", "");
                // Skip unknown widget types (forward compatibility).
                if (type_id == "" || registry.lookup (type_id) == null) {
                    return;
                }
                var size = size_from_string (t.get_string_member_with_default ("size", "full"));
                result.add (new DashboardTileConfig (type_id, size));
            });
            return result;
        }

        /* The starter layout: the provider's suggested widgets (the rest are
         * opt-in via Add), each dropped if the provider can't actually fill it
         * — so a limited backend (LUDUS) gets an empty dashboard + prompt
         * rather than a wall of unavailable cards. */
        private GLib.GenericArray<DashboardTileConfig> default_configs () {
            var result = new GLib.GenericArray<DashboardTileConfig> ();
            var registry = DashboardWidgetRegistry.get_default ();
            foreach (string type_id in session.provider.default_widget_ids ()) {
                var info = registry.lookup (type_id);
                if (info != null && session.provider.supports (info.required_capability)) {
                    result.add (new DashboardTileConfig (type_id, info.default_size));
                }
            }
            return result;
        }

        private static string size_to_string (WidgetSize s) {
            switch (s) {
                case WidgetSize.MINI: return "mini";
                case WidgetSize.HALF: return "half";
                default:              return "full";
            }
        }

        private static WidgetSize size_from_string (string s) {
            switch (s) {
                case "mini": return WidgetSize.MINI;
                case "half": return WidgetSize.HALF;
                default:     return WidgetSize.FULL;
            }
        }

        // --- Animation ----------------------------------------------------------

        /* A subtle spring "pop" as a tile settles after being added or moved. */
        private void pop_in (DashboardTile tile) {
            tile.opacity = 1.0;
            var target = new Adw.CallbackAnimationTarget ((v) => {
                tile.scale = v;
            });
            var spring = new Adw.SpringAnimation (tile, 0.92, 1.0,
                new Adw.SpringParams (0.72, 1.0, 220.0), target);
            spring.epsilon = 0.001;
            spring.play ();
        }
    }
}
