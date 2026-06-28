/* gvdb-glue.c
 *
 * Copyright 2026 000exploit
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "gvdb-glue.h"

#include "gvdb/gvdb-builder.h"
#include "gvdb/gvdb-reader.h"

gboolean
opensprogskole_gvdb_write (const char *path, GHashTable *values, GError **error)
{
  GHashTable *root = gvdb_hash_table_new (NULL, NULL);

  GHashTableIter iter;
  gpointer key, value;
  g_hash_table_iter_init (&iter, values);
  while (g_hash_table_iter_next (&iter, &key, &value))
    {
      GvdbItem *item = gvdb_hash_table_insert (root, (const char *) key);
      gvdb_item_set_value (item, (GVariant *) value);
    }

  gboolean ok = gvdb_table_write_contents (root, path, FALSE, error);
  g_hash_table_unref (root);
  return ok;
}

GHashTable *
opensprogskole_gvdb_read (GBytes *bytes, GError **error)
{
  GvdbTable *table = gvdb_table_new_from_bytes (bytes, FALSE, error);
  if (table == NULL)
    return NULL;

  GHashTable *out = g_hash_table_new_full (g_str_hash, g_str_equal,
                                           g_free, (GDestroyNotify) g_variant_unref);

  gsize n_names = 0;
  gchar **names = gvdb_table_get_names (table, &n_names);
  for (gsize i = 0; i < n_names; i++)
    {
      GVariant *v = gvdb_table_get_value (table, names[i]);
      if (v != NULL)
        g_hash_table_insert (out, g_strdup (names[i]), v); /* transfers the ref */
      g_free (names[i]);
    }

  g_free (names);
  gvdb_table_free (table);
  return out;
}
