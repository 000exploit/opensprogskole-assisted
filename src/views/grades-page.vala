/* grades-page.vala
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

    /* The Grades page: the list of grades from the session, a spinner while the
     * first fetch settles, or an empty state. Owns no data — a mirror of
     * AbsencePage, just bound to session.grades.
     *
     * TODO (multiple grade types): when additional categories of grades arrive,
     * this single list becomes one page of an Adw.ViewStack (see grades-page.blp
     * for the layout side). The bind/sync logic here would then fan out to one
     * Grades widget per type, each driven exactly like the single list below. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/grades-page.ui")]
    public class GradesPage : Adw.Bin {

        [GtkChild] private unowned Grades grades_list;
        [GtkChild] private unowned Gtk.Stack stack;

        private Session? session = null;

        public void bind (Session session) {
            this.session = session;
            // The Grades widget tracks the store directly, so rows appear the
            // moment grades land. The stack (loading / list / empty) is driven by
            // the same signals: items-changed for live edits, updated for the
            // loading→loaded transition (incl. the "loaded but empty" case).
            grades_list.bind (session.grades);
            session.grades.items_changed.connect (sync_stack);
            session.updated.connect (sync_stack);
            sync_stack ();
        }

        private void sync_stack () {
            if (session == null) {
                return;
            }
            if (!session.grades_loaded) {
                stack.visible_child_name = "loading";
                return;
            }
            stack.visible_child_name =
                session.grades.get_n_items () > 0 ? "list" : "empty";
        }
    }
}
