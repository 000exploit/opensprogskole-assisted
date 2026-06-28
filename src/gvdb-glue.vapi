/* gvdb-glue.vapi — Vala binding for the GVDB C glue (gvdb-glue.h).
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

[CCode (cheader_filename = "gvdb-glue.h")]
namespace Gvdb {

    /* Persist a string -> Variant map to a GVDB file. */
    [CCode (cname = "opensprogskole_gvdb_write")]
    public bool write (string path, GLib.HashTable<string, GLib.Variant> values) throws GLib.Error;

    /* Read a GVDB blob back into a string -> Variant map (owned by the caller). */
    [CCode (cname = "opensprogskole_gvdb_read")]
    public GLib.HashTable<string, GLib.Variant> read (GLib.Bytes bytes) throws GLib.Error;
}
