/* android-glue.vapi
 *
 * Vala bindings for src/android/android-glue.c — the Android-only platform
 * bridges. Only compiled into the android build (see src/meson.build); every
 * use site must sit behind `#if ANDROID`.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

[CCode (cheader_filename = "android/android-glue.h")]
namespace Opensprogskole.AndroidGlue {
	/* Whether a posted notification would actually show (false also while
	 * the surface has no bound activity yet — treat as "can't tell"). */
	[CCode (cname = "opensprogskole_android_notifications_enabled")]
	public bool notifications_enabled (Gdk.Surface surface);

	/* Show the system POST_NOTIFICATIONS dialog (no-op before API 33).
	 * Fire-and-forget; re-query notifications_enabled() when it matters. */
	[CCode (cname = "opensprogskole_android_request_notifications")]
	public void request_notifications (Gdk.Surface surface);
}
