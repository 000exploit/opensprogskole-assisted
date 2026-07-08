/* links-page.vala
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

    /* The Links page: the school's external links, sourced from the cached login
     * AppSettings (session.links). Each row opens its URL in the browser. Owns no
     * data; the list is offline-friendly since it comes from cache. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/links-page.ui")]
    public class LinksPage : Adw.Bin {

        [GtkChild] private unowned Gtk.ListBox list;
        [GtkChild] private unowned Gtk.Stack stack;

        private Session? session = null;

        public void bind (Session session) {
            this.session = session;
            list.bind_model (session.links, create_row);
            session.links.items_changed.connect (sync_stack);
            sync_stack ();
        }

        private void sync_stack () {
            if (session == null) {
                return;
            }
            stack.visible_child_name =
                session.links.get_n_items () > 0 ? "list" : "empty";
        }

        private Gtk.Widget create_row (GLib.Object object) {
            var item = (LinkItem) object;
            var row = new Adw.ActionRow () {
                title = item.link_text != "" ? item.link_text : item.description,
                subtitle = item.url,
                title_lines = 0,
                subtitle_lines = 0,
                activatable = true
            };

            // Prefix: a generic web icon, swapped for the link's own picture when
            // it has one (loaded + cached via the shared AvatarCache).
            var icon = new Gtk.Image.from_icon_name ("web-browser-symbolic") {
                pixel_size = 24
            };
            row.add_prefix (icon);
            if (item.picture && item.picture_path != "" && session != null) {
                load_icon.begin (icon, item.picture_path);
            }

            row.add_suffix (new Gtk.Image.from_icon_name ("adw-external-link-symbolic"));
            row.activated.connect (() => open_url (item.url));
            return row;
        }

        private async void load_icon (Gtk.Image image, string url) {
            // Keep the generic web icon unless a picture actually arrives.
            yield AvatarCache.load (session.provider, url, (paintable) => {
                if (paintable != null) {
                    image.set_from_paintable (paintable);
                }
            });
        }

        private void open_url (string url) {
            if (url == "") {
                return;
            }
            var launcher = new Gtk.UriLauncher (url);
            launcher.launch.begin (get_root () as Gtk.Window, null, (obj, res) => {
                try {
                    launcher.launch.end (res);
                } catch (GLib.Error e) {
                    warning ("open link failed: %s", e.message);
                }
            });
        }
    }
}
