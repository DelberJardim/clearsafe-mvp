package app.clearsafe.clearsafe

import org.junit.Assert.*
import org.junit.Test

class TrashPolicyTest {
    private val a="content://media/external/file/1"
    private val b="content://media/external/file/2"
    private fun blocked(block:()->Unit) {assertThrows(IllegalArgumentException::class.java,block)}
    @Test fun keeperCannotBeTrashed() {blocked {TrashPolicy.validate(listOf(a),a,"a".repeat(64),true)}}
    @Test fun exactRequiresKeeperAndDigest() {
        blocked {TrashPolicy.validate(listOf(a),null,null,true)}
        blocked {TrashPolicy.validate(listOf(a),b,"invalid",true)}
    }
    @Test fun rejectsUnknownProvidersAndPaths() {
        for(id in listOf("file:///sdcard/photo.jpg","content://other/1","content://media/external/file/../1","document:x"))
            blocked {TrashPolicy.validate(listOf(id),null,null)}
    }
    @Test fun rejectsEmptyDuplicateAndOversizedBatches() {
        blocked {TrashPolicy.validate(emptyList(),null,null)}
        blocked {TrashPolicy.validate(listOf(a,a),null,null)}
        blocked {TrashPolicy.validate((1..101).map {"content://media/external/file/$it"},null,null)}
    }
    @Test fun acceptsExplicitExactAndManualSelections() {
        TrashPolicy.validate(listOf(a),b,"a".repeat(64),true)
        TrashPolicy.validate(listOf(a),b,null,false)
        TrashPolicy.validate(listOf(a),null,null,false)
    }
}
