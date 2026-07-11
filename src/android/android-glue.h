/* android-glue.h
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

/* Android-only bridges into the platform APIs, callable from Vala through
 * src/android/android-glue.vapi. Everything takes the window's GdkSurface:
 * the JNIEnv and the Activity both hang off it (GdkAndroid public API). */

#pragma once

#include <gdk/gdk.h>
#include <glib.h>

G_BEGIN_DECLS

/* NotificationManager.areNotificationsEnabled() for our app: whether a posted
 * notification would actually show. FALSE also when the surface has no bound
 * activity (yet) — callers treat that as "can't tell, assume no". */
gboolean opensprogskole_android_notifications_enabled (GdkSurface *surface);

/* Show the system POST_NOTIFICATIONS permission dialog (API 33+; a no-op on
 * older releases where the permission doesn't exist). Fire-and-forget: there
 * is no result callback — re-query notifications_enabled() the next time it
 * matters. */
void opensprogskole_android_request_notifications (GdkSurface *surface);

G_END_DECLS
