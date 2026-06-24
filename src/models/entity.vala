/*
 * Entity — base class for JSON-backed models.
 *
 * Implements Json.Serializable so that Json.gobject_deserialize() handles
 * the UMS API's PascalCase JSON ↔ Vala's snake_case properties transparently,
 * plus DateTime ⇄ ISO 8601 strings.
 *
 * Defining a model becomes:
 *
 *     public class TimetableItem : Entity {
 *         public string subject { get; set; default = ""; }
 *         public DateTime time_table_real_start_date_time { get; set; }
 *         // ...
 *     }
 *
 * Parsing (transparent, inbound):
 *
 *     var parser = new Json.Parser();
 *     parser.load_from_data(json_text);
 *     var item = (TimetableItem) Json.gobject_deserialize(
 *         typeof(TimetableItem), parser.get_root());
 *
 * Limitations to know:
 *
 *  - Nested object properties must themselves extend Entity (so their own
 *    deserialize_property runs). For arrays of objects, iterate the
 *    Json.Array yourself and call Json.gobject_deserialize per element —
 *    json-glib does not recurse into collections of GObjects automatically.
 *
 *  - C# enums round-trip as integers; the deserializer leaves them as int.
 *    Declare such fields as int and cast to your Vala enum type when reading.
 *
 *  - DateTime serialization out uses "YYYY-MM-DDTHH:MM:SS" with NO timezone,
 *    to match what the UMS server emits. format_iso8601() would add an
 *    offset which may or may not be accepted.
 *
 *  - The OUTBOUND path (Json.gobject_serialize) emits kebab-case keys, which
 *    UMS does not accept. For endpoints that send model JSON (UpdateHomework
 *    is the only one in this client), hand-build a Json.Object with the
 *    PascalCase keys you actually need. The Entity.to_json_string helper
 *    below rewrites keys to PascalCase as a fallback, but it's noisy on the
 *    wire — defaults from every property get included.
 *
 *  - Local timezone is assumed for inbound DateTime parsing. UMS sends
 *    server-local time (Copenhagen). If you ever run the client in a
 *    different timezone you'll need a fixed TimeZone instead of local().
 */

namespace Opensprogskole {

    public abstract class Entity : Object, Json.Serializable {

        // -------------------------------------------------------------------
        // Inbound name mapping. JSON "TimeTableRealStartDateTime" -> GObject
        // property "time-table-real-start-date-time".
        // GObject.find_property accepts hyphens (canonical) and underscores;
        // we emit hyphens to be safe.
        // -------------------------------------------------------------------
        public virtual unowned ParamSpec? find_property (string name) {
            var prop_name = pascal_to_kebab (name);
            var ocl = (ObjectClass) get_type ().class_ref ();
            return ocl.find_property (prop_name);
        }

        // -------------------------------------------------------------------
        // Inbound value handling. Most types use the default; DateTime needs
        // ISO 8601 string parsing because GLib.DateTime is a GBoxed type the
        // default deserializer doesn't know how to populate.
        // -------------------------------------------------------------------
        public virtual bool deserialize_property (string property_name,
                                                  out Value @value,
                                                  ParamSpec pspec,
                                                  Json.Node property_node) {
            if (pspec.value_type == typeof (DateTime)) {
                @value = Value (typeof (DateTime));
                if (property_node.get_node_type () == Json.NodeType.NULL)
                    return true;

                var s = property_node.get_string ();
                if (s == null || s.length == 0)
                    return true;

                var tz = new TimeZone.local ();
                var dt = new DateTime.from_iso8601 (s, tz);
                if (dt != null)
                    @value.set_boxed (dt);
                return true;
            }
            return default_deserialize_property (property_name, out @value, pspec, property_node);
        }

        // -------------------------------------------------------------------
        // Outbound value handling. Emit DateTime as "YYYY-MM-DDTHH:MM:SS",
        // matching the no-timezone form System.Text.Json (and thus the UMS
        // server) uses for DateTime with Kind=Unspecified.
        // -------------------------------------------------------------------
        public virtual Json.Node serialize_property (string property_name,
                                                     Value @value,
                                                     ParamSpec pspec) {
            if (pspec.value_type == typeof (DateTime)) {
                var node = new Json.Node (Json.NodeType.VALUE);
                var dt = (DateTime?) @value.get_boxed ();
                node.set_string (dt == null ? "" : dt.format ("%Y-%m-%dT%H:%M:%S"));
                return node;
            }
            return default_serialize_property (property_name, @value, pspec);
        }

        // -------------------------------------------------------------------
        // Outbound serializer that REWRITES keys to PascalCase. Use only when
        // the server requires PascalCase (UMS does). Includes every property
        // with its current value — there's no [JsonIgnore] mechanism here;
        // for selective payloads, hand-build a Json.Object instead.
        // -------------------------------------------------------------------
        public string to_json_string () {
            var node = Json.gobject_serialize (this);
            var pascal = kebab_keys_to_pascal_obj (node.get_object ());

            var root = new Json.Node (Json.NodeType.OBJECT);
            root.set_object (pascal);

            var gen = new Json.Generator () { pretty = false };
            gen.set_root (root);
            return gen.to_data (null);
        }

        // -------------------------------------------------------------------
        // String helpers.
        // -------------------------------------------------------------------
        private static string pascal_to_kebab (string s) {
            var sb = new StringBuilder ();
            for (int i = 0; i < s.length; i++) {
                unichar c = s[i];
                if (c.isupper () && i > 0)
                    sb.append_c ('-');
                sb.append_unichar (c.tolower ());
            }
            return sb.str;
        }

        private static string kebab_to_pascal (string s) {
            var sb = new StringBuilder ();
            bool upper_next = true;
            for (int i = 0; i < s.length; i++) {
                unichar c = s[i];
                if (c == '-') { upper_next = true; continue; }
                sb.append_unichar (upper_next ? c.toupper () : c);
                upper_next = false;
            }
            return sb.str;
        }

        private static Json.Object kebab_keys_to_pascal_obj (Json.Object src) {
            var dst = new Json.Object ();
            src.foreach_member ((obj, key, val) => {
                dst.set_member (kebab_to_pascal (key), val);
            });
            return dst;
        }
    }
}
