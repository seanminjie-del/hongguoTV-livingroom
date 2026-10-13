package com.hongguotv.core

import org.junit.Assert.*
import org.junit.Test

class DiscoveryChannelsTest {
    @Test fun hotTitlesAndOverlappingTagsRemainInEveryMatchingChannel() {
        val shared=Series("1","穿越修仙",tags="修仙 · 穿越")
        val urban=Series("2","重生",tags="都市 · 重生")
        val unknown=Series("3","未分类")
        val channels=DiscoveryShelves.channels(listOf(shared,urban,unknown,shared))
        assertEquals(listOf("1","2","3"),channels.first { it.key=="hot" }.items.map { it.id })
        assertEquals(listOf("1"),channels.first { it.key=="fantasy" }.items.map { it.id })
        assertEquals(listOf("1"),channels.first { it.key=="costume" }.items.map { it.id })
        assertEquals(listOf("2"),channels.first { it.key=="urban" }.items.map { it.id })
        assertFalse(channels.any { it.key=="romance" || it.key=="suspense" })
    }
    @Test fun allLoadedTitlesRemainAvailableWithoutShelfTruncation() {
        val items=(1..72).map { Series("$it","故事 $it",tags="爱情") }
        val channels=DiscoveryShelves.channels(items)
        assertEquals(72,channels.first { it.key=="hot" }.items.size)
        assertEquals(72,channels.first { it.key=="romance" }.items.size)
        assertTrue(DiscoveryShelves.channels(emptyList()).isEmpty())
    }
}
