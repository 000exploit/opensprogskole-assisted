/* schools.vala
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

    /* Registry of the language schools the app knows how to talk to. This is the
     * single place real per-school configuration lives; everything else takes a
     * School and stays backend-agnostic. Only Sprogcenter Midt exists for now. */
    namespace Schools {

        /* Sprogcenter Midt (SPC Midt) — runs the UMS backend. */
        public School spc_midt () {
            return new School (
                "scm",
                "Sprogcenter Midt",
                "Horsens",
                "SM",
                "https://ums.sprogcentermidt.dk/api",
                "1030",            // language (UMS passes this literally)
                1                  // accent palette index
            );
        }

        /* Every selectable school, for the login picker. */
        public GLib.GenericArray<School> all () {
            var list = new GLib.GenericArray<School> ();
            list.add (spc_midt ());
            return list;
        }

        /* The school for an id, or the default (SPC Midt) if unknown. */
        public School by_id (string id) {
            var list = all ();
            for (uint i = 0; i < list.length; i++) {
                if (list[i].id == id) {
                    return list[i];
                }
            }
            return spc_midt ();
        }
    }
}
