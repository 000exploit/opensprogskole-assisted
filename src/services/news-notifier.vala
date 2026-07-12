/* news-notifier.vala
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

    /* Turns news into user notifications, and owns the entire policy around
     * them: the opt-in preferences (all default off), and suppression while
     * the window is focused — someone actively looking at the app does not
     * need a ping about what just appeared on screen.
     *
     * The detection lives in NewsTracker (one per session, created here);
     * this service is only the delivery side, one per app. Future scheduled
     * reminders ("exam tomorrow morning") belong here too: this is the one
     * place that knows what has been announced. */
    public class NewsNotifier : GLib.Object {

        private unowned Gtk.Application app;
        private GLib.Settings settings;
        private NewsTracker? tracker = null;

        public NewsNotifier (Gtk.Application app, GLib.Settings settings,
                             SessionController controller) {
            this.app = app;
            this.settings = settings;
            // Each login creates a fresh Session and with it a fresh tracker;
            // the old pair keeps each other alive and dies together.
            controller.authenticated.connect ((session) => {
                tracker = new NewsTracker (session);
                tracker.grades_added.connect (on_grades_added);
                tracker.exams_added.connect (on_exams_added);
            });
        }

        private bool window_in_view () {
            return app.active_window != null && app.active_window.is_active;
        }

        /* Platform seam: GNotification has no Android backend, so there the
         * payload goes to the worker's queue (PendingNotes) and the Java side
         * posts it as a real Android notification. */
        private void deliver (string id, string title, string body) {
#if ANDROID
            PendingNotes.queue (id, title, body);
#else
            var note = new GLib.Notification (title);
            note.set_body (body);
            app.send_notification (id, note);
#endif
        }

        private void on_grades_added (GradeItem[] items) {
            if (!settings.get_boolean ("notify-new-grades") || window_in_view ()) {
                debug ("suppressing new-grades notification (%d items)", items.length);
                return;
            }
            debug ("notifying about %d new grade(s)", items.length);
            var lines = new GLib.StringBuilder ();
            foreach (var item in items) {
                if (lines.len > 0) {
                    lines.append ("\n");
                }
                lines.append_printf ("%s: %s", item.course, item.display_label);
            }
            deliver ("new-grades",
                     GLib.ngettext ("New grade", "New grades", items.length),
                     lines.str);
        }

        private void on_exams_added (TimetableItem[] items) {
            if (!settings.get_boolean ("notify-new-exams") || window_in_view ()) {
                debug ("suppressing new-exams notification (%d items)", items.length);
                return;
            }
            debug ("notifying about %d new exam(s)", items.length);
            var lines = new GLib.StringBuilder ();
            foreach (var item in items) {
                if (lines.len > 0) {
                    lines.append ("\n");
                }
                var start = item.time_table_real_start_date_time;
                if (start != null) {
                    // Translators: an exam line in a notification — subject,
                    // then e.g. "Mon 20 May, 08:15".
                    lines.append_printf (_("%s — %s"), item.subject,
                                         start.format (_("%a %e %b, %H:%M")));
                } else {
                    lines.append (item.subject);
                }
            }
            deliver ("new-exams",
                     GLib.ngettext ("Exam scheduled", "Exams scheduled", items.length),
                     lines.str);
        }
    }
}
