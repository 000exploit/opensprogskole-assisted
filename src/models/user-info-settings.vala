/* user-info-settings.vala
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

    /* GetUserInfoSettings: which UserInfoItem fields this school lets the student
     * edit, plus whether self-uploaded profile pictures ("selfies") are enabled.
     * The profile page reads these to show/hide rows and to gate the edit form —
     * a school may forbid editing some or all fields. As elsewhere, the
     * PascalCase -> snake_case mapping comes for free from Entity. */
    public class UserInfoSettings : Entity {

        public bool work_phone_allow_edit { get; set; default = false; }
        public bool work_mobile_phone_allow_edit { get; set; default = false; }
        public bool phone_number_allow_edit { get; set; default = false; }
        public bool private_mobile_phone_allow_edit { get; set; default = false; }
        public bool private_mail_allow_edit { get; set; default = false; }
        public bool work_mail_allow_edit { get; set; default = false; }
        public bool picture_privacy_setting_allow_edit { get; set; default = false; }
        public bool never_receive_sms_allow_edit { get; set; default = false; }
        public bool selfie_enabled { get; set; default = false; }

        // Not in every backend's response; absent -> stays false -> row hidden.
        public bool other_info_allow_edit { get; set; default = false; }

        /* True when at least one editable field exists, i.e. the "Edit" entry is
         * worth offering at all. */
        public bool any_editable {
            get {
                return work_phone_allow_edit || work_mobile_phone_allow_edit
                    || phone_number_allow_edit || private_mobile_phone_allow_edit
                    || private_mail_allow_edit || work_mail_allow_edit
                    || other_info_allow_edit;
            }
        }
    }
}
