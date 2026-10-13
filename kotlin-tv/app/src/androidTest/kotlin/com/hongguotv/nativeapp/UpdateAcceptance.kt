package com.hongguotv.nativeapp

import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import java.io.File

/** Tests the real updater's persisted channel migration without production test hooks. */
class UpdateAcceptance: Instrumentation() {
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); start() }
    override fun onStart() {
        val prefs=targetContext.getSharedPreferences("app_updates",Activity.MODE_PRIVATE)
        val before=prefs.all.toMap()
        var result=Activity.RESULT_CANCELED
        var report=""
        try {
            prefs.edit().putString("channel","N3urda/hongguoTV-updates")
                .putLong("last_attempt",System.currentTimeMillis()).putBoolean("automatic",false).commit()
            startActivitySync(Intent(Intent.ACTION_MAIN).setClassName(targetContext,"com.hongguotv.nativeapp.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            check(!prefs.contains("last_attempt")) { "Previous channel's six-hour check window still suppresses the new channel" }
            check(!prefs.getBoolean("automatic",true)) { "Migration re-enabled the user's disabled automatic updates" }
            result=Activity.RESULT_OK; report="PASS: channel migration clears old check throttle and preserves automatic preference\n"
        } catch(e: Throwable) { report="FAIL: ${e.stackTraceToString()}" }
        finally {
            val edit=prefs.edit().clear()
            before.forEach { (key,value) -> when(value) { is String -> edit.putString(key,value); is Long -> edit.putLong(key,value); is Boolean -> edit.putBoolean(key,value); is Int -> edit.putInt(key,value) } }
            edit.commit()
        }
        File(targetContext.getExternalFilesDir(null),"update-acceptance/migration.txt").apply { parentFile!!.mkdirs(); writeText(report) }
        finish(result,Bundle().apply { putString("stream",report) })
    }
}
