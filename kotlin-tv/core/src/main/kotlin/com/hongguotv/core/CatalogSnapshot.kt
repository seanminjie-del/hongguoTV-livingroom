// SPDX-License-Identifier: GPL-3.0-only
package com.hongguotv.core

import org.json.JSONArray
import org.json.JSONObject

/** Bounded home metadata only; playback URLs and account data never go to disk. */
object CatalogSnapshot {
    private const val MAX_AGE=7*24*60*60*1000L
    fun encode(items: List<Series>,hasMore: Boolean,now: Long,loadedPages: Int=1): String = JSONObject()
        .put("savedAt",now).put("hasMore",hasMore).put("loadedPages",loadedPages.coerceIn(1,3))
        .put("items",JSONArray(items.take(90).map { it.copy(description=it.description.take(1500)).toJson() })).toString()
    fun decode(value: String,now: Long): CatalogPage? = runCatching {
        require(value.length<=400_000)
        val o=JSONObject(value); require(now-o.getLong("savedAt") in 0..MAX_AGE)
        val rows=o.getJSONArray("items"); require(rows.length() in 1..90)
        val items=(0 until rows.length()).map { Series.fromJson(rows.getJSONObject(it)) }
        require(items.all { it.id.matches(Regex("[0-9]{1,30}")) && it.title.isNotBlank() })
        CatalogPage(items.distinctBy { it.id },o.getBoolean("hasMore"),loadedPages=o.optInt("loadedPages",1).coerceIn(1,3))
    }.getOrNull()
}
