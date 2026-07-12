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

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

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

	/**
	 * Implemented by src/android/sync-jni.c in libopensprogskole.so. Returns
	 * the news detected during the sync as a JSON array of {id,title,body}
	 * ("[]" when the sync succeeded quietly), or null on failure.
	 */
	private static native String nativeSync();

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
		String news = nativeSync();
		Log.i(TAG, "background sync finished; news: " + news);
		if (news == null) {
			// Transient states (not logged in yet, timeout) — let WorkManager
			// retry with its backoff rather than giving up.
			return Result.retry();
		}
		notifySynced();
		postNews(news);
		return Result.success();
	}

	private static final String CHANNEL_ID = "background-sync";
	private static final String NEWS_CHANNEL_ID = "news";
	private static final int NOTIFICATION_ID = 1;
	private static final int NEWS_NOTIFICATION_ID = 2;

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

	/**
	 * News the native side detected during this sync (new grades, scheduled
	 * exams — see NewsNotifier/PendingNotes). Unlike the silent sync marker,
	 * these ride a default-importance channel: they are the pings the user
	 * explicitly opted into (the native side already applied the preference
	 * gates, so everything arriving here is meant to be shown).
	 */
	private void postNews(String json) {
		android.content.Context context = getApplicationContext();
		if (Build.VERSION.SDK_INT >= 33
				&& context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
				   != PackageManager.PERMISSION_GRANTED) {
			return;
		}
		JSONArray notes;
		try {
			notes = new JSONArray(json);
		} catch (JSONException err) {
			Log.e(TAG, "unparseable news payload", err);
			return;
		}
		if (notes.length() == 0) {
			return;
		}
		NotificationManager manager = context.getSystemService(NotificationManager.class);
		manager.createNotificationChannel(new NotificationChannel(
				NEWS_CHANNEL_ID, context.getString(R.string.news_channel),
				NotificationManager.IMPORTANCE_DEFAULT));
		Intent launch = context.getPackageManager()
				.getLaunchIntentForPackage(context.getPackageName());
		for (int i = 0; i < notes.length(); i++) {
			JSONObject note = notes.optJSONObject(i);
			if (note == null)
				continue;
			Notification.Builder builder = new Notification.Builder(context, NEWS_CHANNEL_ID)
					.setSmallIcon(R.drawable.ic_launcher_monochrome)
					.setContentTitle(note.optString("title"))
					.setStyle(new Notification.BigTextStyle()
							.bigText(note.optString("body")))
					.setContentText(note.optString("body"))
					.setAutoCancel(true)
					.setShowWhen(true);
			if (launch != null) {
				builder.setContentIntent(PendingIntent.getActivity(
						context, 0, launch, PendingIntent.FLAG_IMMUTABLE));
			}
			// One slot per news kind ("new-grades"/"new-exams"): a newer ping
			// of the same kind replaces the older one instead of stacking.
			manager.notify(note.optString("id"), NEWS_NOTIFICATION_ID, builder.build());
		}
	}
}
