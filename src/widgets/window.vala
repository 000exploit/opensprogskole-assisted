/* window.vala
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

/* Pure view layer: a three-state stack (onboarding / loading / main) that mirrors
 * the SessionController's state signals and forwards the user's intents back to
 * it. No auth, network, keyring or token logic lives here. */
[GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/window.ui")]
public class Opensprogskole.Window : Adw.ApplicationWindow {

    [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
    [GtkChild] private unowned Gtk.Stack root_stack;
    [GtkChild] private unowned OnboardingView onboarding;
    [GtkChild] private unowned MainView main_view;
#if ANDROID
    [GtkChild] private unowned Adw.AlertDialog quit_dialog;
#endif

    private SessionController controller;

    // The one pending error toast: repeated background failures (e.g. every
    // refresh while the server is down) update it instead of stacking.
    private Adw.Toast? error_toast = null;

    public Window (Gtk.Application app, SessionController controller) {
        Object (application: app);
        this.controller = controller;

        ErrorReporter.get_default ().error_reported.connect (on_error_reported);

        /* Took from GeopJr/Tuba /
		/  FIX: hack for the broken font */
		#if ANDROID
		    this.add_css_class ("android");
		    // Android delivers the system back gesture/button as a window
		    // close-request. Route it through the in-app navigation instead of
		    // quitting outright (see on_close_request).
		    close_request.connect (on_close_request);
		    quit_dialog.response.connect ((response) => {
		        if (response == "quit") {
		            destroy ();
		        }
		    });
		#else
		    // Desktop: with background sync enabled and a live session, closing
		    // the window hides it instead — the process stays resident and the
		    // periodic sync keeps the cache warm (a hidden window keeps
		    // GtkApplication alive, no hold() needed). Launching the app again
		    // re-presents it (Application.activate); app.quit exits for real.
		    var settings = new GLib.Settings (Config.APP_ID);
		    close_request.connect (() => {
		        if (settings.get_boolean ("background-sync") && controller.session != null) {
		            set_visible (false);
		            ((Opensprogskole.Application) application).notify_hidden_to_background ();
		            return true;
		        }
		        return false;
		    });
		#endif

        // User intents → controller.
        onboarding.login_request.connect ((school, method, credentials, remember) => {
            onboarding.set_busy (true);
            controller.try_login.begin (school, method, credentials, remember);
        });
        onboarding.login_cancel_request.connect (() => controller.cancel_login ());
        onboarding.finished.connect (() => controller.enter ());

        // Controller state → screens.
        controller.loading.connect (() => {
            root_stack.visible_child_name = "loading";
        });
        controller.needs_login.connect ((username, error) => {
            onboarding.set_busy (false);
            if (username != null) {
                onboarding.prefill (username);
            } else {
                onboarding.reset ();
            }
            if (error != null) {
                onboarding.show_error (error);
            }
            root_stack.visible_child_name = "onboarding";
        });
        controller.login_failed.connect ((message) => {
            onboarding.set_busy (false);
            onboarding.show_error (message);
        });
        controller.login_cancelled.connect (() => {
            onboarding.set_busy (false);   // back to the form, no error banner
        });
        controller.login_succeeded.connect (() => {
            onboarding.set_busy (false);
            onboarding.login_succeeded ();
        });
        controller.authenticated.connect ((session) => {
            main_view.bind (session);
            root_stack.visible_child_name = "main";
        });
    }

    /* Debug aid for server-side failures: one toast whose "Details" opens the
     * response dialog. Known limitation: while an Adw.Dialog is presented the
     * toast sits behind its scrim; the reporter keeps last_error, so the
     * details stay reachable after the dialog closes. */
    private void on_error_reported (ErrorDetails details) {
        if (error_toast != null) {
            error_toast.title = details.summary ();
            return;
        }
        var toast = new Adw.Toast (details.summary ()) {
            button_label = _("Details")
        };
        toast.button_clicked.connect (() => {
            var last = ErrorReporter.get_default ().last_error;
            if (last != null) {
                new ErrorDetailsDialog (last).present (this);
            }
        });
        toast.dismissed.connect (() => error_toast = null);
        error_toast = toast;
        toast_overlay.add_toast (toast);
    }

#if ANDROID
    /* Android system-back handler (wired only there). Back walks the UI from the
     * inside out: close a presented dialog first, else step the visible screen's
     * navigation, and only when nothing is left to go back to do we treat it as
     * leaving — and then confirm rather than dropping the user out of the app.
     * Always returns true: we either consumed the back or drive the quit
     * ourselves via the confirmation, so the window never closes implicitly. */
    private bool on_close_request () {
        var dialog = get_visible_dialog ();
        if (dialog != null) {
            dialog.close ();
            return true;
        }

        bool consumed = false;
        switch (root_stack.visible_child_name) {
            case "main":       consumed = main_view.handle_back (); break;
            case "onboarding": consumed = onboarding.handle_back (); break;
            default:           break;   // loading: nothing to pop
        }
        if (consumed) {
            return true;
        }

        confirm_quit ();
        return true;
    }

    /* The root-level "closing check": don't let a single back silently kill the
     * app — ask first. The dialog itself lives in window.blp; we just present it
     * (its response is wired once in the constructor). */
    private void confirm_quit () {
        quit_dialog.present (this);
    }
#endif
}
