/* user-info-item.vala
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

    /* The signed-in user's profile, mirroring the backend's UserInfoItem.
     *
     * Like every model it just extends Entity and declares snake_case
     * properties; the PascalCase mapping and ISO 8601 -> DateTime parsing come
     * for free. The .NET UserType enum is sent as an integer, so it is kept as
     * an int here (cast to your own enum when you add one). */
    public class UserInfoItem : Entity {

        // Contact
        public string work_phone_number { get; set; default = ""; }
        public string work_mobile_phone { get; set; default = ""; }
        public string work_mail { get; set; default = ""; }
        public string mobile_phone { get; set; default = ""; }
        public string phone_number { get; set; default = ""; }
        public string private_mobile_phone { get; set; default = ""; }
        public string private_mail { get; set; default = ""; }

        // Pictures
        public string picture_url { get; set; default = ""; }
        public string pending_picture_url { get; set; default = ""; }
        public string approved_picture_url { get; set; default = ""; }
        public string picture_url_small { get; set; default = ""; }
        public string picture_url_medium { get; set; default = ""; }
        public string picture_url_large { get; set; default = ""; }

        // Identity
        public string other_info { get; set; default = ""; }
        public string username { get; set; default = ""; }
        public string domain { get; set; default = ""; }
        public string first_name { get; set; default = ""; }
        public string last_name { get; set; default = ""; }
        public string uni_login { get; set; default = ""; }
        public string card_id { get; set; default = ""; }

        // Address
        public string address { get; set; default = ""; }
        public string place { get; set; default = ""; }
        public string zip_code { get; set; default = ""; }
        public string city { get; set; default = ""; }

        // School / employment
        public string employee_degree { get; set; default = ""; }
        public string department_name { get; set; default = ""; }
        public string internship_category_code { get; set; default = ""; }
        public string school_community_home_room_number { get; set; default = ""; }

        public string birth_day { get; set; default = ""; }
        public bool never_receive_sms { get; set; default = false; }
        public int picture_privacy_setting { get; set; default = 0; }
        public int user_type { get; set; default = 0; }   // UMS UserTypes enum
        public int language_id { get; set; default = 0; }

        // Dates (parsed by Entity)
        public DateTime? start_date_time { get; set; }
        public DateTime? end_date_time { get; set; }
        public DateTime? school_community_home_start_date_time { get; set; }
        public DateTime? school_community_home_end_date_time { get; set; }
        public DateTime? verified_date { get; set; }

        /* "First Last", trimmed. */
        public string full_name {
            owned get {
                return "%s %s".printf (first_name, last_name).strip ();
            }
        }
    }
}
