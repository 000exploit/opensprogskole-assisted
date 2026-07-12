/* sync-runner.vala
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

    /* Drives one complete headless cache refresh: silent login from the saved
     * account, Session.sync_all(), store flush — blocking until done. No UI
     * type may sneak in here: this is what the desktop `--sync` flag runs and
     * what the Android background worker calls into with no GTK anywhere in
     * the process. Progress goes to stderr for the CLI case and to the GLib
     * log for logcat. */
    public class SyncRunner : GLib.Object {

        public const uint DEFAULT_TIMEOUT_SECONDS = 180;

        /* Run one sync to completion on the calling thread, iterating that
         * thread's default main context. Returns 0 on success, 1 on any
         * failure (no saved login, login failed, timeout). */
        public static int run (SessionController controller,
                               uint timeout_seconds = DEFAULT_TIMEOUT_SECONDS) {
            var loop = new GLib.MainLoop ();
            int exit_code = 0;

            controller.needs_login.connect ((username, error) => {
                string message = error ?? _("Not logged in. Start the app and sign in first.");
                printerr ("%s\n", message);
                warning ("headless sync: %s", message);
                exit_code = 1;
                loop.quit ();
            });
            controller.login_failed.connect ((message) => {
                printerr ("%s\n", message);
                warning ("headless sync: %s", message);
                exit_code = 1;
                loop.quit ();
            });
            controller.authenticated.connect ((session) => {
                session.sync_all.begin ((o, r) => {
                    session.sync_all.end (r);
                    Storage.flush_all ();
                    loop.quit ();
                });
            });

            // A stuck request must not leave a zombie process (or a worker
            // Android counts against the app) hanging around forever.
            GLib.Timeout.add_seconds (timeout_seconds, () => {
                printerr ("%s\n", _("Sync timed out."));
                warning ("headless sync: timed out after %u s", timeout_seconds);
                exit_code = 1;
                loop.quit ();
                return GLib.Source.REMOVE;
            });

            controller.start ();
            loop.run ();
            return exit_code;
        }
    }

    /* Where Android's notification content crosses the JNI boundary. There is
     * no GNotification backend on Android, so NewsNotifier queues its payloads
     * here instead of sending; worker_sync drains the queue into its return
     * value and the Java side (SyncWorker) posts real notifications. Only the
     * worker path needs this: the in-process periodic timer is disabled on
     * Android (see SessionController), and foreground refreshes are suppressed
     * by the focus policy anyway. */
    public class PendingNotes {
        private class Note {
            public string id;
            public string title;
            public string body;

            public Note (string id, string title, string body) {
                this.id = id;
                this.title = title;
                this.body = body;
            }
        }

        private static GLib.GenericArray<Note>? notes = null;

        public static void queue (string id, string title, string body) {
            if (notes == null) {
                notes = new GLib.GenericArray<Note> ();
            }
            notes.add (new Note (id, title, body));
            debug ("queued note '%s' for the worker", id);
        }

        /* All queued notes as a JSON array of {id,title,body}; empties the
         * queue. "[]" when there is nothing to tell. */
        public static string drain () {
            var builder = new Json.Builder ();
            builder.begin_array ();
            if (notes != null) {
                for (uint i = 0; i < notes.length; i++) {
                    builder.begin_object ();
                    builder.set_member_name ("id");
                    builder.add_string_value (notes[i].id);
                    builder.set_member_name ("title");
                    builder.add_string_value (notes[i].title);
                    builder.set_member_name ("body");
                    builder.add_string_value (notes[i].body);
                    builder.end_object ();
                }
                notes = null;
            }
            builder.end_array ();
            return Json.to_string (builder.get_root (), false);
        }
    }

    /* The cross-thread handshake behind worker_sync: the WorkManager thread
     * parks on wait() while the GTK thread reports the outcome via finish().
     * A heap object on purpose — Vala closures capture Mutex/Cond *structs*
     * by value, which would silently break the signaling. finish() is
     * idempotent: a late completion after the worker already timed out must
     * not do anything worse than a no-op. */
    private class SyncGate {
        private GLib.Mutex mutex = GLib.Mutex ();
        private GLib.Cond cond = GLib.Cond ();
        private bool finished = false;
        private int result = 1;

        public void finish (int result) {
            mutex.lock ();
            if (!finished) {
                this.result = result;
                finished = true;
                cond.signal ();
            }
            mutex.unlock ();
        }

        public int wait (uint timeout_seconds) {
            int64 deadline = GLib.get_monotonic_time ()
                             + timeout_seconds * GLib.TimeSpan.SECOND;
            mutex.lock ();
            while (!finished) {
                if (!cond.wait_until (mutex, deadline)) {
                    break;   // timed out; `result` keeps its failure default
                }
            }
            int result = this.result;
            mutex.unlock ();
            return result;
        }
    }

    /* The Android background worker's door into the native library, hence the
     * fixed C-friendly name (called by the JNI shim, see src/android/). The
     * GTK runtime glue boots the full app — main(), GLib loop, auto-login —
     * at *every* process start, activity or not, so by the time WorkManager
     * runs us a resident Application always exists. All this does is ask it,
     * from the worker's thread, to run one sync_all() and block here until
     * that lands or fails/times out. Returns the drained news payload as a
     * JSON array ("[]" = synced, nothing new) or null on failure — the Java
     * side posts the notifications and maps null to a WorkManager retry. */
    [CCode (cname = "opensprogskole_worker_sync")]
    public string? worker_sync () {
        var gate = new SyncGate ();

        GLib.MainContext.default ().invoke (() => {
            var app = GLib.Application.get_default () as Application;
            if (app == null) {
                warning ("worker sync: no resident application; runtime not up?");
                gate.finish (1);
                return GLib.Source.REMOVE;
            }
            var settings = new GLib.Settings (Config.APP_ID);
            if (!settings.get_boolean ("background-sync")) {
                debug ("worker sync: background sync is disabled");
                gate.finish (0);   // nothing to do is a success, not a retry
                return GLib.Source.REMOVE;
            }

            if (app.controller.session != null) {
                worker_sync_now (app.controller.session, gate);
            } else {
                // Auto-login is still in flight (we likely share its process
                // start); one-shot handlers pick up whichever way it lands.
                ulong ok_id = 0, fail_id = 0;
                ok_id = app.controller.authenticated.connect ((session) => {
                    app.controller.disconnect (ok_id);
                    app.controller.disconnect (fail_id);
                    worker_sync_now (session, gate);
                });
                fail_id = app.controller.needs_login.connect ((username, error) => {
                    app.controller.disconnect (ok_id);
                    app.controller.disconnect (fail_id);
                    warning ("worker sync: not logged in (%s)", error ?? "no account");
                    gate.finish (1);
                });
            }
            return GLib.Source.REMOVE;
        });

        if (gate.wait (SyncRunner.DEFAULT_TIMEOUT_SECONDS) != 0) {
            return null;
        }
        return PendingNotes.drain ();
    }

    private void worker_sync_now (Session session, SyncGate gate) {
        session.sync_all.begin ((o, r) => {
            session.sync_all.end (r);
            Storage.flush_all ();
            gate.finish (0);
        });
    }
}
