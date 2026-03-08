package moe.matthew.mekuru

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import androidx.core.content.ContextCompat
import com.ichi2.anki.FlashCardsContract
import com.ichi2.anki.api.AddContentApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val SAF_CHANNEL_NAME = "mekuru/android_saf"
        private const val ANKI_CHANNEL_NAME = "mekuru/ankidroid_native"
        private const val REQUEST_OPEN_DOCUMENT_TREE = 7312
    }

    private var pendingTreePickerResult: MethodChannel.Result? = null
    private var pendingPickedDocumentUri: Uri? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAF_CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                try {
                    handleSafMethodCall(call, result)
                } catch (e: Exception) {
                    result.error("saf_error", e.message, null)
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ANKI_CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                try {
                    handleAnkiMethodCall(call, result)
                } catch (e: Exception) {
                    result.error("anki_error", e.message, null)
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_OPEN_DOCUMENT_TREE) return

        val callback = pendingTreePickerResult
        val pickedDocumentUri = pendingPickedDocumentUri
        pendingTreePickerResult = null
        pendingPickedDocumentUri = null

        if (callback == null) return

        if (resultCode != Activity.RESULT_OK) {
            callback.success(null)
            return
        }

        val treeUri = data?.data
        if (treeUri == null) {
            callback.success(null)
            return
        }

        try {
            val intentFlags = data.flags
            val takeFlags =
                (intentFlags and Intent.FLAG_GRANT_READ_URI_PERMISSION) or
                    (intentFlags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            contentResolver.takePersistableUriPermission(
                treeUri,
                takeFlags or Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )

            val response = mutableMapOf<String, Any?>(
                "treeUri" to treeUri.toString(),
                "treeDocumentId" to safeGetTreeDocumentId(treeUri),
            )

            if (pickedDocumentUri != null) {
                response["selectedFileUri"] = pickedDocumentUri.toString()
                response["selectedFileDocumentId"] = safeGetDocumentId(pickedDocumentUri)

                val treeDocId = safeGetTreeDocumentId(treeUri)
                val fileDocId = safeGetDocumentId(pickedDocumentUri)
                response["selectedFileRelativePath"] = deriveRelativePath(treeDocId, fileDocId)
            }

            callback.success(response)
        } catch (e: Exception) {
            callback.error("saf_tree_access_failed", e.message, null)
        }
    }

    private fun handleSafMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickDirectory" -> {
                requestDirectoryAccess(null, result)
            }
            "requestDirectoryAccessForDocument" -> {
                val uriString = call.argument<String>("documentUri")
                if (uriString.isNullOrBlank()) {
                    result.error("bad_args", "documentUri is required", null)
                    return
                }
                requestDirectoryAccessForDocument(Uri.parse(uriString), result)
            }
            "readBytesFromUri" -> {
                val uriString = call.argument<String>("uri")
                if (uriString.isNullOrBlank()) {
                    result.error("bad_args", "uri is required", null)
                    return
                }
                runIo(result) {
                    readBytesFromUri(Uri.parse(uriString))
                }
            }
            "readTextFromUri" -> {
                val uriString = call.argument<String>("uri")
                if (uriString.isNullOrBlank()) {
                    result.error("bad_args", "uri is required", null)
                    return
                }
                runIo(result) {
                    readTextFromUri(Uri.parse(uriString))
                }
            }
            "readBytesFromTreePath" -> {
                val treeUri = call.argument<String>("treeUri")
                val relativePath = call.argument<String>("relativePath")
                if (treeUri.isNullOrBlank() || relativePath == null) {
                    result.error("bad_args", "treeUri and relativePath are required", null)
                    return
                }
                runIo(result) {
                    readBytesFromTreePath(Uri.parse(treeUri), relativePath)
                }
            }
            "readTextFromTreePath" -> {
                val treeUri = call.argument<String>("treeUri")
                val relativePath = call.argument<String>("relativePath")
                if (treeUri.isNullOrBlank() || relativePath == null) {
                    result.error("bad_args", "treeUri and relativePath are required", null)
                    return
                }
                runIo(result) {
                    readTextFromTreePath(Uri.parse(treeUri), relativePath)
                }
            }
            "existsInTreePath" -> {
                val treeUri = call.argument<String>("treeUri")
                val relativePath = call.argument<String>("relativePath")
                if (treeUri.isNullOrBlank() || relativePath == null) {
                    result.error("bad_args", "treeUri and relativePath are required", null)
                    return
                }
                runIo(result) {
                    existsInTreePath(Uri.parse(treeUri), relativePath)
                }
            }
            "listNamesInTreeDir" -> {
                val treeUri = call.argument<String>("treeUri")
                val relativePath = call.argument<String>("relativePath") ?: ""
                if (treeUri.isNullOrBlank()) {
                    result.error("bad_args", "treeUri is required", null)
                    return
                }
                runIo(result) {
                    listNamesInTreeDir(Uri.parse(treeUri), relativePath)
                }
            }
            "getDocumentUriInTree" -> {
                val treeUri = call.argument<String>("treeUri")
                val relativePath = call.argument<String>("relativePath")
                if (treeUri.isNullOrBlank() || relativePath == null) {
                    result.error("bad_args", "treeUri and relativePath are required", null)
                    return
                }
                val docUri = resolveTreeDocumentUri(Uri.parse(treeUri), relativePath)
                result.success(docUri?.toString())
            }
            else -> result.notImplemented()
        }
    }

    private fun handleAnkiMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasDuplicateInDeck" -> {
                val modelId = call.longArgument("modelId")
                val deckId = call.longArgument("deckId")
                val firstFieldValue = call.argument<String>("firstFieldValue")

                if (modelId == null || deckId == null || firstFieldValue.isNullOrBlank()) {
                    result.success(false)
                    return
                }

                runIo(result) {
                    hasDuplicateInDeck(
                        modelId = modelId,
                        deckId = deckId,
                        firstFieldValue = firstFieldValue,
                    )
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun runIo(
        result: MethodChannel.Result,
        task: () -> Any?,
    ) {
        Thread {
            try {
                val value = task()
                runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                runOnUiThread { result.error("saf_io_error", e.message, null) }
            }
        }.start()
    }

    private fun hasDuplicateInDeck(
        modelId: Long,
        deckId: Long,
        firstFieldValue: String,
    ): Boolean {
        if (!canQueryAnkiDuplicates()) return false

        val api = AddContentApi(applicationContext)
        val duplicates = api.findDuplicateNotes(modelId, firstFieldValue)
        if (duplicates.isEmpty()) return false

        return duplicates.any { noteInfo ->
            noteInfo != null && noteHasCardInDeck(noteInfo.getId(), deckId)
        }
    }

    private fun canQueryAnkiDuplicates(): Boolean {
        val provider = packageManager.resolveContentProvider(
            FlashCardsContract.AUTHORITY,
            PackageManager.GET_META_DATA,
        )
        if (provider == null) return false

        return ContextCompat.checkSelfPermission(
            applicationContext,
            AddContentApi.READ_WRITE_PERMISSION,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun noteHasCardInDeck(noteId: Long, deckId: Long): Boolean {
        val noteUri = Uri.withAppendedPath(
            FlashCardsContract.Note.CONTENT_URI,
            noteId.toString(),
        )
        val cardsUri = Uri.withAppendedPath(noteUri, "cards")
        val projection = arrayOf(FlashCardsContract.Card.DECK_ID)

        contentResolver.query(cardsUri, projection, null, null, null)?.use { cursor ->
            val deckIdIndex = cursor.getColumnIndex(FlashCardsContract.Card.DECK_ID)
            while (cursor.moveToNext()) {
                if (deckIdIndex >= 0 && cursor.getLong(deckIdIndex) == deckId) {
                    return true
                }
            }
        }

        return false
    }

    private fun requestDirectoryAccessForDocument(
        pickedDocumentUri: Uri,
        result: MethodChannel.Result,
    ) {
        requestDirectoryAccess(pickedDocumentUri, result)
    }

    private fun requestDirectoryAccess(
        pickedDocumentUri: Uri?,
        result: MethodChannel.Result,
    ) {
        if (pendingTreePickerResult != null) {
            result.error("busy", "A directory picker request is already in progress", null)
            return
        }

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)

            if (pickedDocumentUri != null) {
                buildParentDocumentUri(pickedDocumentUri)?.let { parentUri ->
                    putExtra(DocumentsContract.EXTRA_INITIAL_URI, parentUri)
                }
            }
        }

        pendingTreePickerResult = result
        pendingPickedDocumentUri = pickedDocumentUri
        startActivityForResult(intent, REQUEST_OPEN_DOCUMENT_TREE)
    }

    private fun readBytesFromUri(uri: Uri): ByteArray? {
        return try {
            contentResolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (_: Exception) {
            null
        }
    }

    private fun readTextFromUri(uri: Uri): String? {
        val bytes = readBytesFromUri(uri) ?: return null
        return try {
            bytes.toString(Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    private fun readBytesFromTreePath(treeUri: Uri, relativePath: String): ByteArray? {
        val docUri = resolveTreeDocumentUri(treeUri, relativePath) ?: return null
        return readBytesFromUri(docUri)
    }

    private fun readTextFromTreePath(treeUri: Uri, relativePath: String): String? {
        val docUri = resolveTreeDocumentUri(treeUri, relativePath) ?: return null
        return readTextFromUri(docUri)
    }

    private fun existsInTreePath(treeUri: Uri, relativePath: String): Boolean {
        val docUri = resolveTreeDocumentUri(treeUri, relativePath) ?: return false
        return try {
            contentResolver.openFileDescriptor(docUri, "r")?.use { true } ?: false
        } catch (_: Exception) {
            false
        }
    }

    private fun listNamesInTreeDir(treeUri: Uri, relativePath: String): List<String> {
        val parentDocUri = resolveTreeDocumentUri(treeUri, relativePath) ?: return emptyList()
        val parentDocId = safeGetDocumentId(parentDocUri) ?: return emptyList()
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId)
        val names = mutableListOf<String>()
        val projection = arrayOf(Document.COLUMN_DISPLAY_NAME)
        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val nameIdx = cursor.getColumnIndex(Document.COLUMN_DISPLAY_NAME)
            while (cursor.moveToNext()) {
                if (nameIdx >= 0) {
                    cursor.getString(nameIdx)?.let { names.add(it) }
                }
            }
        }
        return names
    }

    private fun resolveTreeDocumentUri(treeUri: Uri, relativePath: String): Uri? {
        val treeDocId = safeGetTreeDocumentId(treeUri) ?: return null
        val normalized = normalizeRelativePath(relativePath) ?: return null
        val fullDocId = if (normalized.isEmpty()) {
            treeDocId
        } else {
            "$treeDocId/$normalized"
        }
        return try {
            DocumentsContract.buildDocumentUriUsingTree(treeUri, fullDocId)
        } catch (_: Exception) {
            null
        }
    }

    private fun normalizeRelativePath(relativePath: String): String? {
        if (relativePath.isBlank() || relativePath == ".") return ""
        val parts = relativePath
            .replace('\\', '/')
            .split('/')
            .filter { it.isNotEmpty() && it != "." }
        if (parts.any { it == ".." }) return null
        return parts.joinToString("/")
    }

    private fun buildParentDocumentUri(documentUri: Uri): Uri? {
        val authority = documentUri.authority ?: return null
        val documentId = safeGetDocumentId(documentUri) ?: return null

        val prefix = documentId.substringBefore(':', missingDelimiterValue = "")
        if (prefix.isEmpty()) return null

        val afterColon = documentId.substringAfter(':', missingDelimiterValue = "")
        val parentAfterColon = afterColon.substringBeforeLast('/', missingDelimiterValue = "")
        val parentDocId = if (parentAfterColon.isEmpty()) {
            "$prefix:"
        } else {
            "$prefix:$parentAfterColon"
        }

        return try {
            DocumentsContract.buildDocumentUri(authority, parentDocId)
        } catch (_: Exception) {
            null
        }
    }

    private fun safeGetTreeDocumentId(treeUri: Uri): String? {
        return try {
            DocumentsContract.getTreeDocumentId(treeUri)
        } catch (_: Exception) {
            null
        }
    }

    private fun safeGetDocumentId(uri: Uri): String? {
        return try {
            DocumentsContract.getDocumentId(uri)
        } catch (_: Exception) {
            null
        }
    }

    private fun deriveRelativePath(treeDocId: String?, fileDocId: String?): String? {
        if (treeDocId.isNullOrBlank() || fileDocId.isNullOrBlank()) return null
        if (fileDocId == treeDocId) return ""
        val prefix = "$treeDocId/"
        return if (fileDocId.startsWith(prefix)) {
            fileDocId.removePrefix(prefix)
        } else {
            null
        }
    }

    private fun MethodCall.longArgument(name: String): Long? {
        val value = (arguments as? Map<*, *>)?.get(name)
        return when (value) {
            is Int -> value.toLong()
            is Long -> value
            is Number -> value.toLong()
            else -> null
        }
    }
}
