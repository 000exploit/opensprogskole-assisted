/* SyncInit.java
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

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.work.Constraints;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;

import java.util.concurrent.TimeUnit;

/**
 * Keeps {@link SyncWorker} scheduled. A ContentProvider for the same reason
 * as pixiewood's LocaleEnvProvider: Android instantiates providers at every
 * process start, so the schedule re-asserts itself without anyone having to
 * open the app. The enqueue is posted to the main looper because provider
 * onCreate runs before Application.onCreate — WorkManager's own initializer
 * may not be ready yet, the posted runnable runs safely after both.
 *
 * The interval is deliberately coarse and fixed: whether to sync at all (and
 * how eagerly the native side works) is governed by the in-app preferences —
 * opensprogskole_worker_sync() no-ops when background sync is off. KEEP
 * preserves the running schedule across restarts instead of resetting it.
 */
public final class SyncInit extends ContentProvider {
	static final String WORK_NAME = "cache-sync";
	static final long INTERVAL_HOURS = 6;

	@Override
	public boolean onCreate() {
		final android.content.Context context = getContext().getApplicationContext();
		new Handler(Looper.getMainLooper()).post(() -> {
			PeriodicWorkRequest request = new PeriodicWorkRequest.Builder(
					SyncWorker.class, INTERVAL_HOURS, TimeUnit.HOURS)
				.setConstraints(new Constraints.Builder()
					.setRequiredNetworkType(NetworkType.CONNECTED)
					.build())
				.build();
			WorkManager.getInstance(context).enqueueUniquePeriodicWork(
					WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request);
		});
		return true;
	}

	// The mandatory ContentProvider surface; this provider serves no data.
	@Override
	public @Nullable Cursor query(@NonNull Uri uri, @Nullable String[] projection,
			@Nullable String selection, @Nullable String[] selectionArgs,
			@Nullable String sortOrder) {
		return null;
	}

	@Override
	public @Nullable String getType(@NonNull Uri uri) {
		return null;
	}

	@Override
	public @Nullable Uri insert(@NonNull Uri uri, @Nullable ContentValues values) {
		return null;
	}

	@Override
	public int delete(@NonNull Uri uri, @Nullable String selection,
			@Nullable String[] selectionArgs) {
		return 0;
	}

	@Override
	public int update(@NonNull Uri uri, @Nullable ContentValues values,
			@Nullable String selection, @Nullable String[] selectionArgs) {
		return 0;
	}
}
