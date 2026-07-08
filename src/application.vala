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
        // HANDLES_OPEN: the OIDC redirect (dk.eg.ludus.mobile://login-callback)
        // reaches us as an "open this URI" request, routed to the running
        // instance since we stay single-instance (see open()).
        var app_flags = ApplicationFlags.HANDLES_OPEN;
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

    public override void shutdown () {
        // A cache write may still sit in its debounce window; put it on disk
        // before the process goes away.
        Storage.flush_all ();
        base.shutdown ();
    }

    /* Custom-scheme handler entry point. The OS hands us the OIDC redirect
     * URI(s) here; we route callbacks to the waiting LUDUS login and otherwise
     * just make sure a window exists. Any open request also implies the app
     * should be running, so fall back to activate()'s window bootstrap. */
    public override void open (GLib.File[] files, string hint) {
        if (this.active_window == null) {
            activate ();
        }
        foreach (var file in files) {
            string uri = file.get_uri ();
            if (OidcCallbackRouter.is_callback (uri)) {
                OidcCallbackRouter.get_default ().deliver (uri);
            }
        }
        if (this.active_window != null) {
            this.active_window.present ();
        }
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

    /* Built from the metainfo (bundled as a resource), so the name, license,
     * website, issue tracker and release notes can never drift from the
     * AppStream listing. Only what the metainfo can't carry is set here:
     * credits, third-party legal sections and the debug snapshot. */
    private void on_about_action () {
        var about = new Adw.AboutDialog.from_appdata (
            resource_base_path + "/" + Config.APP_ID + ".metainfo.xml",
            Config.PACKAGE_VERSION);

        about.developers = { "000exploit" };
        about.designers = { "000exploit" };
        about.translator_credits = _("translator-credits");
        about.copyright = "© 2026 000exploit";
        about.comments = _("View your schedule, grades and homework, and report absence at your Danish language school.\n\nThis app is not affiliated with Sprogcenter Midt or Inlogic.");

        // The school and its backend vendor; a LUDUS link joins these once
        // LUDUS sign-in actually works.
        about.add_link (_("Sprogcenter Midt"), "https://sprogcentermidt.dk");
        about.add_link (_("UMS by Inlogic"), "https://inlogic.dk");

        // Vendored/adapted third-party code. GVDB is statically built in;
        // main.vala and window.vala carry snippets adapted from Tuba.
        about.add_legal_section ("GVDB", "© GVDB contributors",
                                 Gtk.License.LGPL_2_1, null);
        about.add_legal_section (_("Portions adapted from Tuba"),
                                 "© Evangelos “GeopJr” Paterakis",
                                 Gtk.License.GPL_3_0, null);

        about.add_acknowledgement_section (null, {
            "Evangelos “GeopJr” Paterakis (Tuba) https://github.com/GeopJr/Tuba",
            "sp1rit (pixiewood) https://github.com/sp1ritCS/gtk-android-builder",
            "The GNOME Project https://www.gnome.org",
            "Claude (Anthropic) https://claude.com",
        });

#if ANDROID
        // The APK bundles the platform stack a desktop OS would provide as
        // shared libraries; the notice-requiring licenses get a section.
        about.add_legal_section ("OpenSSL", null, Gtk.License.APACHE_2_0, null);
        about.add_legal_section (_("Bundled GNOME platform libraries"),
                                 "GLib, GTK, libadwaita, libsoup, glib-networking, libsecret",
                                 Gtk.License.LGPL_2_1, null);
#endif

        about.debug_info = debug_info ();
        about.debug_info_filename = "opensprogskole-debug.txt";

        about.present (this.active_window);
    }

    /* A copy-pasteable environment snapshot for bug reports, shown on the About
     * dialog's troubleshooting page. */
    private string debug_info () {
        return "OpenSprogskole %s\nGTK %u.%u.%u\nlibadwaita %u.%u.%u\nlibsoup %u.%u.%u\nOS: %s\n".printf (
            Config.PACKAGE_VERSION,
            Gtk.get_major_version (), Gtk.get_minor_version (), Gtk.get_micro_version (),
            Adw.get_major_version (), Adw.get_minor_version (), Adw.get_micro_version (),
            Soup.get_major_version (), Soup.get_minor_version (), Soup.get_micro_version (),
            Environment.get_os_info (GLib.OsInfoKey.PRETTY_NAME) ?? "unknown");
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
