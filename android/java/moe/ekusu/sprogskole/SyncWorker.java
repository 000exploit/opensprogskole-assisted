/* SyncWorker.java
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

package moe.ekusu.sprogskole;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

/**
 * Refreshes the app's offline cache in the background (scheduled by
 * {@link SyncInit}). No environment bootstrapping happens here on purpose:
 * GTK's RuntimeApplication boots the whole native app — assets, GLib loop,
 * silent login — at every process start, before any worker can run. All this
 * does is call across JNI into opensprogskole_worker_sync() (see
 * src/services/sync-runner.vala), which asks that resident app for one
 * complete sync and blocks until it lands.
 */
public final class SyncWorker extends Worker {
	private static final String TAG = "OpensprogskoleSync";

	public SyncWorker(@NonNull android.content.Context context, @NonNull WorkerParameters params) {
		super(context, params);
	}

	/** Implemented by src/android/sync-jni.c in libopensprogskole.so. */
	private static native int nativeSync();

	@Override
	public @NonNull Result doWork() {
		try {
			// Idempotent (the runtime glue already dlopened the library); this
			// registers it with the JVM so nativeSync() resolves.
			System.loadLibrary("opensprogskole");
		} catch (UnsatisfiedLinkError err) {
			Log.e(TAG, "native library unavailable", err);
			return Result.failure();
		}
		int status = nativeSync();
		Log.i(TAG, "background sync finished with status " + status);
		if (status == 0) {
			notifySynced();
		}
		// Non-zero covers transient states (not logged in yet, timeout) —
		// let WorkManager retry with its backoff rather than giving up.
		return status == 0 ? Result.success() : Result.retry();
	}

	private static final String CHANNEL_ID = "background-sync";
	private static final int NOTIFICATION_ID = 1;

	/**
	 * The silent "cache is fresh" marker: an IMPORTANCE_MIN notification (no
	 * sound, no heads-up, collapsed in the shade) whose timestamp doubles as
	 * "last synced". The fixed id replaces the previous one, so at most one is
	 * ever visible; the channel gives users a native off-switch. On API 33+
	 * this shows nothing until notifications are granted — the app has no
	 * runtime-permission prompt yet, so it must degrade to silence, not crash.
	 */
	private void notifySynced() {
		Context context = getApplicationContext();
		if (Build.VERSION.SDK_INT >= 33
				&& context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
				   != PackageManager.PERMISSION_GRANTED) {
			return;
		}
		NotificationManager manager = context.getSystemService(NotificationManager.class);
		manager.createNotificationChannel(new NotificationChannel(
				CHANNEL_ID, context.getString(R.string.sync_channel),
				NotificationManager.IMPORTANCE_MIN));

		Notification.Builder builder = new Notification.Builder(context, CHANNEL_ID)
				.setSmallIcon(R.drawable.ic_launcher_monochrome)
				.setContentTitle(context.getString(R.string.sync_done))
				.setShowWhen(true);
		Intent launch = context.getPackageManager()
				.getLaunchIntentForPackage(context.getPackageName());
		if (launch != null) {
			builder.setContentIntent(PendingIntent.getActivity(
					context, 0, launch, PendingIntent.FLAG_IMMUTABLE));
		}
		manager.notify(NOTIFICATION_ID, builder.build());
	}
}
