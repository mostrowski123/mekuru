package moe.matthew.mekuru

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
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
        private const val SYSTEM_UI_CHANNEL_NAME = "mekuru/android_system_ui"
        private const val REQUEST_OPEN_DOCUMENT_TREE = 7312

        /**
         * Shared so a configuration change does not throw away everything
         * learned about the trees the reader is currently paging through.
         */
        private val resolutionCache = SafResolutionCache()
    }

    private var pendingTreePickerResult: MethodChannel.Result? = null
    private var pendingPickedDocumentUri: Uri? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.enableEdgeToEdge(window)
    }

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_UI_CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                try {
                    handleSystemUiMethodCall(call, result)
                } catch (e: Exception) {
                    result.error("system_ui_error", e.message, null)
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
                // Resolving a tree path queries the document provider, so it
                // must not run on the main thread.
                runIo(result) {
                    resolveTreeDocumentUri(Uri.parse(treeUri), relativePath)?.toString()
                }
            }
            else -> result.notImplemented()
        }
    }

    // AnkiDroid's content provider can block for seconds while its process
    // cold-starts, so every AddContentApi call must run via runIo — querying
    // the provider on the main thread ANRs the app.
    private fun handleAnkiMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isApiAvailable" -> {
                runIo(result) {
                    AddContentApi.getAnkiDroidPackageName(applicationContext) != null
                }
            }
            "getModelList" -> {
                runIo(result) {
                    AddContentApi(applicationContext).modelList
                }
            }
            "getFieldList" -> {
                val modelId = call.longArgument("modelId")
                if (modelId == null) {
                    result.error("bad_args", "modelId is required", null)
                    return
                }
                runIo(result) {
                    AddContentApi(applicationContext).getFieldList(modelId)?.toList()
                }
            }
            "getDeckList" -> {
                runIo(result) {
                    AddContentApi(applicationContext).deckList
                }
            }
            "addNote" -> {
                val modelId = call.longArgument("modelId")
                val deckId = call.longArgument("deckId")
                val fields = call.argument<List<String>>("fields")
                val tags = call.argument<List<String>>("tags") ?: emptyList()
                if (modelId == null || deckId == null || fields == null) {
                    result.error("bad_args", "modelId, deckId and fields are required", null)
                    return
                }
                runIo(result) {
                    AddContentApi(applicationContext).addNote(
                        modelId,
                        deckId,
                        fields.toTypedArray(),
                        tags.toSet(),
                    )
                }
            }
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

    private fun handleSystemUiMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setSystemBarsVisible" -> {
                val visible = call.argument<Boolean>("visible")
                if (visible == null) {
                    result.error("bad_args", "visible is required", null)
                    return
                }

                setSystemBarsVisible(visible)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun setSystemBarsVisible(visible: Boolean) {
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.isAppearanceLightStatusBars = false
        controller.isAppearanceLightNavigationBars = false

        if (visible) {
            controller.show(WindowInsetsCompat.Type.systemBars())
        } else {
            controller.hide(WindowInsetsCompat.Type.systemBars())
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
            } catch (e: SafFailure) {
                runOnUiThread { result.error(e.code, e.reason, e.details()) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("saf_io_error", describeThrowable(e), null)
                }
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

    /**
     * A SAF operation that failed for a reason worth reporting.
     *
     * Reads used to collapse every failure into a bare `null`, so a crash
     * report could say a file could not be read but never why. [code] and
     * [reason] travel to Dart as the method channel error, and [details] adds
     * the provider authority and the stage that failed. Nothing here carries a
     * file path or user content.
     */
    private class SafFailure(
        val code: String,
        val reason: String,
        val authority: String?,
        val stage: String,
    ) : Exception(reason) {
        fun details(): Map<String, String?> =
            mapOf("authority" to authority, "stage" to stage)
    }

    private fun describeThrowable(e: Throwable): String {
        val message = e.message
        return if (message.isNullOrBlank()) {
            e.javaClass.simpleName
        } else {
            "${e.javaClass.simpleName}: $message"
        }
    }

    private fun readBytesFromUri(uri: Uri): ByteArray {
        try {
            return contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: throw SafFailure(
                    "saf_open_failed",
                    "The document provider returned no stream for the document",
                    uri.authority,
                    "open",
                )
        } catch (e: SafFailure) {
            throw e
        } catch (e: Exception) {
            throw SafFailure("saf_read_failed", describeThrowable(e), uri.authority, "read")
        }
    }

    private fun readTextFromUri(uri: Uri): String =
        readBytesFromUri(uri).toString(Charsets.UTF_8)

    private fun readBytesFromTreePath(treeUri: Uri, relativePath: String): ByteArray =
        readTreePath(treeUri, relativePath, ::readBytesFromUri)

    private fun readTextFromTreePath(treeUri: Uri, relativePath: String): String =
        readTreePath(treeUri, relativePath, ::readTextFromUri)

    /**
     * Resolves [relativePath] and reads it with [read].
     *
     * A failed read drops everything cached for the tree, so a document that
     * has since been moved, deleted or had its grant revoked cannot keep being
     * served from stale state — the next attempt resolves from scratch.
     */
    private fun <T> readTreePath(
        treeUri: Uri,
        relativePath: String,
        read: (Uri) -> T,
    ): T {
        val documentUri = requireTreeDocumentUri(treeUri, relativePath)
        return try {
            read(documentUri)
        } catch (e: Exception) {
            resolutionCache.invalidateTree(treeUri.toString())
            throw e
        }
    }

    private fun requireTreeDocumentUri(treeUri: Uri, relativePath: String): Uri =
        resolveTreeDocumentUri(treeUri, relativePath)
            ?: throw SafFailure(
                "saf_document_not_found",
                "No document matching the requested path exists under the granted tree",
                treeUri.authority,
                "resolve",
            )

    private fun existsInTreePath(treeUri: Uri, relativePath: String): Boolean {
        val docUri = resolveTreeDocumentUri(treeUri, relativePath) ?: return false
        return try {
            contentResolver.openFileDescriptor(docUri, "r")?.use { true } ?: false
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Lists a directory, always reading it fresh.
     *
     * This backs the folder picker, where showing a file the user just added
     * matters more than saving a query, so it never serves the cached index —
     * it refreshes it instead, which later resolutions then reuse.
     */
    private fun listNamesInTreeDir(treeUri: Uri, relativePath: String): List<String> {
        val parentDocId = resolveTreeDocumentId(treeUri, relativePath) ?: return emptyList()
        val children = listChildDocuments(treeUri, parentDocId)
        resolutionCache.putChildIndex(
            treeUri.toString(),
            parentDocId,
            SafTreePathResolver.indexChildren(children),
        )
        return children.map { it.displayName }
    }

    private fun listChildDocuments(
        treeUri: Uri,
        parentDocumentId: String,
    ): List<SafChildDocument> {
        val childrenUri = try {
            DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocumentId)
        } catch (_: Exception) {
            return emptyList()
        }
        val children = mutableListOf<SafChildDocument>()
        val projection = arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME)
        try {
            contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                val idIdx = cursor.getColumnIndex(Document.COLUMN_DOCUMENT_ID)
                val nameIdx = cursor.getColumnIndex(Document.COLUMN_DISPLAY_NAME)
                if (idIdx < 0 || nameIdx < 0) return@use
                while (cursor.moveToNext()) {
                    val documentId = cursor.getString(idIdx) ?: continue
                    val displayName = cursor.getString(nameIdx) ?: continue
                    children.add(SafChildDocument(documentId, displayName))
                }
            }
        } catch (_: Exception) {
            return emptyList()
        }
        return children
    }

    /**
     * Resolves [relativePath] inside [treeUri] to the provider's document ID.
     *
     * Appending the path to the tree document ID is correct and cheap for
     * path-shaped providers, so it is tried first and verified against the
     * provider. Everything else has opaque document IDs and has to be resolved
     * by walking the children cursors; see [SafTreePathResolver].
     */
    private fun resolveTreeDocumentId(treeUri: Uri, relativePath: String): String? {
        val treeDocId = safeGetTreeDocumentId(treeUri) ?: return null
        val segments = SafTreePathResolver.splitSegments(relativePath) ?: return null
        if (segments.isEmpty()) return treeDocId

        val treeKey = treeUri.toString()
        val fullPath = segments.joinToString("/")
        resolutionCache.documentId(treeKey, fullPath)?.let { return it }

        // Skip the append attempt once this tree has proved it does not accept
        // derived IDs; on a network provider that failed query is a wasted
        // round trip on every single lookup.
        val triedFastPath = !resolutionCache.isKnownOpaque(treeKey)
        if (triedFastPath) {
            val joined = SafTreePathResolver.joinDocumentId(treeDocId, segments)
            if (documentIdResolves(treeUri, joined)) {
                resolutionCache.putDocumentId(treeKey, fullPath, joined)
                return joined
            }
        }

        val walked = SafTreePathResolver.resolveCached(
            treeKey,
            treeDocId,
            segments,
            resolutionCache,
        ) { parentDocumentId ->
            listChildDocuments(treeUri, parentDocumentId)
        }

        // Only conclude the tree is opaque when the walk found a document the
        // append could not name. A plain missing file says nothing about the
        // provider's ID shape, and marking a path-shaped tree opaque would cost
        // it the fast path forever.
        if (triedFastPath && walked != null) {
            resolutionCache.markOpaque(treeKey)
        }
        return walked
    }

    private fun resolveTreeDocumentUri(treeUri: Uri, relativePath: String): Uri? {
        val documentId = resolveTreeDocumentId(treeUri, relativePath) ?: return null
        return buildTreeDocumentUri(treeUri, documentId)
    }

    private fun buildTreeDocumentUri(treeUri: Uri, documentId: String): Uri? {
        return try {
            DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
        } catch (_: Exception) {
            null
        }
    }

    /**
     * True when [documentId] names a real document in [treeUri].
     *
     * The provider must both return a row and echo back the same document ID.
     * A well-behaved provider throws for an unknown ID, but a lenient one can
     * hand back a fabricated row for a concatenated ID it never issued, which
     * would send the caller off to read a document that does not exist. A
     * provider that canonicalises IDs instead falls through to the slower walk,
     * which still resolves correctly.
     */
    private fun documentIdResolves(treeUri: Uri, documentId: String): Boolean {
        val documentUri = buildTreeDocumentUri(treeUri, documentId) ?: return false
        return try {
            contentResolver.query(
                documentUri,
                arrayOf(Document.COLUMN_DOCUMENT_ID),
                null,
                null,
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return@use false
                val idIdx = cursor.getColumnIndex(Document.COLUMN_DOCUMENT_ID)
                idIdx >= 0 && cursor.getString(idIdx) == documentId
            } ?: false
        } catch (_: Exception) {
            false
        }
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
