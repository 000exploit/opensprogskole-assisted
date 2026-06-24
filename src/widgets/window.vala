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

    [GtkChild] private unowned Gtk.Stack root_stack;
    [GtkChild] private unowned OnboardingView onboarding;
    [GtkChild] private unowned MainView main_view;

    private SessionController controller;

    public Window (Gtk.Application app, SessionController controller) {
        Object (application: app);
        this.controller = controller;

        // User intents → controller.
        onboarding.authenticate_request.connect ((school, username, password, save) => {
            onboarding.set_busy (true);
            controller.try_login.begin (school, username, password, save);
        });
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
        controller.login_succeeded.connect (() => {
            onboarding.set_busy (false);
            onboarding.login_succeeded ();
        });
        controller.authenticated.connect ((session) => {
            main_view.bind (session);
            root_stack.visible_child_name = "main";
        });
    }
}
