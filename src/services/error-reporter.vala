/* error-reporter.vala
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

    /* Everything worth knowing about one failed server exchange, captured at
     * the only place the response bytes exist (UmsClient) and carried to the
     * UI out of band — a Vala errordomain can't hold a payload, and threading
     * this through Session/SessionController would touch every call path. */
    public class ErrorDetails : GLib.Object {

        // Cap how much of a response body is kept: plenty for any real error
        // page, while a runaway payload can't sit in memory for the app's life.
        public const size_t MAX_BODY_LENGTH = 64 * 1024;

        public string method { get; construct; }
        public string url { get; construct; }
        public uint status { get; construct; }
        public string reason_phrase { get; construct; }
        // Short, translated context beyond the status line, e.g. "Malformed
        // response" for a 200 whose body wasn't the expected JSON. May be "".
        public string note { get; construct; }
        // The user-facing name of the operation the request served, e.g.
        // "Call in sick" (see UmsEndpoints.describe). "" when unknown.
        public string operation { get; construct; }
        public string body { get; construct; }
        public GLib.DateTime timestamp { get; construct; }

        public ErrorDetails.from_message (Soup.Message msg, GLib.Bytes? bytes,
                                          string note = "", string operation = "") {
            Object (method: msg.method,
                    url: msg.get_uri ().to_string (),
                    status: msg.status_code,
                    reason_phrase: msg.reason_phrase ?? "",
                    note: note,
                    operation: operation,
                    body: body_from_bytes (bytes),
                    timestamp: new GLib.DateTime.now_local ());
        }

        /* One line for the toast: the friendly operation name when known,
         * else the raw request. The technical detail lives in request_line()
         * and to_clipboard_text(). */
        public string summary () {
            string subject = operation != ""
                ? operation : "%s %s".printf (method, display_path ());
            if (note != "") {
                return "%s: %s (HTTP %u)".printf (subject, note, status);
            }
            return "%s: HTTP %u".printf (subject, status);
        }

        /* The technical one-liner for the dialog: method, path and status
         * line. The host is the user's own school — the path is what
         * identifies the request; the full URL is in to_clipboard_text(). */
        public string request_line () {
            return "%s %s — HTTP %u %s".printf (method, display_path (),
                                                status, reason_phrase).strip ();
        }

        /* The full report for the Copy button. Deliberately untranslated:
         * it's meant to be pasted into bug reports and read by developers. */
        public string to_clipboard_text () {
            var b = new GLib.StringBuilder ();
            b.append_printf ("Time: %s\n", timestamp.format_iso8601 ());
            if (operation != "") {
                b.append_printf ("Operation: %s\n", operation);
            }
            b.append_printf ("Request: %s %s\n", method, url);
            b.append_printf ("Status: HTTP %u %s\n", status, reason_phrase);
            if (note != "") {
                b.append_printf ("Note: %s\n", note);
            }
            b.append ("\n");
            b.append (body != "" ? body : "(empty response body)");
            return b.str;
        }

        private string display_path () {
            try {
                var uri = GLib.Uri.parse (url, GLib.UriFlags.NONE);
                string? query = uri.get_query ();
                return query != null ? uri.get_path () + "?" + query
                                     : uri.get_path ();
            } catch (GLib.Error e) {
                return url;
            }
        }

        private static string body_from_bytes (GLib.Bytes? bytes) {
            if (bytes == null || bytes.get_size () == 0) {
                return "";
            }
            size_t length = bytes.get_size ();
            bool truncated = length > MAX_BODY_LENGTH;
            if (truncated) {
                length = MAX_BODY_LENGTH;
            }
            var builder = new GLib.StringBuilder.sized (length);
            builder.append_len ((string) bytes.get_data (), (ssize_t) length);
            // Server bytes are untrusted — never let invalid UTF-8 reach GTK.
            string text = builder.str.make_valid ();
            if (truncated) {
                text += "\n" + _("… [truncated]");
            }
            return text;
        }
    }

    /* App-wide side channel for server-side failures (same shape as
     * Connectivity): UmsClient reports, the Window listens and raises the
     * "Details" toast. Transport failures (offline, timeout, cancel) are NOT
     * reported — they carry no server response and the loading states / the
     * Connectivity gating already cover them. */
    public class ErrorReporter : GLib.Object {

        private static ErrorReporter? _default = null;

        /* The shared instance, created on first use and kept for the app's life. */
        public static unowned ErrorReporter get_default () {
            if (_default == null) {
                _default = new ErrorReporter ();
            }
            return _default;
        }

        /* The most recent report, kept so the details stay reachable after
         * the toast is gone (or was hidden behind a dialog's scrim). */
        public ErrorDetails? last_error { get; private set; default = null; }

        public signal void error_reported (ErrorDetails details);

        private ErrorReporter () {}

        public void report (ErrorDetails details) {
            last_error = details;
            error_reported (details);
        }
    }
}
