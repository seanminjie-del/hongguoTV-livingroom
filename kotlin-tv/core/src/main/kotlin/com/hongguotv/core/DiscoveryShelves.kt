// SPDX-License-Identifier: GPL-3.0-only
package com.hongguotv.core

/** Topics are derived from source metadata, never invented recommendations. */
object DiscoveryShelves {
    data class Shelf(val key: String,val title: String,val items: List<Series>)
    private val topics=listOf(
            Triple("fantasy","修仙与玄幻",listOf("修仙","玄幻","仙侠","奇幻")),
            Triple("costume","古装与穿越",listOf("古装","古代","穿越","古风")),
            Triple("urban","都市与逆袭",listOf("都市","逆袭","重生","战神")),
            Triple("romance","爱情与家庭",listOf("爱情","恋爱","甜宠","家庭","萌宝")),
            Triple("suspense","悬疑与冒险",listOf("悬疑","推理","冒险","末日","惊悚")))
    /** Channels classify the whole loaded catalog, allowing genuine tag overlap. */
    fun channels(items: List<Series>): List<Shelf> {
        val catalog=items.distinctBy { it.id }
        if(catalog.isEmpty()) return emptyList()
        return listOf(Shelf("hot","热门发现",catalog))+topics.mapNotNull { (key,title,words) ->
            val matches=catalog.filter { item -> words.any { it in item.tags } }
            if(matches.isEmpty()) null else Shelf(key,title,matches)
        }
    }
    fun from(items: List<Series>): List<Shelf> {
        val remaining=items.distinctBy { it.id }.toMutableList()
        val result=mutableListOf<Shelf>()
        val hot=remaining.take(12); remaining.removeAll(hot.toSet())
        if(hot.isNotEmpty()) result+=Shelf("hot","热门发现",hot)
        for((key,title,words) in topics) {
            val matches=remaining.filter { item -> words.any { it in item.tags } }
            if(matches.size<3) continue
            result+=Shelf(key,title,matches); remaining.removeAll(matches.toSet())
        }
        if(remaining.isNotEmpty()) result+=Shelf("explore","更多好故事",remaining)
        return result
    }
}
