package app.clearsafe.clearsafe

import android.Manifest
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.rule.GrantPermissionRule
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Only artificial emulator fixtures are created/changed by these tests. */
class RecoveryIntegrationTest {
    @get:Rule val permission:GrantPermissionRule=GrantPermissionRule.grant(
        Manifest.permission.READ_MEDIA_IMAGES,Manifest.permission.READ_MEDIA_VIDEO)
    private val instrumentation=InstrumentationRegistry.getInstrumentation()
    private val resolver=instrumentation.targetContext.contentResolver
    private val device=UiDevice.getInstance(instrumentation)
    private class Reply:MethodChannel.Result {
        val latch=CountDownLatch(1); var value:Any?=null;var error:String?=null
        override fun success(result:Any?) {value=result;latch.countDown()}
        override fun error(code:String,message:String?,details:Any?) {error="$code: $message";latch.countDown()}
        override fun notImplemented() {error="notImplemented";latch.countDown()}
        fun await() {assertTrue("Timed out waiting for native result",latch.await(45,TimeUnit.SECONDS))}
    }
    private fun bytes():ByteArray {
        val bitmap=Bitmap.createBitmap(80,60,Bitmap.Config.ARGB_8888);bitmap.eraseColor(Color.BLUE)
        return ByteArrayOutputStream().use {out -> bitmap.compress(Bitmap.CompressFormat.JPEG,90,out);bitmap.recycle();out.toByteArray()}
    }
    private fun shell(command:String):String = ParcelFileDescriptor.AutoCloseInputStream(
        instrumentation.uiAutomation.executeShellCommand(command)).bufferedReader().use {it.readText()}
    private fun foreignFixture(data:ByteArray):String {
        val name="ClearSafeTest_${UUID.randomUUID()}.jpg"
        shell("content insert --uri content://media/external/images/media --bind _display_name:s:$name --bind mime_type:s:image/jpeg --bind relative_path:s:Pictures/ClearSafeTests/")
        val rowId=resolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,arrayOf(MediaStore.MediaColumns._ID),
            "${MediaStore.MediaColumns.DISPLAY_NAME} = ?",arrayOf(name),null)!!.use {c ->
                check(c.moveToFirst()) { "Shell fixture not inserted" };c.getLong(0)
            }
        val image="content://media/external/images/media/$rowId"
        val streams=instrumentation.uiAutomation.executeShellCommandRw("content write --uri $image")
        ParcelFileDescriptor.AutoCloseOutputStream(streams[1]).use {it.write(data)}
        ParcelFileDescriptor.AutoCloseInputStream(streams[0]).bufferedReader().use {it.readText()}
        val id="content://media/external/file/${Uri.parse(image).lastPathSegment}"
        for(i in 0..100) {
            resolver.query(Uri.parse(id),arrayOf(MediaStore.MediaColumns.SIZE),null,null,null)?.use {c ->
                if(c.moveToFirst() && c.getLong(0)==data.size.toLong()) return id
            }
            android.os.SystemClock.sleep(100)
        }
        error("Fixture metadata did not stabilize")
    }
    private fun snapshot(scenario:ActivityScenario<MainActivity>,id:String):Map<String,Any?> {
        var output:Map<String,Any?>?=null
        scenario.onActivity {activity ->
            val inventory=MainActivity::class.java.getDeclaredMethod("inventory",Int::class.javaPrimitiveType,Int::class.javaPrimitiveType)
            inventory.isAccessible=true;inventory.invoke(activity,0,200)
            val stat=MainActivity::class.java.getDeclaredMethod("stat",String::class.java);stat.isAccessible=true
            @Suppress("UNCHECKED_CAST")
            output=stat.invoke(activity,id) as? Map<String,Any?>
        };return output ?: error("Fixture not visible")
    }
    private fun invoke(scenario:ActivityScenario<MainActivity>,method:String,args:Map<String,Any?>):Reply {
        val reply=Reply()
        scenario.onActivity {activity ->
            val field=MainActivity::class.java.getDeclaredField("actions");field.isAccessible=true
            (field.get(activity) as MediaActions).handle(MethodCall(method,args),reply)
        };return reply
    }
    private fun confirm(approve:Boolean) {
        val button=device.wait(Until.findObject(By.res("android",if(approve) "button1" else "button2")),15000)
        assertNotNull("Expected Android system confirmation dialog",button);button!!.click()
    }
    private fun trashed(id:String):Boolean {
        val args=Bundle().apply {putInt(MediaStore.QUERY_ARG_MATCH_TRASHED,MediaStore.MATCH_INCLUDE)}
        resolver.query(Uri.parse(id),arrayOf(MediaStore.MediaColumns.IS_TRASHED),args,null)!!.use {c ->
            assertTrue(c.moveToFirst());return c.getInt(0)==1
        }
    }
    @Test fun foreignDuplicateTrashAndRestoreSurviveActivityRecreation() {
        val data=bytes();val keep=foreignFixture(data);val copy=foreignFixture(data)
        val digest=MessageDigest.getInstance("SHA-256").digest(data).joinToString("") {"%02x".format(it)}
        ActivityScenario.launch(MainActivity::class.java).use {scenario ->
            val a=snapshot(scenario,keep);val b=snapshot(scenario,copy)
            val request=invoke(scenario,"trash",mapOf("items" to listOf(b),"keep" to a,"digest" to digest,"exact" to true))
            confirm(true);request.await();assertNull(request.error)
            assertFalse(trashed(keep));assertTrue(trashed(copy))
            scenario.recreate()
            val journal=invoke(scenario,"journal",emptyMap());journal.await();assertNull(journal.error)
            @Suppress("UNCHECKED_CAST") val rows=journal.value as List<Map<String,Any?>>
            assertEquals("trashed",rows.first {it["id"]==copy}["state"])
            val restore=invoke(scenario,"restore",mapOf("id" to copy));confirm(true);restore.await();assertNull(restore.error)
            assertFalse(trashed(copy))
            resolver.openInputStream(Uri.parse(copy))!!.use {assertArrayEquals(data,it.readBytes())}
            resolver.openInputStream(Uri.parse(keep))!!.use {assertArrayEquals(data,it.readBytes())}
        }
    }
    @Test fun cancellationKeepsOriginalAndJournalReflectsActualState() {
        val id=foreignFixture(bytes())
        ActivityScenario.launch(MainActivity::class.java).use {scenario ->
            val item=snapshot(scenario,id)
            val request=invoke(scenario,"trash",mapOf("items" to listOf(item),"exact" to false))
            confirm(false);request.await();assertTrue(request.error!!.startsWith("cancelled"));assertFalse(trashed(id))
            val journal=invoke(scenario,"journal",emptyMap());journal.await()
            @Suppress("UNCHECKED_CAST") val rows=journal.value as List<Map<String,Any?>>
            assertEquals("active",rows.first {it["id"]==id}["state"])
        }
    }
    @Test fun changedSnapshotAndDifferentContentFailBeforeSystemPrompt() {
        val data=bytes();val differentBytes=data.clone();differentBytes[differentBytes.lastIndex]=(differentBytes.last().toInt() xor 1).toByte()
        val id=foreignFixture(data);val other=foreignFixture(differentBytes)
        val digest=MessageDigest.getInstance("SHA-256").digest(data).joinToString("") {"%02x".format(it)}
        ActivityScenario.launch(MainActivity::class.java).use {scenario ->
            val item=snapshot(scenario,id)
            val stale=invoke(scenario,"trash",mapOf("items" to listOf(item+mapOf("revision" to "stale"))))
            stale.await();assertTrue(stale.error!!.startsWith("action_blocked"));assertFalse(trashed(id))
            val different=invoke(scenario,"trash",mapOf("items" to listOf(snapshot(scenario,other)),
                "keep" to item,"exact" to true,"digest" to digest))
            different.await();assertTrue(different.error!!.startsWith("action_blocked"));assertFalse(trashed(id));assertFalse(trashed(other))
        }
    }
    @Test fun localOcrProtectsDocumentAndPreviewHasActualImageBytes() {
        val bitmap=Bitmap.createBitmap(1000,700,Bitmap.Config.ARGB_8888);bitmap.eraseColor(Color.WHITE)
        val canvas=android.graphics.Canvas(bitmap)
        val paint=Paint().apply {color=Color.BLACK;textSize=60f;isAntiAlias=true}
        canvas.drawText("DOCUMENTO 123456",50f,150f,paint)
        canvas.drawText("ASSINATURA E DATA",50f,300f,paint)
        val data=ByteArrayOutputStream().use {out -> bitmap.compress(Bitmap.CompressFormat.JPEG,95,out);bitmap.recycle();out.toByteArray()}
        val id=foreignFixture(data)
        ActivityScenario.launch(MainActivity::class.java).use {scenario ->
            snapshot(scenario,id)
            fun visual(method:String):Reply {
                val reply=Reply()
                scenario.onActivity {activity ->
                    val field=MainActivity::class.java.getDeclaredField("visuals");field.isAccessible=true
                    (field.get(activity) as MediaVisuals).handle(MethodCall(method,mapOf("id" to id)),reply)
                };reply.await();assertNull(reply.error);return reply
            }
            val preview=visual("preview").value as ByteArray
            assertNotNull(android.graphics.BitmapFactory.decodeByteArray(preview,0,preview.size))
            @Suppress("UNCHECKED_CAST") val value=visual("signature").value as Map<String,Any?>
            assertEquals(true,value["protected"])
            assertEquals(true,value["textDetected"])
            assertEquals(64,(value["bits"] as String).length)
        }
    }
}
