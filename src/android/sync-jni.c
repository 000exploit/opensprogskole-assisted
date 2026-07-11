/* sync-jni.c
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

/* The one JNI symbol the WorkManager side needs: SyncWorker.nativeSync()
 * (android/java/moe/ekusu/sprogskole/SyncWorker.java) resolves to this after
 * its System.loadLibrary. Runs on the worker's own thread — the handshake
 * with the GTK thread lives in worker_sync (src/services/sync-runner.vala). */

#include <jni.h>

extern int opensprogskole_worker_sync (void);

JNIEXPORT jint JNICALL
Java_moe_ekusu_sprogskole_SyncWorker_nativeSync (JNIEnv *env, jclass klass)
{
  (void) env;
  (void) klass;
  return opensprogskole_worker_sync ();
}
