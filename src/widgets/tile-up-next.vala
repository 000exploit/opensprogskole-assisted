/* tile-up-next.vala
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

    /* "Up next" tile. FULL: the next relevant day's lessons (DayLessons), with
     * the day shown in the tile subtitle. MINI: a single "next class" card with
     * a countdown and an Open button (à la the Lingu mockup). */
    public class UpNextWidget : DashboardWidget {

        private Session? session = null;

        // FULL presenter.
        private DayLessons? lessons = null;

        // MINI presenter.
        private Gtk.Box? mini = null;
        private Label? mini_caption = null;
        private Label? mini_title = null;
        private Label? mini_room = null;
        private TimetableItem? next_item = null;

        private static bool is_mini (DashboardTile tile) {
            return tile.config.size == WidgetSize.MINI;
        }

        public override Gtk.Widget build (DashboardTile tile) {
            return create_presenter (tile);
        }

        public override void bind (Session session, DashboardTile tile) {
            this.session = session;
            session.timetable_updated.connect (() => render (tile));
            session.updated.connect (() => render (tile));
            render (tile);
        }

        public override void relayout (DashboardTile tile) {
            tile.set_content (create_presenter (tile));
            render (tile);
        }

        private Gtk.Widget create_presenter (DashboardTile tile) {
            if (is_mini (tile)) {
                return build_mini (tile);
            }
            lessons = new DayLessons () { compact = true };
            lessons.lesson_activated.connect ((item) => open_lesson (tile, item));
            mini = null;

            var view_all = new Button.with_label (_("View schedule"));
            view_all.add_css_class ("accent");
            view_all.add_css_class ("flat");
            view_all.clicked.connect (() => navigate ("schedule"));
            tile.set_header_action (view_all);

            return lessons;
        }

        private Gtk.Widget build_mini (DashboardTile tile) {
            lessons = null;
            tile.set_header_action (null);
            mini_caption = new Label ("") { halign = Align.START, xalign = 0 };
            mini_caption.add_css_class ("caption-heading");
            mini_caption.add_css_class ("accent");
            mini_title = new Label ("") { halign = Align.START, xalign = 0, wrap = true };
            mini_title.add_css_class ("title-3");
            mini_room = new Label ("") { halign = Align.START, xalign = 0, ellipsize = Pango.EllipsizeMode.END };
            mini_room.add_css_class ("caption");
            mini_room.add_css_class ("dim-label");

            var text = new Box (Orientation.VERTICAL, 2) { hexpand = true, valign = Align.CENTER };
            text.append (mini_caption);
            text.append (mini_title);
            text.append (mini_room);

            var open = new Button.with_label (_("Open")) { valign = Align.CENTER };
            open.add_css_class ("suggested-action");
            open.add_css_class ("pill");
            open.clicked.connect (() => {
                if (next_item != null) {
                    open_lesson (tile, next_item);
                }
            });

            mini = new Box (Orientation.HORIZONTAL, 10);
            mini.append (text);
            mini.append (open);
            return mini;
        }

        private void open_lesson (DashboardTile tile, TimetableItem item) {
            if (session != null) {
                new LessonDialog (item, session).present (tile);
            }
        }

        private void render (DashboardTile tile) {
            if (session == null) {
                return;
            }
            if (session.timetable_state != LoadState.LOADED) {
                tile.subtitle = "";
                tile.show_loading (session.timetable_state == LoadState.FAILED
                    ? _("Couldn't load lessons.") : "");
                return;
            }

            var now = new DateTime.now_local ();
            string? key = session.timetable.upcoming_day_key (now);
            if (key == null) {
                tile.subtitle = "";
                next_item = null;
                tile.show_empty (_("No more lessons"),
                    _("You're all caught up."), "appointment-soon-symbolic");
                return;
            }

            var model = session.timetable.get_day_for_key (key);
            tile.subtitle = day_label_for (key, now);

            if (is_mini (tile)) {
                render_mini (model, key, now);
            } else {
                lessons.bind (model, day_label_for (key, now));
            }
            tile.show_content ();
        }

        private void render_mini (GLib.ListModel? model, string key, DateTime now) {
            DateTime? when;
            next_item = next_lesson (model, key, now, out when);
            if (next_item == null) {
                mini_caption.label = _("NEXT CLASS");
                mini_title.label = _("Nothing scheduled");
                mini_room.label = "";
                return;
            }
            int mins = when != null
                ? (int) ((when.to_unix () - now.to_unix ()) / 60) : -1;
            mini_caption.label = mins >= 0
                ? _("NEXT CLASS · IN %s").printf (human_delay (mins))
                : _("NEXT CLASS");
            mini_title.label = "%s — %s".printf (next_item.start_time, next_item.subject);
            mini_room.label = next_item.room.replace ("<br>", " / ").strip ();
        }

        /* The first lesson of `key`'s day that hasn't started yet (or the first
         * of a future day), with its start DateTime. */
        private TimetableItem? next_lesson (GLib.ListModel? model, string key,
                                            DateTime now, out DateTime? when) {
            when = null;
            if (model == null || model.get_n_items () == 0) {
                return null;
            }
            TimetableItem first = (TimetableItem) model.get_item (0);
            for (uint i = 0; i < model.get_n_items (); i++) {
                var item = (TimetableItem) model.get_item (i);
                var dt = parse_dt (key, item.start_time);
                if (dt != null && dt.compare (now) > 0) {
                    when = dt;
                    return item;
                }
            }
            when = parse_dt (key, first.start_time);
            return first;
        }

        private static DateTime? parse_dt (string key, string hhmm) {
            if (key.length < 10 || hhmm.length < 5) {
                return null;
            }
            return new DateTime.local (
                int.parse (key.substring (0, 4)),
                int.parse (key.substring (5, 2)),
                int.parse (key.substring (8, 2)),
                int.parse (hhmm.substring (0, 2)),
                int.parse (hhmm.substring (3, 2)), 0);
        }

        private static string human_delay (int minutes) {
            if (minutes < 60) {
                return _("%d MIN").printf (minutes);
            }
            int h = minutes / 60;
            int m = minutes % 60;
            return m > 0 ? _("%dH %dMIN").printf (h, m) : _("%dH").printf (h);
        }

        private static string day_label_for (string key, DateTime now) {
            if (key == now.format ("%Y-%m-%d")) {
                return _("Today");
            }
            var day = new DateTime.local (
                int.parse (key.substring (0, 4)),
                int.parse (key.substring (5, 2)),
                int.parse (key.substring (8, 2)), 0, 0, 0);
            /* Translators: a weekday + date, e.g. "Tuesday, 30 June". */
            return day.format (_("%A, %-d %B"));
        }
    }
}
