/* oidc-callback-router.vala
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

    /* Bridges the OS-delivered OIDC redirect to the in-flight login.
     *
     * The browser returns to dk.eg.ludus.mobile://login-callback?code=…; the OS
     * routes that URI to our (single-instance) app, which surfaces it via
     * GApplication.open — far from the LudusProvider that is awaiting it. This
     * singleton is the seam between them, mirroring Connectivity/ErrorReporter:
     * Application.open() calls deliver(); the provider awaits next() for the
     * duration of one flow. */
    public class OidcCallbackRouter : GLib.Object {

        private static OidcCallbackRouter? _default = null;

        public static unowned OidcCallbackRouter get_default () {
            if (_default == null) {
                _default = new OidcCallbackRouter ();
            }
            return _default;
        }

        // Emitted for every OIDC-scheme URI the app is asked to open. The
        // awaiting flow filters by its own `state`; a stray callback (no flow
        // in progress) simply has no listener.
        public signal void redirected (string uri);

        private OidcCallbackRouter () {}

        /* Whether `uri` is an OIDC redirect we should route (vs some other
         * openable the app was handed). */
        public static bool is_callback (string uri) {
            return uri.has_prefix (LudusConfig.REDIRECT_SCHEME + ":");
        }

        /* Feed a delivered redirect URI to whatever flow is waiting. */
        public void deliver (string uri) {
            redirected (uri);
        }

        /* Await the next redirect URI, or null if `cancellable` fires first
         * (the user closed the sign-in prompt). Suspends the caller's async
         * continuation until one or the other resumes it. */
        public async string? next (GLib.Cancellable cancellable) {
            string? result = null;
            bool resumed = false;
            unowned OidcCallbackRouter self = this;

            // Both handlers race; whichever fires first resumes the coroutine
            // exactly once. Idle.add hands the resume to the main loop so we
            // never re-enter synchronously from inside a signal emission.
            ulong redirect_id = 0;
            ulong cancel_id = 0;
            redirect_id = redirected.connect ((uri) => {
                if (resumed) {
                    return;
                }
                resumed = true;
                result = uri;
                Idle.add (next.callback);
            });
            cancel_id = cancellable.connect (() => {
                if (resumed) {
                    return;
                }
                resumed = true;
                Idle.add (next.callback);
            });

            yield;

            self.disconnect (redirect_id);
            cancellable.disconnect (cancel_id);
            return result;
        }
    }
}
