// SPDX-License-Identifier: GPL-3.0-only
package com.hongguotv.core

import okhttp3.Request
import java.io.EOFException
import java.io.IOException
import java.io.InterruptedIOException
import java.net.NoRouteToHostException
import java.net.ProtocolException
import java.net.SocketException
import java.net.UnknownHostException

internal class HttpStatusException(val status:Int,val retryAfter:String?,message:String):IOException(message)

internal object NetworkRetry {
    fun <T> execute(request:Request,action:()->T):T {
        var retries=0
        while(true) {
            RequestScope.ensureActive()
            try { return action() }
            catch(error:IOException) {
                RequestScope.ensureActive()
                val transient=when(error) {
                    is HttpStatusException -> error.status in listOf(408,500,502,503,504) && error.retryAfter==null
                    is EOFException,is SocketException,is UnknownHostException,is NoRouteToHostException,is InterruptedIOException -> true
                    is ProtocolException -> error.message?.contains("unexpected end of stream",ignoreCase=true)==true
                    else -> false
                }
                if(request.method!="GET" || retries>=2 || !transient) throw error
                val delay=if(retries++==0) 300L else 900L
                // Navigation cancellation must interrupt the wait before a new call is created.
                repeat((delay/50).toInt()) { RequestScope.ensureActive();Thread.sleep(50) }
            }
        }
    }
}
