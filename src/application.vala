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
    private GLib.Settings settings;

    public Application () {
#if ANDROID
        var app_flags = ApplicationFlags.NON_UNIQUE;
#else
        var app_flags = ApplicationFlags.DEFAULT_FLAGS;
#endif
        Object (
            application_id: "moe.ekusu.sprogskole",
            flags: app_flags,
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
        this.set_accels_for_action ("app.preferences", {"<control>comma"});

        settings = new GLib.Settings (Config.APP_ID);
        controller = new SessionController ();
    }

    // The accent override (null = following the system accent).
    private Gtk.CssProvider? accent_provider = null;

    public override void startup () {
        base.startup ();
        // Apply the local appearance preferences app-wide (defaults = follow
        // system); reapply live when they change from the Preferences dialog.
        apply_color_scheme ();
        apply_accent ();
        settings.changed["color-scheme"].connect (apply_color_scheme);
        settings.changed["accent-color"].connect (apply_accent);
        // The standalone accent differs between light/dark, so re-derive it when
        // the effective scheme flips (system change or our own override).
        Adw.StyleManager.get_default ().notify["dark"].connect (apply_accent);
    }

    private void apply_color_scheme () {
        Adw.ColorScheme scheme;
        switch (settings.get_int ("color-scheme")) {
            case 1:  scheme = Adw.ColorScheme.FORCE_LIGHT; break;
            case 2:  scheme = Adw.ColorScheme.FORCE_DARK;  break;
            default: scheme = Adw.ColorScheme.DEFAULT;     break;
        }
        Adw.StyleManager.get_default ().color_scheme = scheme;
    }

    /* AdwStyleManager's accent is read-only (system-driven), so an override is a
     * CSS provider redefining the accent named-colors. 0 = follow system (drop
     * the override); 1–9 map to AdwAccentColor. */
    private void apply_accent () {
        var display = Gdk.Display.get_default ();
        if (display == null) {
            return;
        }
        if (accent_provider != null) {
            Gtk.StyleContext.remove_provider_for_display (display, accent_provider);
            accent_provider = null;
        }
        int choice = settings.get_int ("accent-color");
        if (choice <= 0) {
            return;   // follow system
        }
        var accent = (Adw.AccentColor) (choice - 1);
        bool dark = Adw.StyleManager.get_default ().dark;
        string css =
            "@define-color accent_bg_color %s;\n".printf (accent.to_rgba ().to_string ()) +
            "@define-color accent_color %s;\n".printf (accent.to_standalone_rgba (dark).to_string ()) +
            "@define-color accent_fg_color #ffffff;\n";
        accent_provider = new Gtk.CssProvider ();
        accent_provider.load_from_string (css);
        Gtk.StyleContext.add_provider_for_display (display, accent_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
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
            version = "0.9.9",
            developers = developers,
            copyright = "© 2026 000exploit",
        };

        about.present (this.active_window);
    }

    private void on_preferences_action () {
        // Pass the school's own week-start so "Use school default" can show what
        // it resolves to; fall back to Monday before any session exists.
        int school_weekday = controller.session != null
            ? controller.session.school.first_weekday : 1;
        new PreferencesDialog (settings, school_weekday).present (this.active_window);
    }

    private void on_logout_action () {
        controller.logout ();
    }
}
