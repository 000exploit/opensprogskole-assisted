/* preferences-dialog.vala
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

using Gtk;

namespace Opensprogskole {

    /* Local, instant, reversible app preferences (no account/server settings —
     * those live on the profile page). Writes straight to GSettings; the
     * Application applies color-scheme, and ScheduleView reads first-weekday. */
    [GtkTemplate (ui = "/moe/ekusu/sprogskole/ui/preferences-dialog.ui")]
    public class PreferencesDialog : Adw.PreferencesDialog {

        [GtkChild] private unowned Adw.ComboRow color_scheme_row;
        [GtkChild] private unowned Adw.ComboRow accent_color_row;
        [GtkChild] private unowned Adw.ComboRow first_weekday_row;
        [GtkChild] private unowned Label cache_size_label;
        [GtkChild] private unowned Button clear_button;

        private GLib.Settings settings;
        // The school's own week-start, so "Use school default" can show what it
        // resolves to ("Currently Monday").
        private int school_weekday;

        // "First day of week" combo index → stored ISO weekday (0 = use school
        // default, 1 = Monday … 7 = Sunday). The combo lists the common choices.
        private const int[] WEEKDAY_VALUES = { 0, 1, 7, 6 };

        public PreferencesDialog (GLib.Settings settings, int school_first_weekday) {
            this.settings = settings;
            this.school_weekday = school_first_weekday;

            color_scheme_row.model = new StringList ({
                _("Follow system"), _("Light"), _("Dark") });
            first_weekday_row.model = new StringList ({
                _("Use school default"), _("Monday"), _("Sunday"), _("Saturday") });

            // Color scheme: the combo index is the stored value (0/1/2).
            color_scheme_row.selected = settings.get_int ("color-scheme");
            color_scheme_row.notify["selected"].connect (() => {
                settings.set_int ("color-scheme", (int) color_scheme_row.selected);
            });

            // Accent: index 0 = follow system, 1–9 = AdwAccentColor. Index is the
            // stored value; Application applies it via a CSS override.
            accent_color_row.model = new StringList ({
                _("Follow system"), _("Blue"), _("Teal"), _("Green"), _("Yellow"),
                _("Orange"), _("Red"), _("Pink"), _("Purple"), _("Slate")
            });
            accent_color_row.selected = settings.get_int ("accent-color");
            accent_color_row.notify["selected"].connect (() => {
                settings.set_int ("accent-color", (int) accent_color_row.selected);
            });

            // First weekday: index ≠ stored value, so map both directions.
            first_weekday_row.selected = index_for_weekday (settings.get_int ("first-weekday"));
            first_weekday_row.notify["selected"].connect (() => {
                settings.set_int ("first-weekday", WEEKDAY_VALUES[first_weekday_row.selected]);
                update_weekday_subtitle ();
            });
            update_weekday_subtitle ();

            clear_button.clicked.connect (on_clear);
            refresh_cache_size ();
        }

        private int index_for_weekday (int value) {
            for (int i = 0; i < WEEKDAY_VALUES.length; i++) {
                if (WEEKDAY_VALUES[i] == value) {
                    return i;
                }
            }
            return 0;
        }

        /* The effective week start (override, or the school default when "use
         * school default" is selected), shown so the default isn't a mystery. */
        private void update_weekday_subtitle () {
            int eff = WEEKDAY_VALUES[first_weekday_row.selected];
            if (eff == 0) {
                eff = school_weekday;
            }
            first_weekday_row.subtitle = _("Currently %s").printf (weekday_name (eff));
        }

        private string weekday_name (int iso) {
            switch (iso) {
                case 1:  return _("Monday");
                case 2:  return _("Tuesday");
                case 3:  return _("Wednesday");
                case 4:  return _("Thursday");
                case 5:  return _("Friday");
                case 6:  return _("Saturday");
                default: return _("Sunday");
            }
        }

        private void refresh_cache_size () {
            cache_size_label.label = GLib.format_size ((uint64) Storage.total_size ());
        }

        /* Clearing is safe (re-downloads on demand), so no confirmation — just a
         * toast, per HIG. */
        private void on_clear () {
            Storage.clear_all ();
            AvatarCache.clear_all ();
            refresh_cache_size ();
            add_toast (new Adw.Toast (_("Cached data cleared")));
        }
    }
}
