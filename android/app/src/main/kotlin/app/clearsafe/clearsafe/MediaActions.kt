package app.clearsafe.clearsafe

import android.app.Activity
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Only the Android system can trash/restore. No delete/update/write capability. */
internal class MediaActions(
    private val activity: Activity,
    private val known: (String) -> Uri?,
    private val stat: (String) -> Map<String, Any?>?
) {
    private val worker = Executors.newSingleThreadExecutor()
    private val prefs = activity.getSharedPreferences("recovery_journal_v1", 0)
    private var pending: MethodChannel.Result? = null
    @Volatile private var busy = false
    @Volatile private var cancelled = false
    private fun records() = JSONArray(prefs.getString("items", "[]"))
    private fun save(rows: JSONArray) {
        check(prefs.edit().putString("items", rows.toString()).commit()) { "Journal could not be saved" }
    }
    private fun uri(id: String): Uri {
        require(id.matches(Regex("content://media/external/file/[0-9]+")))
        return known(id) ?: throw IllegalStateException("Item not in current inventory")
    }
    private fun stable(item: Map<String, Any?>) {
        val current = stat(item["id"] as String) ?: error("Missing item")
        check(current["size"] == (item["size"] as Number).toLong() &&
            current["revision"] == item["revision"] &&
            current["kind"] in listOf("photo", "video")) { "Item changed; analyze again" }
        check(state(item["id"] as String)["state"] == "active") { "Item already trashed or unavailable" }
    }
    private fun hash(uri: Uri, expectedSize: Long): String {
        val digest = MessageDigest.getInstance("SHA-256")
        var count = 0L
        activity.contentResolver.openInputStream(uri)?.use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                check(!cancelled) { "Validation cancelled" }
                val n = input.read(buffer)
                if (n < 0) break
                count += n; check(count <= expectedSize); digest.update(buffer, 0, n)
            }
        } ?: error("Unreadable item")
        check(count == expectedSize) { "Truncated content" }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
    private fun equal(a: Uri, b: Uri, size: Long) {
        activity.contentResolver.openInputStream(a)?.use { left ->
            activity.contentResolver.openInputStream(b)?.use { right ->
                fun window(input: java.io.InputStream, buffer: ByteArray): Int {
                    var count=0
                    while(count<buffer.size) {
                        val n=input.read(buffer,count,buffer.size-count)
                        if(n<0) break
                        check(n>0); count+=n
                    }
                    return count
                }
                val x=ByteArray(65536); val y=ByteArray(65536); var count=0L
                while(true) {
                    check(!cancelled)
                    val n=window(left,x); val m=window(right,y)
                    check(n==m); if(n==0) break
                    for(i in 0 until n) check(x[i]==y[i]) { "Different content" }
                    count+=n; check(count<=size)
                }
                check(count==size)
            } ?: error("Unreadable copy")
        } ?: error("Unreadable keeper")
    }
    private fun state(id: String): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < 30) return mapOf("state" to "unsupported")
        return try {
            val args=Bundle().apply { putInt(MediaStore.QUERY_ARG_MATCH_TRASHED, MediaStore.MATCH_INCLUDE) }
            activity.contentResolver.query(Uri.parse(id), arrayOf(MediaStore.MediaColumns.IS_TRASHED,
                MediaStore.MediaColumns.DATE_EXPIRES, MediaStore.MediaColumns.SIZE), args, null)?.use { c ->
                if(c.moveToFirst()) return mapOf("state" to if(c.getInt(0)==1) "trashed" else "active",
                    "expires" to if(c.isNull(1)) null else c.getLong(1)*1000, "currentSize" to c.getLong(2))
            }
            mapOf("state" to "missing")
        } catch (_: Exception) { mapOf("state" to "unknown") }
    }
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if(call.method=="supported") { result.success(Build.VERSION.SDK_INT>=30); return }
        if(call.method=="cancelValidation") {if(pending==null) cancelled=true;result.success(null);return}
        if(busy) { result.error("busy","Operation already in progress",null); return }
        if(Build.VERSION.SDK_INT<30) { result.error("unsupported","Trash requires Android 11",null); return }
        busy=true;cancelled=false
        worker.execute {
            try {
                when(call.method) {
                    "journal" -> {
                        val rows=records(); val out=mutableListOf<Map<String,Any?>>()
                        for(i in 0 until rows.length()) {
                            val item=rows.getJSONObject(i); val id=item.getString("id")
                            out.add(mapOf("id" to id,"name" to item.getString("name"),"time" to item.getLong("time"),
                                "size" to item.getLong("size"),"request" to item.optString("request")) + state(id))
                        }
                        activity.runOnUiThread { busy=false;result.success(out.reversed()) }
                    }
                    "trash" -> {
                        val items=call.argument<List<Map<String,Any?>>>("items") ?: error("No selection")
                        val keep=call.argument<Map<String,Any?>>("keep")
                        val digest=call.argument<String>("digest")
                        val exact=call.argument<Boolean>("exact") ?: false
                        TrashPolicy.validate(items.map { it["id"] as String },keep?.get("id") as String?,digest,exact)
                        val uris=items.map { uri(it["id"] as String) }
                        items.forEach(::stable); keep?.let { uri(it["id"] as String);stable(it) }
                        if(exact) check(hash(uri(keep!!["id"] as String),(keep["size"] as Number).toLong())==digest)
                        val hashes=items.mapIndexed { i,item ->
                            val value=hash(uris[i],(item["size"] as Number).toLong())
                            if(exact) {
                                check(value==digest); equal(uri(keep!!["id"] as String),uris[i],(item["size"] as Number).toLong())
                            }
                            value
                        }
                        items.forEach(::stable); keep?.let(::stable)
                        check(!cancelled)
                        val rows=records()
                        // Replace an older record for the same ID only after a fully verified new request.
                        val merged=JSONArray()
                        for(i in 0 until rows.length()) if(rows.getJSONObject(i).getString("id") !in items.map {it["id"]}) merged.put(rows.getJSONObject(i))
                        items.forEachIndexed { i,item -> merged.put(JSONObject().put("id",item["id"]).put("name",item["name"])
                            .put("size",item["size"]).put("hash",hashes[i]).put("time",System.currentTimeMillis()).put("request","trash_requested")) }
                        save(merged)
                        launch(uris,true,result)
                    }
                    "restore" -> {
                        val id=call.argument<String>("id") ?: error("No ID")
                        val rows=records(); var record:JSONObject?=null
                        for(i in 0 until rows.length()) if(rows.getJSONObject(i).getString("id")==id) record=rows.getJSONObject(i)
                        val item=record ?: error("No recovery record")
                        TrashPolicy.validate(listOf(id),null,null)
                        check(state(id)["state"]=="trashed") { "Not in accessible trash" }
                        // Prevent restoring a reused media ID with different content.
                        check(hash(Uri.parse(id),item.getLong("size"))==item.getString("hash")) { "Recovery content changed" }
                        item.put("request","restore_requested");save(rows)
                        launch(listOf(Uri.parse(id)),false,result)
                    }
                    else -> error("Unsupported action")
                }
            } catch(_:Exception) {
                activity.runOnUiThread { busy=false;result.error("action_blocked",
                    "Não foi possível validar o conteúdo ou acessar a lixeira. Analise novamente; consulte a galeria para recuperação.",null) }
            }
        }
    }
    private fun launch(uris: List<Uri>, trash: Boolean, result: MethodChannel.Result) {
        check(Build.VERSION.SDK_INT>=30)
        val request=MediaStore.createTrashRequest(activity.contentResolver,uris,trash)
        activity.runOnUiThread {
            try {
                check(!cancelled && !activity.isFinishing && !activity.isDestroyed)
                pending=result
                activity.startIntentSenderForResult(request.intentSender,103,null,0,0,0)
            } catch(_:Exception) {pending=null;busy=false;result.error("unavailable","System trash unavailable",null)}
        }
    }
    fun completed(code: Int) {
        val result=pending;pending=null;busy=false
        if(code==Activity.RESULT_OK) result?.success(null)
        else result?.error("cancelled","Solicitação cancelada no Android. Confira o histórico para o estado atual.",null)
    }
    fun close() {cancelled=true;worker.shutdownNow()}
}
