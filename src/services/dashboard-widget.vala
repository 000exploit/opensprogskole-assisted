/* dashboard-widget.vala
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

    /* A tile's footprint. Maps to a CSS min-width class (see style.css); the
     * DashboardView WrapBox reflows them, and forces a single column when
     * narrow. */
    public enum WidgetSize { MINI, HALF, FULL }

    /* One placed tile: the widget type + its size. This is the persisted unit
     * and the dashboard's source of truth (an ordered ListStore of these). */
    public class DashboardTileConfig : GLib.Object {
        public string type_id { get; set; }
        public WidgetSize size { get; set; }

        public DashboardTileConfig (string type_id, WidgetSize size) {
            Object (type_id: type_id, size: size);
        }
    }

    /* The card chrome shared by every tile (header + a content Stack the
     * controller drives). Composition, not inheritance: a DashboardTile holds a
     * DashboardWidget `controller` that builds the presenter and binds it —
     * this avoids subclassing a GtkTemplate. The tile is what the WrapBox packs
     * and what carries drag-and-drop + edit mode. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/dashboard-widget.ui")]
    public class DashboardTile : Adw.Bin {

        [GtkChild] private unowned Box tile_box;
        [GtkChild] private unowned Image icon_image;
        [GtkChild] private unowned Label title_label;
        [GtkChild] private unowned Label subtitle_label;
        [GtkChild] private unowned Adw.Bin header_action_slot;
        [GtkChild] private unowned Box edit_controls;
        [GtkChild] private unowned Button resize_button;
        [GtkChild] private unowned Button remove_button;
        [GtkChild] private unowned Gtk.Stack content_stack;
        [GtkChild] private unowned Adw.Bin content_slot;
        [GtkChild] private unowned LoadingState loading;
        [GtkChild] private unowned Adw.StatusPage empty_page;

        /* The type + size this tile renders (kept so DnD/persistence can read
         * back the placement from the widget). */
        public DashboardTileConfig config { get; construct; }

        /* The logic driving this tile's content. Owned, so caching the tile in
         * the view keeps its controller (and its signal subscriptions) alive. */
        public DashboardWidget? controller { get; set; default = null; }

        public string title {
            get { return title_label.label; }
            set { title_label.label = value; }
        }

        /* A contextual line under the title (e.g. the up-next day), or "" to
         * hide it. */
        public string subtitle {
            get { return subtitle_label.label; }
            set {
                subtitle_label.label = value;
                subtitle_label.visible = value != "";
            }
        }

        public string icon_name {
            owned get { return icon_image.icon_name ?? ""; }
            set {
                icon_image.icon_name = value;
                icon_image.visible = value != "";
            }
        }

        /* In edit mode the remove button shows and the presenter goes
         * insensitive so its own controls can't swallow the drag gesture. */
        public bool edit_mode {
            get { return _edit_mode; }
            set {
                _edit_mode = value;
                // Float the controls over the tile; block the whole card's
                // input (header action included, not just the content) so a
                // press starts a drag / hits the edit controls. The edit
                // controls sit on a separate overlay layer, so they stay live.
                edit_controls.visible = value;
                tile_box.sensitive = !value;
                if (value) {
                    add_css_class ("editing");
                } else {
                    remove_css_class ("editing");
                }
            }
        }
        private bool _edit_mode = false;

        /* Whether the resize button is offered (the widget supports >1 size).
         * Set by the view from the registry. */
        public bool can_resize {
            get { return _can_resize; }
            set {
                _can_resize = value;
                resize_button.visible = value;
            }
        }
        private bool _can_resize = false;

        /* The user tapped the resize control — the view cycles the size. */
        public signal void size_change_requested ();

        /* Uniform scale about the centre, applied in snapshot() (so it never
         * disturbs layout) — the SpringAnimation "pop" on add/drop writes it. */
        public double scale { get; set; default = 1.0; }

        // Pointer offset inside the tile where a drag began, so the drag icon
        // (a WidgetPaintable of this tile) lines up under the cursor.
        public int drag_hotspot_x = 0;
        public int drag_hotspot_y = 0;

        public signal void remove_requested ();

        public DashboardTile (DashboardTileConfig config) {
            Object (config: config);
        }

        construct {
            apply_size_class ();
            remove_button.clicked.connect (() => remove_requested ());
            resize_button.clicked.connect (() => size_change_requested ());
            notify["scale"].connect (queue_draw);
        }

        /* Re-apply the CSS width class after config.size changes (on resize). */
        public void apply_size_class () {
            remove_css_class ("size-mini");
            remove_css_class ("size-half");
            remove_css_class ("size-full");
            switch (config.size) {
                case WidgetSize.MINI: add_css_class ("size-mini"); break;
                case WidgetSize.HALF: add_css_class ("size-half"); break;
                default:              add_css_class ("size-full"); break;
            }
            // Minis shouldn't stretch to a tall neighbour's height in a WrapBox
            // line; keep them their natural size, pinned to the top.
            valign = config.size == WidgetSize.MINI ? Align.START : Align.FILL;
        }

        // --- Content the controller drives -------------------------------------

        public void set_content (Gtk.Widget widget) {
            content_slot.child = widget;
        }

        /* A controller-provided action shown top-right in the header (or null). */
        public void set_header_action (Gtk.Widget? widget) {
            header_action_slot.child = widget;
        }

        public void show_loading (string? error) {
            loading.error = error ?? "";
            content_stack.visible_child_name = "loading";
        }

        public void show_content () {
            content_stack.visible_child_name = "content";
        }

        public void show_empty (string title, string description, string icon_name) {
            empty_page.title = title;
            empty_page.description = description;
            empty_page.icon_name = icon_name;
            content_stack.visible_child_name = "empty";
        }

        public void show_unavailable () {
            content_stack.visible_child_name = "unavailable";
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            if (scale == 1.0) {
                base.snapshot (snapshot);
                return;
            }
            float w = get_width ();
            float h = get_height ();
            snapshot.translate ({ w / 2, h / 2 });
            snapshot.scale ((float) scale, (float) scale);
            snapshot.translate ({ -w / 2, -h / 2 });
            base.snapshot (snapshot);
        }
    }

    /* The per-type logic behind a tile: builds its presenter and binds it to a
     * Session, driving the tile's content Stack. One instance per placed tile,
     * created by the registry from a type-id. Subclasses reuse the existing
     * "dumb" presenter widgets (Chart, DayLessons, Grades, ...). */
    public abstract class DashboardWidget : GLib.Object {

        /* A widget asks the shell to open a core section ("schedule",
         * "grades", ...) — e.g. the "View schedule" button on the up-next tile.
         * The DashboardView forwards it to main-view. */
        public signal void navigate (string section);

        /* Create the presenter widget (called once); may keep a reference for
         * bind() to populate. `tile` is passed so a widget that needs to open a
         * dialog has a presentation parent. */
        public abstract Gtk.Widget build (DashboardTile tile);

        /* Subscribe to the Session and render the first state. Uses the tile's
         * show_loading/show_content/show_empty to reflect load state. Only
         * called when the provider supports the widget's data (the view gates
         * on capability first). */
        public abstract void bind (Session session, DashboardTile tile);

        /* The tile's size changed (a resize): rebuild the presenter for the new
         * size and re-render, WITHOUT re-subscribing (bind already did). Default
         * is a no-op for size-agnostic widgets; size-switching widgets (e.g.
         * attendance donut ↔ wave) override it. */
        public virtual void relayout (DashboardTile tile) {}
    }
}
