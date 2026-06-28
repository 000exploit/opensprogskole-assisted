/* link-item.vala
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

    /* An external link shown in the "Links" section, built from a StorageNode over
     * the cached AppSettings.UserVariables.Links entry (PascalCase keys). Only the
     * fields the Links page renders are kept. */
    public class LinkItem : GLib.Object {
        public string link_text { get; set; default = ""; }
        public string description { get; set; default = ""; }
        public string url { get; set; default = ""; }
        public bool picture { get; set; default = false; }
        public string picture_path { get; set; default = ""; }

        public static LinkItem from_node (StorageNode n) {
            return new LinkItem () {
                link_text = n.get_string ("LinkText"),
                description = n.get_string ("Description"),
                url = n.get_string ("Url"),
                picture = n.get_bool ("Picture"),
                picture_path = n.get_string ("PicturePath")
            };
        }
    }
}
