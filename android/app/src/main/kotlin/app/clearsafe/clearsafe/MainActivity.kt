package app.clearsafe.clearsafe

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.ContactsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val handles = mutableMapOf<String, InputStream>()
    private val known = mutableMapOf<String, Uri>()
    private val documents = mutableMapOf<String, Uri>()
    private var pending: MethodChannel.Result? = null
    private var pendingScope = ""
    private fun allowed(p: String) = checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED
    private fun access(scope: String): String {
        if (scope == "contacts") return if(allowed(Manifest.permission.READ_CONTACTS)) "full" else "denied"
        if (Build.VERSION.SDK_INT >= 33) {
            if (allowed(Manifest.permission.READ_MEDIA_IMAGES) && allowed(Manifest.permission.READ_MEDIA_VIDEO)) return "full"
            if (allowed(Manifest.permission.READ_MEDIA_IMAGES) || allowed(Manifest.permission.READ_MEDIA_VIDEO) ||
                (Build.VERSION.SDK_INT >= 34 && allowed(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED))) return "limited"
            return "denied"
        }
        return if(allowed(Manifest.permission.READ_EXTERNAL_STORAGE)) "full" else "denied"
    }
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "clearsafe/read_only").setMethodCallHandler { call, result ->
            val scope = call.argument<String>("scope") ?: "media"
            when(call.method) {
                "permission" -> result.success(access(scope))
                "requestPermission" -> {
                    if(pending != null) result.error("busy", "Permission request in progress", null)
                    else {
                        pending=result; pendingScope=scope
                        val permissions = if(scope=="contacts") arrayOf(Manifest.permission.READ_CONTACTS)
                        else if(Build.VERSION.SDK_INT>=34) arrayOf(Manifest.permission.READ_MEDIA_IMAGES,Manifest.permission.READ_MEDIA_VIDEO,Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
                        else if(Build.VERSION.SDK_INT>=33) arrayOf(Manifest.permission.READ_MEDIA_IMAGES,Manifest.permission.READ_MEDIA_VIDEO)
                        else arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
                        requestPermissions(permissions,101)
                    }
                }
                "selectDocuments" -> {
                    if(pending!=null) result.error("busy","Request in progress",null)
                    else { pending=result; startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        type="*/*"; addCategory(Intent.CATEGORY_OPENABLE)
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE,true)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    },102) }
                }
                else -> worker.execute {
                    try {
                        val answer: Any? = when(call.method) {
                            "inventory" -> inventory(call.argument<Int>("offset")?:0,call.argument<Int>("limit")?:200)
                            "stat" -> stat(call.argument<String>("id")!!)
                            "open" -> {
                                val id=call.argument<String>("id")!!
                                val uri=known[id] ?: documents[id] ?: throw IllegalArgumentException("Unknown ID")
                                val handle=UUID.randomUUID().toString()
                                handles[handle]=contentResolver.openInputStream(uri) ?: throw IllegalStateException("Unavailable")
                                handle
                            }
                            "read" -> {
                                val input=handles[call.argument<String>("handle")!!] ?: throw IllegalArgumentException("Unknown handle")
                                val bytes=ByteArray(65536); val n=input.read(bytes)
                                if(n<0) ByteArray(0) else bytes.copyOf(n)
                            }
                            "close" -> { handles.remove(call.argument<String>("handle")!!)?.close(); null }
                            "contacts" -> contacts()
                            "diagnostics" -> if(access("media")=="full") emptyList<String>() else listOf("Galeria com acesso parcial ou negado; relatório limitado ao conteúdo autorizado.")
                            else -> throw IllegalArgumentException("Unsupported read operation")
                        }
                        runOnUiThread { result.success(answer) }
                    } catch(e: Exception) { runOnUiThread { result.error("read_failed","Content unavailable or access revoked",null) } }
                }
            }
        }
    }
    override fun onRequestPermissionsResult(code:Int, permissions:Array<out String>, grants:IntArray) {
        super.onRequestPermissionsResult(code,permissions,grants)
        if(code==101) {pending?.success(access(pendingScope));pending=null}
    }
    @Deprecated("Activity result compatibility")
    override fun onActivityResult(code:Int,resultCode:Int,data:Intent?) {
        super.onActivityResult(code,resultCode,data)
        if(code==102) {
            if(resultCode==Activity.RESULT_OK && data!=null) {
                val uris=mutableListOf<Uri>()
                data.data?.let {uris.add(it)}
                data.clipData?.let {clip -> for(i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)}
                for(uri in uris) { val id="document:$uri";documents[id]=uri;known[id]=uri }
            }
            pending?.success(null);pending=null
        }
    }
    private fun row(c:Cursor,uri:Uri):Map<String,Any?> {
        fun str(key:String):String {val i=c.getColumnIndex(key);return if(i>=0 && !c.isNull(i)) c.getString(i) else ""}
        fun num(key:String):Long {val i=c.getColumnIndex(key);return if(i>=0 && !c.isNull(i)) c.getLong(i) else -1L}
        val mime=str(MediaStore.MediaColumns.MIME_TYPE)
        val id=uri.toString();known[id]=uri
        val time=num(MediaStore.MediaColumns.DATE_MODIFIED)
        val size=num(MediaStore.MediaColumns.SIZE)
        val generation=if(Build.VERSION.SDK_INT>=30) num(MediaStore.MediaColumns.GENERATION_MODIFIED) else time
        return mapOf("id" to id,"name" to str(MediaStore.MediaColumns.DISPLAY_NAME),"size" to size,
            "kind" to if(mime.startsWith("video/")) "video" else "photo",
            "folder" to if(Build.VERSION.SDK_INT>=29) str(MediaStore.MediaColumns.RELATIVE_PATH).trimEnd('/') else "",
            "modified" to if(time>=0) time*1000 else null,"revision" to "$size:$time:$generation")
    }
    private fun inventory(offset:Int,limit:Int):List<Map<String,Any?>> {
        require(offset>=0 && limit in 1..200)
        val out=mutableListOf<Map<String,Any?>>()
        val collection=MediaStore.Files.getContentUri("external")
        val projection=mutableListOf(MediaStore.MediaColumns._ID,MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,MediaStore.MediaColumns.DATE_MODIFIED,MediaStore.MediaColumns.MIME_TYPE)
        if(Build.VERSION.SDK_INT>=29) projection.add(MediaStore.MediaColumns.RELATIVE_PATH)
        if(Build.VERSION.SDK_INT>=30) projection.add(MediaStore.MediaColumns.GENERATION_MODIFIED)
        // Accessible media only; no all-files access, no protected app directories.
        var index=0
        if(access("media")!="denied") contentResolver.query(collection,projection.toTypedArray(),
            "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (?,?)",arrayOf("1","3"),"${MediaStore.MediaColumns._ID} ASC")?.use {c ->
            while(c.moveToNext()) {
                if(index++<offset) continue
                if(out.size>=limit) break
                val uri=Uri.withAppendedPath(collection,c.getLong(0).toString());out.add(row(c,uri))
            }
        }
        if(out.size<limit) {
            for((id,uri) in documents.toSortedMap()) {
                if(index++<offset) continue
                if(out.size>=limit) break
                out.add(documentStat(id,uri))
            }
        }
        return out
    }
    private fun documentStat(id:String,uri:Uri):Map<String,Any?> {
        var name="Document";var size=-1L;var modified:Long?=null
        contentResolver.query(uri,null,null,null,null)?.use {c ->
            if(c.moveToFirst()) {
                val n=c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val s=c.getColumnIndex(OpenableColumns.SIZE)
                val m=c.getColumnIndex("last_modified")
                if(n>=0 && !c.isNull(n)) name=c.getString(n)
                if(s>=0 && !c.isNull(s)) size=c.getLong(s)
                if(m>=0 && !c.isNull(m) && c.getLong(m)>0) modified=c.getLong(m)
            }
        }
        val mime=contentResolver.getType(uri) ?: ""
        val kind=when {
            mime.startsWith("image/") -> "photo"
            mime.startsWith("video/") -> "video"
            mime.startsWith("audio/") -> "audio"
            mime.startsWith("text/") || (mime.startsWith("application/") && mime!="application/octet-stream") -> "document"
            else -> "other"
        }
        // Providers may not expose modification version. Do not claim exact duplicates for these.
        return mapOf("id" to id,"name" to name,"size" to size,"kind" to kind,"folder" to "Documentos selecionados",
            "modified" to modified,"revision" to "unversioned")
    }
    private fun stat(id:String):Map<String,Any?>? {
        documents[id]?.let {return documentStat(id,it)}
        val uri=known[id] ?: return null
        val cols=mutableListOf(MediaStore.MediaColumns._ID,MediaStore.MediaColumns.DISPLAY_NAME,MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_MODIFIED,MediaStore.MediaColumns.MIME_TYPE)
        if(Build.VERSION.SDK_INT>=29) cols.add(MediaStore.MediaColumns.RELATIVE_PATH)
        if(Build.VERSION.SDK_INT>=30) cols.add(MediaStore.MediaColumns.GENERATION_MODIFIED)
        contentResolver.query(uri,cols.toTypedArray(),null,null,null)?.use {c ->if(c.moveToFirst()) return row(c,uri)}
        return null
    }
    private fun contacts():List<Map<String,Any?>> {
        if(access("contacts")!="full") throw SecurityException()
        val out=mutableListOf<Map<String,Any?>>()
        contentResolver.query(ContactsContract.Contacts.CONTENT_URI,arrayOf(ContactsContract.Contacts._ID,ContactsContract.Contacts.DISPLAY_NAME_PRIMARY),null,null,null)?.use {c ->
            while(c.moveToNext()) {
                val id=c.getString(0)
                fun values(uri:Uri,column:String):List<String> {
                    val result=mutableListOf<String>()
                    contentResolver.query(uri,arrayOf(column),"contact_id = ?",arrayOf(id),null)?.use {v ->while(v.moveToNext()) result.add(v.getString(0)?:"")}
                    return result
                }
                out.add(mapOf("id" to id,"name" to (c.getString(1)?:""),
                    "phones" to values(ContactsContract.CommonDataKinds.Phone.CONTENT_URI,ContactsContract.CommonDataKinds.Phone.NUMBER),
                    "emails" to values(ContactsContract.CommonDataKinds.Email.CONTENT_URI,ContactsContract.CommonDataKinds.Email.ADDRESS)))
            }
        }
        return out
    }
    override fun onDestroy() {
        worker.execute {handles.values.forEach {try {it.close()} catch(_:Exception) {}};handles.clear()}
        worker.shutdown();super.onDestroy()
    }
}
