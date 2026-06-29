/* main.vala
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

/* Took from GeopJr/Tuba */
#if ANDROID
    [CCode (cname = "g_io_openssl_load")]
    extern void g_io_openssl_load (GLib.IOModule? module);
#endif

int main (string[] args) {
    Intl.bindtextdomain (Config.GETTEXT_PACKAGE, Config.LOCALEDIR);
    Intl.bind_textdomain_codeset (Config.GETTEXT_PACKAGE, "UTF-8");
    Intl.textdomain (Config.GETTEXT_PACKAGE);

    /* Took from GeopJr/Tuba entirely */
	#if WINDOWS || DARWIN || HAIKU || ANDROID
		GLib.Environment.set_variable ("SECRET_BACKEND", "file", false);
		if (GLib.Environment.get_variable ("SECRET_BACKEND") == "file")
			GLib.Environment.set_variable ("SECRET_FILE_TEST_PASSWORD", @"$(GLib.Environment.get_user_name ())$(Config.APP_ID)", false);
	#endif
		#if ANDROID
		#if ANDROID_x86_64
			string arch = "x86_64";
		#else
			string arch = "aarch64";
		#endif
		string files_dir = @"/data/data/$(Config.APP_ID)/files";
		GLib.Environment.set_variable ("GIO_EXTRA_MODULES", @"$(files_dir)/lib/$(arch)/gio/modules", true);
		GLib.IOModule.scan_all_in_directory (@"$(files_dir)/lib/$(arch)/gio/modules");
		GLib.Environment.set_variable ("GSETTINGS_SCHEMA_DIR",
			@"$(files_dir)/share/glib-2.0/schemas", true);

		// See https://gitlab.gnome.org/GNOME/gtk/-/work_items/7704
		GLib.Environment.set_variable ("XDG_CACHE_HOME",
			@"/data/data/$(Config.APP_ID)/cache", true);
		GLib.Environment.set_variable ("XDG_CONFIG_HOME", @"$(files_dir)/config", true);
		GLib.Environment.set_variable ("XDG_DATA_HOME", @"$(files_dir)/data", true);

        g_io_openssl_load (null);
    #endif

    var app = new Opensprogskole.Application ();
    return app.run (args);
}
