/* link-item.vala
 *
 * Copyright 2026 flex
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

    /* An external link shown in the "Links" section, mirroring the backend's
     * LinkItem. Plain Entity subclass — PascalCase mapping is inherited.
     *
     * The backend's nested "LinkSettings" array is intentionally not modelled:
     * Entity/json-glib does not auto-deserialize collections of objects, so if
     * it is ever needed, iterate that Json.Array by hand (see the note in
     * entity.vala). */
    public class LinkItem : Entity {
        public int id { get; set; default = 0; }
        public string description { get; set; default = ""; }
        public string link_text { get; set; default = ""; }
        public string url { get; set; default = ""; }
        public bool sso { get; set; default = false; }
        public bool written2_web_folder { get; set; default = false; }
        public bool picture { get; set; default = false; }
        public int picture_id { get; set; default = 0; }
        public string picture_path { get; set; default = ""; }
        public int sort_order { get; set; default = 0; }
    }
}
