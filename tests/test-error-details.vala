/* test-error-details.vala
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

/* ErrorDetails/ErrorReporter against a real libsoup exchange: a local
 * Soup.Server plays the UMS backend, so capture, truncation, formatting and
 * the report signal are exercised exactly as UmsClient drives them. */

namespace Opensprogskole.Tests {

    private Soup.Server server;
    private string base_url;

    private const size_t BIG_BODY_LENGTH = 100 * 1024;   // > MAX_BODY_LENGTH

    /* Fetch `path` and capture it as UmsClient.report would. Requests run
     * async on the default main context so the in-process server can answer. */
    private ErrorDetails fetch (string method, string path,
                                string note = "", string operation = "") {
        var session = new Soup.Session ();
        var msg = new Soup.Message (method, base_url + path);
        ErrorDetails? details = null;
        var loop = new GLib.MainLoop ();
        session.send_and_read_async.begin (msg, GLib.Priority.DEFAULT, null,
                                           (obj, res) => {
            try {
                var bytes = session.send_and_read_async.end (res);
                details = new ErrorDetails.from_message (msg, bytes, note, operation);
            } catch (GLib.Error e) {
                GLib.Test.fail_printf ("request failed: %s", e.message);
            }
            loop.quit ();
        });
        loop.run ();
        assert_nonnull (details);
        return details;
    }

    private void test_capture () {
        var d = fetch ("POST", "/api/fail?day=1");
        assert_cmpuint (d.status, GLib.CompareOperator.EQ, 500);
        assert_cmpstr (d.method, GLib.CompareOperator.EQ, "POST");
        assert_cmpstr (d.body, GLib.CompareOperator.EQ, "{\"Message\":\"boom\"}");
        assert_true (d.url.has_suffix ("/api/fail?day=1"));
        assert_cmpstr (d.summary (), GLib.CompareOperator.EQ,
                       "POST /api/fail?day=1: HTTP 500");
        assert_true (d.request_line ().has_prefix ("POST /api/fail?day=1 — HTTP 500"));

        string clip = d.to_clipboard_text ();
        assert_true (clip.contains ("Request: POST http://"));
        assert_true (clip.contains ("Status: HTTP 500"));
        assert_true (clip.contains ("{\"Message\":\"boom\"}"));
    }

    private void test_operation_and_note () {
        var d = fetch ("GET", "/api/empty", "Malformed response", "Timetable");
        assert_cmpstr (d.body, GLib.CompareOperator.EQ, "");
        assert_cmpstr (d.summary (), GLib.CompareOperator.EQ,
                       "Timetable: Malformed response (HTTP 404)");
        string clip = d.to_clipboard_text ();
        assert_true (clip.contains ("Operation: Timetable"));
        assert_true (clip.contains ("Note: Malformed response"));
        assert_true (clip.contains ("(empty response body)"));
    }

    private void test_truncation () {
        var d = fetch ("GET", "/api/big");
        assert_cmpuint (d.body.length, GLib.CompareOperator.LT, (uint) BIG_BODY_LENGTH);
        assert_true (d.body.has_suffix ("[truncated]"));
    }

    private void test_invalid_utf8 () {
        var d = fetch ("GET", "/api/binary");
        // Whatever came back must be valid UTF-8 by the time it can reach GTK.
        assert_true (d.body.validate ());
    }

    private void test_reporter () {
        var d = fetch ("GET", "/api/empty");
        ErrorDetails? received = null;
        ulong id = ErrorReporter.get_default ().error_reported.connect ((det) => {
            received = det;
        });
        ErrorReporter.get_default ().report (d);
        ErrorReporter.get_default ().disconnect (id);
        assert_true (received == d);
        assert_true (ErrorReporter.get_default ().last_error == d);
    }

    private void test_endpoint_names () {
        assert_cmpstr (UmsEndpoints.describe ("/api" + UmsEndpoints.AUTHENTICATE),
                       GLib.CompareOperator.EQ, "Login");
        assert_cmpstr (UmsEndpoints.describe (
                           "/api" + UmsEndpoints.GET_TIMETABLE + "?language=1030"),
                       GLib.CompareOperator.EQ, "Timetable");
        // The settings path contains the plain user-info path — the longer
        // one must win.
        assert_cmpstr (UmsEndpoints.describe ("/api" + UmsEndpoints.GET_USER_INFO_SETTINGS),
                       GLib.CompareOperator.EQ, "Profile settings");
        assert_cmpstr (UmsEndpoints.describe ("/api" + UmsEndpoints.GET_USER_INFO + "/dXNlcg"),
                       GLib.CompareOperator.EQ, "Profile");
        assert_null (UmsEndpoints.describe ("/api/Somewhere/Else"));
    }

    public static int main (string[] args) {
        GLib.Test.init (ref args);

        server = new Soup.Server ("server-header", "test");
        server.add_handler ("/api/fail", (srv, m, path, query) => {
            m.set_status (500, null);
            m.set_response ("application/json", Soup.MemoryUse.COPY,
                            "{\"Message\":\"boom\"}".data);
        });
        server.add_handler ("/api/big", (srv, m, path, query) => {
            var big = new uint8[BIG_BODY_LENGTH];
            GLib.Memory.set (big, 'A', big.length);
            m.set_status (500, null);
            m.set_response ("text/plain", Soup.MemoryUse.COPY, big);
        });
        server.add_handler ("/api/binary", (srv, m, path, query) => {
            uint8 garbage[] = { 0xff, 0xfe, 'h', 'i', 0xc0, 0x80 };
            m.set_status (500, null);
            m.set_response ("application/octet-stream", Soup.MemoryUse.COPY, garbage);
        });
        server.add_handler ("/api/empty", (srv, m, path, query) => {
            m.set_status (404, null);
        });
        try {
            server.listen_local (0, 0);
        } catch (GLib.Error e) {
            GLib.error ("listen failed: %s", e.message);
        }
        base_url = server.get_uris ().nth_data (0).to_string ();
        // The handlers above expect no trailing slash on the base.
        if (base_url.has_suffix ("/")) {
            base_url = base_url.substring (0, base_url.length - 1);
        }

        GLib.Test.add_func ("/error-details/capture", test_capture);
        GLib.Test.add_func ("/error-details/operation-and-note", test_operation_and_note);
        GLib.Test.add_func ("/error-details/truncation", test_truncation);
        GLib.Test.add_func ("/error-details/invalid-utf8", test_invalid_utf8);
        GLib.Test.add_func ("/error-details/reporter", test_reporter);
        GLib.Test.add_func ("/error-details/endpoint-names", test_endpoint_names);
        return GLib.Test.run ();
    }
}
