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
        [GtkChild] private unowned Adw.Breakpoint narrow_bp;
        [GtkChild] private unowned Gtk.Grid tiles;
        [GtkChild] private unowned Adw.StatusPage empty_page;

        // Column units per row (grid width): a full tile spans all of them, a
        // half spans 2, a mini 1. Switched by width via a breakpoint.
        private const int UNITS_WIDE = 4;
        private const int UNITS_NARROW = 2;
        private int units_per_row = UNITS_WIDE;

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

            // Same narrow breakpoint as the Blueprint report/margin setters
            // (Adw applies only one breakpoint at a time, so they must share
            // one): drop the grid to 2 columns and repack.
            narrow_bp.apply.connect (() => set_units (UNITS_NARROW));
            narrow_bp.unapply.connect (() => set_units (UNITS_WIDE));
        }

        private void set_units (int units) {
            if (units_per_row == units) {
                return;
            }
            units_per_row = units;
            rebuild_from_model ();
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

        /* The only place the grid structure is written. Reuses cached tiles,
         * builds+binds a tile the first time its config appears, then packs
         * them into rows of `units_per_row` by span. The last tile of a partial
         * row is stretched to fill the remaining units (no trailing gap). */
        // Set true for one rebuild by a user action (reorder/resize/add/remove)
        // so surviving tiles slide (FLIP) to their new spots; false for the
        // initial load, where nothing should animate.
        private bool animate_reflow = false;

        private void rebuild_from_model () {
            // FLIP "First": record where the currently-placed tiles are, before
            // we tear the grid down.
            GLib.HashTable<DashboardTile, Graphene.Point?>? old_pos = null;
            if (animate_reflow) {
                old_pos = new GLib.HashTable<DashboardTile, Graphene.Point?> (
                    direct_hash, direct_equal);
                var origin = Graphene.Point ();
                origin.init (0, 0);
                tiles_by_config.foreach ((cfg, tile) => {
                    if (tile.get_parent () != tiles) {
                        return;
                    }
                    Graphene.Point p;
                    if (tile.compute_point (tiles, origin, out p)) {
                        old_pos.set (tile, p);
                    }
                });
            }

            clear_grid ();

            var packed = new GLib.GenericArray<DashboardTile> ();
            uint n = layout.get_n_items ();
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
                packed.add (tile);
            }

            empty_page.visible = packed.length == 0;
            tiles.visible = packed.length > 0;

            int row = 0;
            uint i = 0;
            while (i < packed.length) {
                // Greedily fill a row up to units_per_row.
                uint start = i;
                int used = 0;
                while (i < packed.length
                       && used + span_of (packed[i]) <= units_per_row) {
                    used += span_of (packed[i]);
                    i++;
                }
                if (i == start) {   // a single tile wider than a row (shouldn't happen)
                    i++;
                    used = units_per_row;
                }
                int leftover = units_per_row - used;
                int col = 0;
                for (uint j = start; j < i; j++) {
                    int span = span_of (packed[j]);
                    if (j == i - 1) {
                        span += leftover;   // last tile fills the row
                    }
                    packed[j].hexpand = true;
                    tiles.attach (packed[j], col, row, span, 1);
                    col += span;
                }
                row++;
            }
            prune_cache ();

            if (old_pos != null) {
                animate_reflow = false;
                schedule_flip (old_pos);
            }
        }

        /* FLIP "Last/Invert/Play": once the grid has re-laid-out (next idle),
         * for each surviving tile that moved, offset it back to its old spot and
         * spring the offset to 0 — so it slides from where it was to where it
         * now is. */
        private void schedule_flip (GLib.HashTable<DashboardTile, Graphene.Point?> old_pos) {
            Idle.add (() => {
                var origin = Graphene.Point ();
                origin.init (0, 0);
                old_pos.foreach ((tile, old) => {
                    if (tile.get_parent () != tiles) {
                        return;
                    }
                    Graphene.Point now;
                    if (!tile.compute_point (tiles, origin, out now)) {
                        return;
                    }
                    double dx = old.x - now.x;
                    double dy = old.y - now.y;
                    if (dx.abs () < 1.0 && dy.abs () < 1.0) {
                        return;   // didn't move
                    }
                    var target = new Adw.CallbackAnimationTarget ((v) => {
                        tile.offset_x = dx * v;
                        tile.offset_y = dy * v;
                    });
                    var spring = new Adw.SpringAnimation (tile, 1.0, 0.0,
                        new Adw.SpringParams (0.86, 1.0, 240.0), target);
                    spring.epsilon = 0.5;
                    spring.play ();
                });
                return Source.REMOVE;
            });
        }

        /* Column span of a tile at the current width: full row / half / one. */
        private int span_of (DashboardTile tile) {
            switch (tile.config.size) {
                case WidgetSize.FULL: return units_per_row;
                case WidgetSize.HALF: return int.min (2, units_per_row);
                default:              return 1;
            }
        }

        private void clear_grid () {
            Gtk.Widget? child;
            while ((child = tiles.get_first_child ()) != null) {
                tiles.remove (child);   // cache keeps the tile alive
            }
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
            animate_reflow = true;   // existing tiles slide to make room
            rebuild_from_model ();
            persist ();
            var tile = tiles_by_config.lookup (cfg);
            if (tile != null) {
                pop_in (tile);       // the new one pops in
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
                tile.controller.relayout (tile);   // donut ↔ wave etc.
            }
            animate_reflow = true;                 // others slide as the span changes
            rebuild_from_model ();                 // re-pack: the span changed
            persist ();
            pop_in (tile);                         // the resized tile pops
        }

        private void do_remove (DashboardTileConfig cfg) {
            uint pos;
            if (layout.find (cfg, out pos)) {
                layout.remove (pos);
            }
            animate_reflow = true;   // remaining tiles slide to close the gap
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
            animate_reflow = true;   // the moved tile + shifted tiles fly to place
            rebuild_from_model ();
            persist ();
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
