package moe.matthew.mekuru

import android.content.ContentResolver
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import java.io.BufferedOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import moe.matthew.mekuru.backup.FileJobIo
import moe.matthew.mekuru.backup.Finalized
import moe.matthew.mekuru.backup.JobFailedException
import moe.matthew.mekuru.backup.JobIo
import moe.matthew.mekuru.backup.JobSpec
import moe.matthew.mekuru.backup.Sink
import moe.matthew.mekuru.backup.createPartialFile
import moe.matthew.mekuru.backup.finalizePartialFile
import moe.matthew.mekuru.backup.openFileEntry

/**
 * [JobIo] over `ContentResolver`. Handles both `content://` documents (the
 * SAF folder or file the user picked) and `file://` URIs (the test seams and
 * any plain-path fallback) through the same calls, so the emulator suites
 * exercise the real descriptor and channel path.
 *
 * The partial document is created with `application/octet-stream`: with the
 * zip MIME type the provider would append `.zip` to `<name>.partial`.
 */
class SafJobIo(private val resolver: ContentResolver) : JobIo {
    override fun createPartial(spec: JobSpec): JobSpec {
        spec.docUri?.let { deleteUri(Uri.parse(it)) }
        val name = requireNotNull(spec.displayName) { "displayName" } + FileJobIo.PARTIAL_SUFFIX
        val uri = when {
            spec.treeUri != null -> {
                val tree = Uri.parse(spec.treeUri)
                val parent = DocumentsContract.buildDocumentUriUsingTree(
                    tree,
                    DocumentsContract.getTreeDocumentId(tree),
                )
                DocumentsContract.createDocument(resolver, parent, PARTIAL_MIME, name)
                    ?: throw JobFailedException("create_failed")
            }
            spec.targetPath != null -> Uri.fromFile(createPartialFile(File(spec.targetPath)))
            else -> throw IllegalArgumentException("export target missing")
        }
        return spec.copy(docUri = uri.toString())
    }

    override fun openSink(spec: JobSpec): Sink? {
        val uri = Uri.parse(spec.docUri ?: return null)
        if (!exists(uri)) return null
        if (!forceNonResumable) {
            val pfd = try {
                resolver.openFileDescriptor(uri, "rw")
            } catch (_: Exception) {
                null
            }
            if (pfd != null && pfd.statSize >= 0) {
                val stream = ParcelFileDescriptor.AutoCloseOutputStream(pfd)
                return Sink(BufferedOutputStream(stream, BUFFER), stream.channel)
            }
            pfd?.close()
        }
        // A pipe-only provider: no seeking, so a resume starts the archive over.
        val stream = try {
            resolver.openOutputStream(uri, "wt")
        } catch (_: IllegalArgumentException) {
            resolver.openOutputStream(uri, "w")
        } ?: throw JobFailedException("open_failed")
        return Sink(BufferedOutputStream(stream, BUFFER), null)
    }

    override fun deletePartial(spec: JobSpec) {
        spec.docUri?.let { deleteUri(Uri.parse(it)) }
    }

    override fun finalizePartial(spec: JobSpec): Finalized {
        val partial = Uri.parse(requireNotNull(spec.docUri) { "docUri" })
        val displayName = requireNotNull(spec.displayName) { "displayName" }
        if (partial.scheme == "file") {
            val partialFile = File(requireNotNull(partial.path))
            return finalizePartialFile(partialFile, File(partialFile.parentFile, displayName))
        }
        if (!exists(partial)) {
            val existing = spec.treeUri?.let { childByName(Uri.parse(it), displayName) }
                ?: throw JobFailedException("partial_missing")
            return Finalized(existing.toString(), renamed = true)
        }
        return try {
            val renamed = DocumentsContract.renameDocument(resolver, partial, displayName)
            if (renamed == null) Finalized(partial.toString(), renamed = false) else Finalized(renamed.toString(), renamed = true)
        } catch (_: Exception) {
            Finalized(partial.toString(), renamed = false)
        }
    }

    /** `content://` through the resolver (the folder grant must still hold), anything else as a file. */
    override fun openEntry(path: String): InputStream? {
        if (!path.startsWith("content:")) return openFileEntry(path)
        return try {
            resolver.openInputStream(Uri.parse(path))
        } catch (_: IOException) {
            null
        } catch (_: SecurityException) {
            null
        }
    }

    private fun exists(uri: Uri): Boolean {
        if (uri.scheme == "file") return File(requireNotNull(uri.path)).isFile
        return try {
            resolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)
                ?.use { it.count > 0 } ?: false
        } catch (_: Exception) {
            false
        }
    }

    private fun deleteUri(uri: Uri) {
        try {
            if (uri.scheme == "file") File(requireNotNull(uri.path)).delete() else DocumentsContract.deleteDocument(resolver, uri)
        } catch (_: Exception) {
            // Already gone, or the provider refused; nothing else to do.
        }
    }

    private fun childByName(treeUri: Uri, name: String): Uri? {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
        )
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        )
        return try {
            resolver.query(children, columns, null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    if (cursor.getString(1) == name) {
                        return DocumentsContract.buildDocumentUriUsingTree(treeUri, cursor.getString(0))
                    }
                }
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        private const val PARTIAL_MIME = "application/octet-stream"
        private const val BUFFER = 1 shl 16

        /** Test seam: pretend every target is a pipe-only provider. */
        @Volatile var forceNonResumable = false
    }
}
