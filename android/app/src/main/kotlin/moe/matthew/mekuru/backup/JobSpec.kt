package moe.matthew.mekuru.backup

import org.json.JSONObject

/**
 * Everything a job needs to run, or resume, without the Flutter side:
 * persisted as `job.json` the moment the job is committed.
 *
 * Export: [displayName] is the final file name; [treeUri] the SAF folder (or
 * [targetPath] a plain path for tests and fallbacks); [docUri] the `.partial`
 * document created at commit. Restore: [sourceUri] the archive (a
 * `content://` or `file://` URI), [stagingPath] where it is unpacked,
 * [folders] the archive's zip-prefix to device-directory map and
 * [manifestJson] the text that becomes the EXTRACTED marker.
 */
data class JobSpec(
    val kind: String,
    val displayName: String? = null,
    val treeUri: String? = null,
    val targetPath: String? = null,
    val docUri: String? = null,
    val sourceUri: String? = null,
    val stagingPath: String? = null,
    val totalBytes: Long = 0L,
    val folders: Map<String, String> = emptyMap(),
    val manifestJson: String? = null,
) {
    val isExport: Boolean get() = kind == KIND_EXPORT

    fun toJson(): JSONObject = JSONObject()
        .put("kind", kind)
        .putOpt("displayName", displayName)
        .putOpt("treeUri", treeUri)
        .putOpt("targetPath", targetPath)
        .putOpt("docUri", docUri)
        .putOpt("sourceUri", sourceUri)
        .putOpt("stagingPath", stagingPath)
        .put("totalBytes", totalBytes)
        .put("folders", JSONObject(folders))
        .putOpt("manifestJson", manifestJson)

    companion object {
        const val KIND_EXPORT = "export"
        const val KIND_RESTORE = "restore"

        fun fromJson(json: JSONObject): JobSpec {
            val folders = LinkedHashMap<String, String>()
            json.optJSONObject("folders")?.let { obj ->
                for (key in obj.keys()) folders[key] = obj.getString(key)
            }
            return JobSpec(
                kind = json.getString("kind"),
                displayName = json.text("displayName"),
                treeUri = json.text("treeUri"),
                targetPath = json.text("targetPath"),
                docUri = json.text("docUri"),
                sourceUri = json.text("sourceUri"),
                stagingPath = json.text("stagingPath"),
                totalBytes = json.optLong("totalBytes", 0L),
                folders = folders,
                manifestJson = json.text("manifestJson"),
            )
        }

        /**
         * A string value, or null when absent, JSON null or empty. Android's
         * org.json renders JSONObject.NULL as the string "null" in optString,
         * which is how a `treeUri: null` from Dart once became a tree URI.
         */
        private fun JSONObject.text(key: String): String? =
            if (!has(key) || isNull(key)) null else optString(key).ifEmpty { null }
    }
}
