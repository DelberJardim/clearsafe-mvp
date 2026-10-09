package app.clearsafe.clearsafe

/** Pure, fail-closed gate, independent from UI and Android permissions. */
internal object TrashPolicy {
    fun validate(ids: List<String>, keeper: String?, digest: String?, exact: Boolean = false) {
        require(ids.isNotEmpty() && ids.size <= 100)
        require(ids.toSet().size == ids.size && keeper !in ids)
        require(!exact || (keeper != null && digest?.matches(Regex("[a-f0-9]{64}")) == true))
        require(ids.all { it.matches(Regex("content://media/external/file/[0-9]+")) })
        require(keeper == null || keeper.matches(Regex("content://media/external/file/[0-9]+")))
    }
}
