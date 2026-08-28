using System.IO;
using System.Linq;

using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CKAN.Exporters
{
    /// <summary>
    /// Exports the installed modules as a JSON array, one object per module.
    ///
    /// Unlike <see cref="CkanExporter"/>, which emits an installable modpack
    /// (a .ckan metapackage), this emits the full metadata of each installed
    /// module for consumption by scripts and other tooling.
    /// </summary>
    public sealed class JsonExporter : IExporter
    {
        public void Export(RegistryManager  manager,
                           IRegistryQuerier registry,
                           Stream           stream)
        {
            var array = new JArray(registry.InstalledModules
                                           .OrderBy(im => im.Module.identifier)
                                           .Select(im => JObject.Parse(im.Module.ToJson())));

            using (var writer = new StreamWriter(stream, Encoding.UTF8, 4096, true))
            using (var jsonWriter = new JsonTextWriter(writer)
                                    {
                                        Formatting = Formatting.Indented,
                                        CloseOutput = false,
                                    })
            {
                array.WriteTo(jsonWriter);
                jsonWriter.Flush();
                writer.WriteLine();
            }
        }
    }
}
