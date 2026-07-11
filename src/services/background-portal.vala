/* background-portal.vala
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

    /* Client for the XDG Background portal (org.freedesktop.portal.Background).
     * Inside Flatpak, running without a window is a permission the compositor
     * grants: request() asks for it, and a granted app appears on GNOME's
     * "Background Apps" list — with the line set through set_status() and a
     * working system-side quit control. Outside a sandbox nothing tracks or
     * enforces background apps, so everything here degrades to a no-op and
     * `allowed` stays true. Raw D-Bus on purpose: two portal calls don't
     * justify a libportal dependency. */
    public class BackgroundPortal : GLib.Object {

        private const string BUS_NAME = "org.freedesktop.portal.Desktop";
        private const string OBJECT_PATH = "/org/freedesktop/portal/desktop";
        private const string IFACE = "org.freedesktop.portal.Background";
        private const string REQUEST_IFACE = "org.freedesktop.portal.Request";

        private static BackgroundPortal? _default = null;

        /* The shared instance, created on first use and kept for the app's life. */
        public static unowned BackgroundPortal get_default () {
            if (_default == null) {
                _default = new BackgroundPortal ();
            }
            return _default;
        }

        /* True only inside Flatpak, where the portal's answer means something. */
        public bool available { get; private set; default = false; }

        /* The compositor's verdict on running windowless. Optimistic until an
         * explicit denial, so a window closed while the request is still in
         * flight hides rather than quits — the portal's background monitor is
         * the safety net for the un-granted case, not us. */
        public bool allowed { get; private set; default = true; }

        // Distinguishes concurrent requests' response paths (see request()).
        private uint next_token = 0;

        private BackgroundPortal () {
            available = GLib.FileUtils.test ("/.flatpak-info", GLib.FileTest.EXISTS);
        }

        /* Ask leave to run in the background; `reason` is shown if the
         * compositor decides to prompt. The verdict lands in `allowed`. Safe
         * to call repeatedly (setting toggled back on): the portal re-checks
         * its stored permission rather than re-prompting every time. */
        public async void request (string reason) {
            if (!available) {
                return;
            }
            try {
                var bus = yield GLib.Bus.get (GLib.BusType.SESSION, null);

                /* Portal requests answer through a Response signal on a request
                 * object whose path is derived from our unique name and the
                 * handle_token we pass in; subscribe before calling so a fast
                 * response can't slip past. */
                string token = "opensprogskole%u".printf (next_token++);
                string sender = bus.unique_name.substring (1).replace (".", "_");
                string request_path =
                    "/org/freedesktop/portal/desktop/request/%s/%s".printf (sender, token);

                GLib.SourceFunc resume = request.callback;
                uint subscription = 0;
                subscription = bus.signal_subscribe (
                    BUS_NAME, REQUEST_IFACE, "Response", request_path, null,
                    GLib.DBusSignalFlags.NO_MATCH_RULE,
                    (connection, sender_name, path, iface, signal_name, parameters) => {
                        uint32 response;
                        GLib.Variant results;
                        parameters.get ("(u@a{sv})", out response, out results);
                        bool granted = false;
                        // 0 = success; anything else (cancelled, failed) = denial.
                        if (response == 0) {
                            results.lookup ("background", "b", out granted);
                        }
                        allowed = granted;
                        debug ("background portal: background %s",
                               granted ? "granted" : "denied");
                        connection.signal_unsubscribe (subscription);
                        GLib.Idle.add ((owned) resume);
                    });

                var options = new GLib.VariantBuilder (GLib.VariantType.VARDICT);
                options.add ("{sv}", "handle_token", new GLib.Variant.string (token));
                options.add ("{sv}", "reason", new GLib.Variant.string (reason));
                options.add ("{sv}", "autostart", new GLib.Variant.boolean (false));

                yield bus.call (BUS_NAME, OBJECT_PATH, IFACE, "RequestBackground",
                                new GLib.Variant ("(sa{sv})", "", options),
                                new GLib.VariantType ("(o)"),
                                GLib.DBusCallFlags.NONE, -1, null);
                yield;   // until the Response handler resumes us
            } catch (GLib.Error e) {
                // No portal or an old one — nothing enforces background apps
                // either, so leaving `allowed` optimistic matches reality.
                debug ("background portal request failed: %s", e.message);
            }
        }

        /* The line GNOME shows under the app in Background Apps while it runs
         * windowless. Fire and forget: portals without Background v2 just
         * error, and a stale message merely stays generic. */
        public void set_status (string message) {
            if (!available) {
                return;
            }
            var options = new GLib.VariantBuilder (GLib.VariantType.VARDICT);
            options.add ("{sv}", "message", new GLib.Variant.string (message));
            GLib.Bus.get.begin (GLib.BusType.SESSION, null, (obj, res) => {
                try {
                    var bus = GLib.Bus.get.end (res);
                    bus.call.begin (BUS_NAME, OBJECT_PATH, IFACE, "SetStatus",
                                    new GLib.Variant ("(a{sv})", options),
                                    null, GLib.DBusCallFlags.NONE, -1, null);
                } catch (GLib.Error e) {
                    debug ("background portal set_status failed: %s", e.message);
                }
            });
        }
    }
}
