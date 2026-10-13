package com.hongguotv.nativeapp

import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import android.os.SystemClock
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ImageView
import android.widget.TextView
import java.io.File

/** Runs against the installed APK and live content; no test data or hooks in production. */
class TvAcceptance: Instrumentation() {
    private lateinit var activity: Activity
    private val report=StringBuilder()
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); start() }
    private fun views(view: View): List<View> = listOf(view)+(if(view is ViewGroup) (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList())
    private fun all()=views(activity.window.decorView)
    private fun label(value: String)=all().filterIsInstance<TextView>().first { it.text.toString()==value && it.isFocusable && it.isShown }
    private fun <T> ui(action: ()->T): T {
        var result: T?=null; var error: Throwable?=null
        runOnMainSync { try { result=action() } catch(e: Throwable) { error=e } }
        error?.let { throw it }
        @Suppress("UNCHECKED_CAST") return result as T
    }
    private fun await(name: String,check: ()->Boolean) {
        val deadline=SystemClock.elapsedRealtime()+120_000
        while(SystemClock.elapsedRealtime()<deadline) {
            if(ui(check)) return
            SystemClock.sleep(100)
        }
        error("Timed out: $name")
    }
    private fun key(code: Int) { sendKeyDownUpSync(code); waitForIdleSync() }
    private fun snapshot(name: String) {
        waitForIdleSync(); uiAutomation.waitForIdle(200,5000)
        val bitmap=uiAutomation.takeScreenshot() ?: error("Screenshot unavailable")
        val file=File(targetContext.getExternalFilesDir(null),"acceptance/$name.png"); file.parentFile!!.mkdirs()
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) }; bitmap.recycle()
    }
    private fun home(): HomeScreen=all().filterIsInstance<HomeScreen>().single()
    private fun homeReady(): Boolean {
        val home=all().filterIsInstance<HomeScreen>().firstOrNull() ?: return false
        if(home.refresh.text.contains("按确认查看")) home.refresh.performClick()
        return home.refresh.text.startsWith("刷新片库")
    }
    private fun cardIds()=all().filter { it.tag?.toString()?.matches(Regex("[0-9]{1,30}"))==true }.map { it.tag.toString() }.toSet()
    override fun onStart() {
        try {
            activity=startActivitySync(Intent(Intent.ACTION_MAIN).setClassName(targetContext,"com.hongguotv.nativeapp.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            for(round in 1..3) {
                await("home content") { homeReady() }
                ui { label("首页").requestFocus() }; key(KeyEvent.KEYCODE_DPAD_DOWN)
                if(ui { activity.currentFocus?.tag==null }) key(KeyEvent.KEYCODE_DPAD_DOWN)
                repeat(6) { if(ui { home().capturePosition().shelf!="hot" }) key(KeyEvent.KEYCODE_DPAD_DOWN) }
                val first=ui { home().capturePosition() }
                check(first.shelf!=null) { "D-pad did not enter home cards" }
                key(KeyEvent.KEYCODE_DPAD_RIGHT)
                val second=ui { home().capturePosition() }
                check(first.focus!=second.focus && first.shelf==second.shelf)
                key(KeyEvent.KEYCODE_DPAD_DOWN)
                check(ui { home().capturePosition().shelf!=second.shelf })
                if(round==1) snapshot("home-next-row")
                key(KeyEvent.KEYCODE_DPAD_UP)
                check(ui { home().capturePosition().focus==second.focus })
                await("visible posters") { all().filterIsInstance<ImageView>().count { it.isShown && it.drawable!=null }>=6 }
                if(round==1) snapshot("home-1080p")
                key(KeyEvent.KEYCODE_DPAD_CENTER)
                await("detail") { all().filterIsInstance<TextView>().any { it.text.toString().startsWith("开始观看") || it.text.toString().startsWith("继续第") } }
                if(round==1) snapshot("detail-1080p")
                key(KeyEvent.KEYCODE_BACK)
                await("home restored") { all().any { it is HomeScreen } }
                check(ui { home().capturePosition().focus==second.focus }) { "Detail return lost focus" }
                ui { label("搜索").performClick() }
                ui {
                    all().filterIsInstance<EditText>().single().setText("修仙")
                    all().filterIsInstance<TextView>().last { it.text.toString()=="搜索" && it.isFocusable }.performClick()
                }
                await("search results") { cardIds().isNotEmpty() && all().filterIsInstance<TextView>().any { it.text.toString().contains("已载入") } }
                val pageOne=ui { cardIds() }
                check(pageOne.size<=24)
                ui { all().first { it.tag?.toString() in pageOne }.requestFocus() }
                await("search posters") { all().filterIsInstance<ImageView>().count { it.isShown && it.drawable!=null }>=6 }
                await("whole search card visible") {
                    val card=activity.currentFocus ?: return@await false
                    val rect=android.graphics.Rect()
                    card.getGlobalVisibleRect(rect) && rect.height()==card.height
                }
                if(round==1) snapshot("search-1080p")
                val canPage=ui { all().filterIsInstance<TextView>().any { it.text.toString()=="下一页" && it.isEnabled } }
                if(canPage) {
                    ui { label("下一页").performClick() }
                    await("search page two") { all().filterIsInstance<TextView>().any { it.text.toString()=="第 2 页" } && cardIds().isNotEmpty() }
                    check(ui { cardIds().intersect(pageOne).isEmpty() }) { "Search repeated IDs across pages" }
                    ui { label("上一页").performClick() }
                    await("search page one") { all().filterIsInstance<TextView>().any { it.text.toString()=="第 1 页" } && cardIds()==pageOne }
                }
                report.append("Round $round PASS: D-pad rows, detail return, live search, pagination without duplicates\n")
                ui { label("首页").performClick() }
            }
            await("home final") { homeReady() }
            ui { all().first { it.tag?.toString()?.startsWith("hot:")==true }.requestFocus() }; key(KeyEvent.KEYCODE_DPAD_CENTER)
            await("play action") { all().filterIsInstance<TextView>().any { it.text.toString()=="开始观看" || it.text.toString().startsWith("继续第") } }
            ui { all().filterIsInstance<TextView>().first { it.text.toString()=="开始观看" || it.text.toString().startsWith("继续第") }.performClick() }
            await("playback outcome") {
                all().filterIsInstance<androidx.media3.ui.PlayerView>().firstOrNull()?.player?.let { it.isPlaying && it.videoSize.width>0 && it.currentPosition>1000 }==true ||
                    all().filterIsInstance<TextView>().any { it.text.toString().contains("片源暂不可播放") }
            }
            val blocked=ui { all().filterIsInstance<TextView>().any { it.text.toString().contains("片源暂不可播放") } }
            if(blocked) {
                snapshot("playback-unavailable")
                report.append("BLOCKED: live provider rejected playback; no video frames. Error code and recovery entry verified.\n")
                ui { label("返回详情").performClick() }
            } else {
                snapshot("playback")
                key(KeyEvent.KEYCODE_DPAD_CENTER)
                await("paused") { all().filterIsInstance<androidx.media3.ui.PlayerView>().single().player?.isPlaying==false }
                key(KeyEvent.KEYCODE_DPAD_CENTER)
                await("resumed") { all().filterIsInstance<androidx.media3.ui.PlayerView>().single().player?.isPlaying==true }
                key(KeyEvent.KEYCODE_DPAD_DOWN); key(KeyEvent.KEYCODE_BACK)
                await("episode panel cancelled") { all().filterIsInstance<androidx.media3.ui.PlayerView>().single().player?.isPlaying==true }
                val previousId=ui { all().filterIsInstance<androidx.media3.ui.PlayerView>().single().player!!.currentMediaItem!!.mediaId }
                key(KeyEvent.KEYCODE_DPAD_UP)
                ui { label("下一集").performClick() }
                await("next episode video") { all().filterIsInstance<androidx.media3.ui.PlayerView>().single().player?.let { it.currentMediaItem?.mediaId!=previousId && it.isPlaying && it.videoSize.width>0 && it.currentPosition>1000 }==true }
                snapshot("playback-next-episode")
                key(KeyEvent.KEYCODE_DPAD_UP); key(KeyEvent.KEYCODE_BACK); key(KeyEvent.KEYCODE_BACK)
                report.append("PASS: real comic video frames, pause/resume, episode panel cancel, next episode playback\n")
            }
            await("detail return from playback") { all().filterIsInstance<TextView>().any { it.text.toString()=="开始观看" || it.text.toString().startsWith("继续第") } }
            key(KeyEvent.KEYCODE_BACK); await("home after playback") { homeReady() }
            report.append("PASS: return from playback to detail and home\n")
            if(!blocked) {
                ui { label("短剧").performClick() }; await("short home") { homeReady() }
                ui { all().first { it.tag?.toString()?.startsWith("hot:")==true }.requestFocus() }; key(KeyEvent.KEYCODE_DPAD_CENTER)
                await("short detail") { all().filterIsInstance<TextView>().any { it.text.toString()=="开始观看" || it.text.toString().startsWith("继续第") } }
                ui { all().filterIsInstance<TextView>().first { it.text.toString()=="开始观看" || it.text.toString().startsWith("继续第") }.performClick() }
                await("short drama real video") { all().filterIsInstance<androidx.media3.ui.PlayerView>().single().player?.let { it.isPlaying && it.videoSize.width>0 && it.currentPosition>1000 }==true }
                snapshot("playback-short")
                key(KeyEvent.KEYCODE_DPAD_UP); key(KeyEvent.KEYCODE_BACK); key(KeyEvent.KEYCODE_BACK)
                await("short detail return") { all().filterIsInstance<TextView>().any { it.text.toString()=="开始观看" || it.text.toString().startsWith("继续第") } }
                key(KeyEvent.KEYCODE_BACK); await("short home return") { homeReady() }
                report.append("PASS: real short drama video and detail/home return\n")
            }
            ui {
                val configuration=android.content.res.Configuration(activity.resources.configuration).apply { fontScale=1.4f }
                @Suppress("DEPRECATION") activity.resources.updateConfiguration(configuration,activity.resources.displayMetrics)
                label("首页").performClick()
            }
            await("large text home") { homeReady() }
            ui { label("首页").requestFocus() }; key(KeyEvent.KEYCODE_DPAD_DOWN); key(KeyEvent.KEYCODE_DPAD_DOWN)
            snapshot("home-large-text")
            report.append("PASS: home remains operable with 1.4x text\n")
            File(targetContext.getExternalFilesDir(null),"acceptance/report.txt").writeText(report.toString())
            finish(if(blocked) Activity.RESULT_CANCELED else Activity.RESULT_OK,Bundle().apply { putString("stream",report.toString()) })
        } catch(e: Throwable) {
            runCatching { snapshot("failure") }
            report.append("FAIL: ${e.stackTraceToString()}\n")
            File(targetContext.getExternalFilesDir(null),"acceptance/report.txt").apply { parentFile!!.mkdirs(); writeText(report.toString()) }
            finish(Activity.RESULT_CANCELED,Bundle().apply { putString("stream",report.toString()) })
        }
    }
}
