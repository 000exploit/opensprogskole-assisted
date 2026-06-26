/* connectivity.vala
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

    /* App-wide network reachability, wrapping GIO's NetworkMonitor as one shared
     * source of truth. Write controls tie their sensitivity to `online` through
     * bind_writable, so disabling them while offline needs no per-widget plumbing:
     * add a button, bind it, done — scales to any number across any component.
     *
     * Caveat: NetworkMonitor reports whether a network *route* exists, not that
     * the UMS API is reachable; a request can still fail while `online` is true.
     * The reliable failure feedback is the per-request error toast — this only
     * proactively greys out controls when there is plainly no connection. */
    public class Connectivity : GLib.Object {

        private static Connectivity? _default = null;

        /* The shared instance, created on first use and kept for the app's life. */
        public static unowned Connectivity get_default () {
            if (_default == null) {
                _default = new Connectivity ();
            }
            return _default;
        }

        private GLib.NetworkMonitor monitor;

        /* True while the system has a network route. Notifies on change, which is
         * what every bound control and listener reacts to. */
        public bool online { get; private set; default = true; }

        /* Cancelled the instant the connection drops, so in-flight libsoup
         * requests abort immediately instead of hanging until their timeout. A
         * fresh one is swapped in after each cancellation; pass it to every
         * request (see UmsClient). */
        public GLib.Cancellable cancellable { get; private set; }

        private Connectivity () {
            monitor = GLib.NetworkMonitor.get_default ();
            online = monitor.network_available;
            cancellable = new GLib.Cancellable ();
            monitor.network_changed.connect ((available) => {
                if (!available) {
                    cancellable.cancel ();                  // abort in-flight now
                    cancellable = new GLib.Cancellable ();  // fresh for later
                }
                online = available;
            });
        }

        /* Keep `widget` sensitive only while online — one line per write control;
         * the GBinding unbinds itself when the widget is finalized. Use only for
         * controls gated *solely* by connectivity. Controls that also toggle their
         * own `sensitive` (a busy state) should instead fold `online` into that
         * logic and listen to notify["online"]. */
        public void bind_writable (Gtk.Widget widget) {
            bind_property ("online", widget, "sensitive",
                           GLib.BindingFlags.SYNC_CREATE);
        }
    }
}
