/* android-glue.c
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

#include "android-glue.h"

#include <jni.h>
#include <gdk/android/gdkandroid.h>

/* Resolve the JNIEnv (valid on the GTK thread, which is where all of this
 * runs) and the bound Activity for a toplevel surface. NULL when the surface
 * is not an android toplevel or no activity has attached to it yet — mapped
 * windows always have one, so hook these off ::map or later. */
static JNIEnv *
glue_env_and_activity (GdkSurface *surface, jobject *activity)
{
  if (!GDK_IS_ANDROID_TOPLEVEL (surface))
    return NULL;
  *activity = gdk_android_toplevel_get_activity (GDK_ANDROID_TOPLEVEL (surface));
  if (*activity == NULL)
    return NULL;
  return gdk_android_display_get_env (gdk_surface_get_display (surface));
}

gboolean
opensprogskole_android_notifications_enabled (GdkSurface *surface)
{
  jobject activity;
  JNIEnv *env = glue_env_and_activity (surface, &activity);
  if (env == NULL)
    return FALSE;

  (*env)->PushLocalFrame (env, 8);

  // Context.getSystemService(Context.NOTIFICATION_SERVICE)
  jclass context_class = (*env)->GetObjectClass (env, activity);
  jmethodID get_service = (*env)->GetMethodID (env, context_class,
      "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;");
  jstring service = (*env)->NewStringUTF (env, "notification");
  jobject manager = (*env)->CallObjectMethod (env, activity, get_service, service);

  jboolean enabled = JNI_FALSE;
  if (manager != NULL)
    {
      jclass manager_class = (*env)->GetObjectClass (env, manager);
      jmethodID are_enabled = (*env)->GetMethodID (env, manager_class,
          "areNotificationsEnabled", "()Z");
      enabled = (*env)->CallBooleanMethod (env, manager, are_enabled);
    }

  if ((*env)->ExceptionCheck (env))
    {
      (*env)->ExceptionClear (env);
      enabled = JNI_FALSE;
    }
  (*env)->PopLocalFrame (env, NULL);
  return enabled == JNI_TRUE;
}

void
opensprogskole_android_request_notifications (GdkSurface *surface)
{
  jobject activity;
  JNIEnv *env = glue_env_and_activity (surface, &activity);
  if (env == NULL)
    return;

  (*env)->PushLocalFrame (env, 8);

  // POST_NOTIFICATIONS only exists on API 33+; on older releases posting
  // needs no permission, so there is nothing to ask for.
  jclass version_class = (*env)->FindClass (env, "android/os/Build$VERSION");
  jint sdk = (*env)->GetStaticIntField (env, version_class,
      (*env)->GetStaticFieldID (env, version_class, "SDK_INT", "I"));
  if (sdk >= 33)
    {
      jclass string_class = (*env)->FindClass (env, "java/lang/String");
      jobjectArray permissions = (*env)->NewObjectArray (env, 1, string_class,
          (*env)->NewStringUTF (env, "android.permission.POST_NOTIFICATIONS"));
      jclass activity_class = (*env)->GetObjectClass (env, activity);
      jmethodID request = (*env)->GetMethodID (env, activity_class,
          "requestPermissions", "([Ljava/lang/String;I)V");
      // The code only matters to onRequestPermissionsResult, which nothing
      // listens to (state is re-queried instead); any small value works.
      (*env)->CallVoidMethod (env, activity, request, permissions, (jint) 47);
    }

  if ((*env)->ExceptionCheck (env))
    (*env)->ExceptionClear (env);
  (*env)->PopLocalFrame (env, NULL);
}
