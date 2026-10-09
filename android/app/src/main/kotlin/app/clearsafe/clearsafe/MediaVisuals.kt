package app.clearsafe.clearsafe

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Previews and conservative visual suggestions; never selects or changes media. */
internal class MediaVisuals(private val activity: Activity, private val known: (String)->Uri?) {
    private val worker=Executors.newSingleThreadExecutor()
    private fun thumbnail(uri:Uri, size:Int):Bitmap {
        check(Build.VERSION.SDK_INT>=29) { "Preview requires Android 10" }
        return activity.contentResolver.loadThumbnail(uri,Size(size,size),null)
    }
    fun handle(call:MethodCall,result:MethodChannel.Result) {
        if(call.method=="supported") {result.success(Build.VERSION.SDK_INT>=29);return}
        val id=call.argument<String>("id") ?: ""
        val uri=known(id)
        if(uri==null) { result.error("unknown","Item not in inventory",null);return }
        if(call.method=="view") {
            try {
                activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri,activity.contentResolver.getType(uri));addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                });result.success(null)
            } catch(_:Exception) { result.error("viewer","Nenhum visualizador disponível",null) }
            return
        }
        worker.execute {
            try {
                val answer:Any?=when(call.method) {
                    "preview" -> {
                        val bitmap=thumbnail(uri,768)
                        try { ByteArrayOutputStream().use { out -> bitmap.compress(Bitmap.CompressFormat.JPEG,85,out);out.toByteArray() } }
                        finally { bitmap.recycle() }
                    }
                    "details" -> {
                        val out=mutableMapOf<String,Any?>()
                        activity.contentResolver.query(uri,arrayOf(MediaStore.MediaColumns.WIDTH,MediaStore.MediaColumns.HEIGHT,
                            MediaStore.Video.VideoColumns.DURATION),null,null,null)?.use {c ->
                            if(c.moveToFirst()) {out["width"]=c.getInt(0);out["height"]=c.getInt(1);out["duration"]=c.getLong(2)}
                        };out
                    }
                    "signature" -> {
                        val bitmap=thumbnail(uri,1280)
                        try {
                            val recognizer=TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                            val text=try { Tasks.await(recognizer.process(InputImage.fromBitmap(bitmap,0)),30,TimeUnit.SECONDS).text }
                                finally {recognizer.close()}
                            val small=Bitmap.createScaledBitmap(bitmap,9,8,true)
                            val bits=StringBuilder();val histogram=DoubleArray(12)
                            try {
                                fun gray(color:Int)=(Color.red(color)*299+Color.green(color)*587+Color.blue(color)*114)/1000
                                for(y in 0..7) for(x in 0..7) bits.append(if(gray(small.getPixel(x,y))>gray(small.getPixel(x+1,y))) '1' else '0')
                                // RGB histograms complement the edge hash to reduce flat-scene collisions.
                                val colorGrid=Bitmap.createScaledBitmap(bitmap,32,32,true)
                                try { for(y in 0..31) for(x in 0..31) {
                                    val color=colorGrid.getPixel(x,y)
                                    histogram[Color.red(color)/64]++;histogram[4+Color.green(color)/64]++;histogram[8+Color.blue(color)/64]++
                                } } finally {if(colorGrid!==bitmap && colorGrid!==small) colorGrid.recycle()}
                            } finally {if(small!==bitmap) small.recycle()}
                            mapOf("bits" to bits.toString(),"colors" to histogram.map {it/3072},
                                "aspect" to bitmap.width.toDouble()/bitmap.height,"protected" to text.isNotBlank())
                        } finally {bitmap.recycle()}
                    }
                    else -> error("Unsupported preview")
                }
                activity.runOnUiThread {result.success(answer)}
            } catch(_:Exception) { activity.runOnUiThread { result.error("preview_failed","Prévia ou análise visual indisponível",null) } }
        }
    }
    fun close() {worker.shutdown()}
}
