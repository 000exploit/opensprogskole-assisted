/* application.vala
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

public class Opensprogskole.Application : Adw.Application {

    private SessionController controller;

    public Application () {
        Object (
            application_id: "moe.ekusu.sprogskole",
            flags: ApplicationFlags.DEFAULT_FLAGS,
            resource_base_path: "/moe/ekusu/sprogskole"
        );
    }

    construct {
        ActionEntry[] action_entries = {
            { "about", this.on_about_action },
            { "preferences", this.on_preferences_action },
            { "logout", this.on_logout_action },
            { "quit", this.quit }
        };
        this.add_action_entries (action_entries, this);
        this.set_accels_for_action ("app.quit", {"<control>q"});

        controller = new SessionController ();
    }

    public override void activate () {
        base.activate ();
        if (this.active_window == null) {
            // LoadingState is referenced only from .ui templates, so nothing
            // else pulls in its GType; register it before any template that
            // embeds it is built, or GtkBuilder can't resolve it by name.
            typeof (LoadingState).name ();
            new Opensprogskole.Window (this, controller).present ();
            controller.start ();   // drive the initial screen once the window listens
        } else {
            this.active_window.present ();
        }
    }

    private void on_about_action () {
        string[] developers = { "000exploit" };
        var about = new Adw.AboutDialog () {
            application_name = "OpenSprogskole",
            application_icon = "moe.ekusu.sprogskole",
            developer_name = "000exploit",
            translator_credits = _("translator-credits"),
            version = "0.5.0",
            developers = developers,
            copyright = "© 2026 000exploit",
        };

        about.present (this.active_window);
    }

    private void on_preferences_action () {
        message ("app.preferences action activated");
    }

    private void on_logout_action () {
        controller.logout ();
    }
}
