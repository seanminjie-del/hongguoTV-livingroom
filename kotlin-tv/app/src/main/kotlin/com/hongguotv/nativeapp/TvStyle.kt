// SPDX-License-Identifier: GPL-3.0-only
package com.hongguotv.nativeapp

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.widget.LinearLayout

/** Shared native shapes keep focus clear without blur or extra image memory. */
object TvStyle {
    val background=Color.rgb(15,18,23)
    val surface=Color.rgb(24,28,34)
    val raised=Color.rgb(39,44,52)
    val accent=Color.rgb(255,137,100)
    val text=Color.rgb(243,244,246)
    val muted=Color.rgb(167,174,186)
    val outline=Color.rgb(57,64,75)
    const val POSTER_ASPECT=.7f
    fun captionHeight(card: LinearLayout)=card.paddingTop+card.paddingBottom+(1 until card.childCount).sumOf { index ->
        val view=card.getChildAt(index); val params=view.layoutParams as LinearLayout.LayoutParams
        view.measuredHeight+params.topMargin+params.bottomMargin
    }
    fun shape(context: Context,color: Int,border: Int=Color.TRANSPARENT,radius: Int=10)=GradientDrawable().apply {
        setColor(color); cornerRadius=radius*context.resources.displayMetrics.density
        setStroke((2*context.resources.displayMetrics.density).toInt(),border)
    }
    fun card(context: Context,focused: Boolean)=shape(context,if(focused) raised else background,if(focused) accent else Color.TRANSPARENT,radius=8)
}
