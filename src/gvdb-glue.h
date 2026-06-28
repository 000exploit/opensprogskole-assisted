/* gvdb-glue.h
 *
 * Copyright 2026 000exploit
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Thin glue over the vendored GVDB copylib so Vala can persist/read a plain
 * GHashTable<char*, GVariant*> without touching GVDB's opaque builder types.
 */

#pragma once

#include <glib.h>

G_BEGIN_DECLS

/* Write `values` (keys: char*, values: GVariant*) to a GVDB file at `path`.
 * Returns FALSE and sets `error` on failure. */
gboolean opensprogskole_gvdb_write (const char *path, GHashTable *values, GError **error);

/* Read a GVDB blob into a new GHashTable<char*, GVariant*> (caller owns it,
 * keys g_free'd, values g_variant_unref'd). NULL + `error` on failure. */
GHashTable *opensprogskole_gvdb_read (GBytes *bytes, GError **error);

G_END_DECLS
