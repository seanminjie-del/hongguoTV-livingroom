package com.hongguotv.core
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
class SignerTest {
    @Test fun visitorSignatureMatchesJackotomOracleWithConsistentIdentity() {
        val rows=JSONArray(javaClass.getResource("/visitor-signing.json")!!.readText())
        for(i in 0 until rows.length()) {
            val row=rows.getJSONObject(i); val ts=row.getInt("ts")
            var seed=17L
            val signer=Signer({ ts.toLong()*1000 }, { seed=(seed*1664525+1013904223) and 0xffffffffL; seed/4294967296.0 },row.getString("nonce"),row.getLong("started"))
            val body=if(row.isNull("body")) null else row.getString("body").toByteArray()
            val device=row.getJSONObject("device").let { o -> o.keys().asSequence().associateWith { o.getString(it) } }
            assertEquals("visitor signature $i",row.getString("medusa"),signer.medusa(row.getString("url"),body,ts,device))
        }
    }
    @Test fun matchesPinnedJavaScriptOracleAcrossTimestampVariants() {
        val rows = JSONArray(javaClass.getResource("/signing.json")!!.readText())
        for (i in 0 until rows.length()) {
            val row=rows.getJSONObject(i); val ts=row.getInt("ts"); val url=row.getString("url"); val query=url.substringAfter('?')
            val body=if(row.isNull("body")) null else row.getString("body").toByteArray()
            var seed=17L
            val signer=Signer(clock={ts.toLong()*1000},random={ seed=(seed*1664525+1013904223) and 0xffffffffL; seed/4294967296.0 })
            assertEquals("branch $i",0,signer.branch(query,body,ts))
            assertEquals("hash $i",row.getString("hash"),signer.hashF13(sm3(query.toByteArray()),body?.let{digest("MD5",it)}?:ByteArray(16),ts).hex())
            assertEquals("gorgon $i",row.getString("gorgon"),signer.gorgon(query,body,ts,42131))
            assertEquals("helios $i",row.getString("helios"),signer.helios(ts))
        }
    }
}
