// SPDX-License-Identifier: GPL-3.0-only
package com.hongguotv.nativeapp

import android.content.Context
import android.graphics.Typeface
import android.text.TextUtils
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.widget.*
import com.hongguotv.core.Series

/** Fixed text slots keep D-pad movement from resizing the content below the preview. */
class SeriesPreview(context: Context,compact: Boolean=false,metadata: Boolean=true): LinearLayout(context) {
    private fun label(size: Float,color: Int)=TextView(context).apply { textSize=size; setTextColor(color); includeFontPadding=false }
    private val title=label(if(compact) 20f else 25f,TvStyle.text).apply { minLines=1; maxLines=1; ellipsize=TextUtils.TruncateAt.END; typeface=Typeface.create("sans-serif-medium",Typeface.NORMAL) }
    private val meta=label(if(compact) 12f else 13f,TvStyle.muted).apply { visibility=if(metadata) VISIBLE else GONE; minLines=1; maxLines=1; ellipsize=TextUtils.TruncateAt.END }
    private val description=label(13f,TvStyle.muted).apply { minLines=2; maxLines=2; ellipsize=TextUtils.TruncateAt.END }
    init {
        orientation=HORIZONTAL; gravity=Gravity.CENTER_VERTICAL
        val dp=resources.displayMetrics.density
        setPadding(0,((if(compact) 5 else 8)*dp).toInt(),0,(8*dp).toInt())
        val details=LinearLayout(context).apply { orientation=VERTICAL; addView(title); addView(meta,LayoutParams(-1,-2).apply { topMargin=(4*dp).toInt() }) }
        addView(details,LayoutParams(0,-2,1f))
        if(!compact && resources.displayMetrics.widthPixels/dp>=900 && resources.configuration.fontScale<=1.2f) addView(description,LayoutParams((260*dp).toInt(),-2).apply { leftMargin=(28*dp).toInt() })
        show(null,"")
    }
    fun show(series: Series?,status: String) {
        val nextTitle=series?.title ?: "选一部，开始看"
        val nextMeta=if(series==null) "确认查看剧集 · 长按管理片单" else listOf(status,series.badge,series.tags).flatMap { it.split('·') }.map(String::trim).filter { it.isNotBlank() && !it.all(Char::isDigit) }.distinct().joinToString("  /  ")
        if(title.text.toString()!=nextTitle) title.text=nextTitle
        if(meta.text.toString()!=nextMeta) meta.text=nextMeta
        description.text=series?.description.orEmpty().replace('\n',' ')
    }
}

/** One active topic grid with independent channel positions and explicit D-pad boundaries. */
class HomeScreen(
    context: Context,
    private val top: View,
    private val preview: SeriesPreview,
    private val loadCover: (ImageView,String)->Unit,
    private val selected: (Series,String)->Unit,
    private val open: (Series,Boolean)->Unit,
    private val actions: (Series,View)->Unit,
    private val remember: (String)->Unit,
    private val connectTop: (Int)->Unit
): LinearLayout(context) {
    data class Entry(val series: Series,val label: String,val resume: Boolean=false,val progress: Int?=null)
    data class Shelf(val key: String,val title: String,val entries: List<Entry>,val more: (() -> Unit)?=null)
    data class ChannelPosition(val focus: String,val index: Int,val vertical: Int)
    data class Position(val focus: String,val shelf: String?,val column: Int,val row: Int,val vertical: Int,val channels: Map<String,ChannelPosition>)
    private data class Card(val key: String,val view: LinearLayout,val image: ImageView?,val entry: Entry?)
    private val large=resources.configuration.fontScale>1.2f
    private var columns=if(large || resources.displayMetrics.widthPixels/resources.displayMetrics.density<900) 5 else 7
    private val railWidth=if(large) 174 else 146
    private fun dp(n: Int)=(n*resources.displayMetrics.density).toInt()
    private fun label(value: String,size: Float,color: Int=TvStyle.text)=TextView(context).apply { text=value; textSize=size; setTextColor(color); includeFontPadding=false }
    private val railScroll=ScrollView(context).apply { isVerticalScrollBarEnabled=false }
    private val rail=LinearLayout(context).apply { orientation=VERTICAL }
    private val channelHeading=label("题材频道",13f,TvStyle.muted).apply { setPadding(dp(10),dp(4),0,dp(10)) }
    private val side=LinearLayout(context).apply { orientation=VERTICAL }
    private val pane=LinearLayout(context).apply { orientation=VERTICAL }
    private val heading=label("热门发现",20f).apply { typeface=Typeface.create("sans-serif-medium",Typeface.NORMAL); maxLines=1; ellipsize=TextUtils.TruncateAt.END }
    private val count=label("",12f,TvStyle.muted)
    private val scroll=ScrollView(context).apply { isVerticalScrollBarEnabled=false; clipToPadding=false; setPadding(dp(2),dp(2),dp(2),dp(2)) }
    private val contents=LinearLayout(context).apply { orientation=VERTICAL }
    private val channels=linkedMapOf<String,TextView>()
    private val positions=linkedMapOf<String,ChannelPosition>()
    private val cards=mutableListOf<Card>()
    private var shelves=emptyList<Shelf>()
    private var active="hot"
    private var lastFocus=""
    private var restoring=false
    private var revision=0
    private var footerMore: (() -> Unit)?=null
    private val footer=LinearLayout(context).apply { orientation=VERTICAL; setPadding(0,dp(6),0,0) }
    val refresh=label("正在更新热门…",12f,TvStyle.muted).apply {
        id=View.generateViewId(); tag="home:refresh"; isFocusable=true; isFocusableInTouchMode=true
        maxLines=3; ellipsize=TextUtils.TruncateAt.END; minHeight=dp(36); gravity=Gravity.CENTER_VERTICAL
        setPadding(dp(10),dp(6),dp(10),dp(6)); background=TvStyle.card(context,false)
        setOnFocusChangeListener { _,f -> background=TvStyle.card(context,f) }
    }
    private val moreButton=label("更多热门 ›",13f).apply {
        id=View.generateViewId(); tag="home:more"; isFocusable=true; isFocusableInTouchMode=true
        setPadding(dp(10),dp(8),dp(10),dp(8)); background=TvStyle.card(context,false)
        setOnFocusChangeListener { _,f -> background=TvStyle.card(context,f) }; setOnClickListener { footerMore?.invoke() }
    }
    init {
        orientation=HORIZONTAL; clipChildren=false
        railScroll.addView(rail)
        side.addView(channelHeading)
        side.addView(railScroll,LayoutParams(-1,0))
        side.addView(Space(context),LayoutParams(-1,0,1f)); side.addView(footer)
        footer.addOnLayoutChangeListener { _,_,top,_,bottom,_,oldTop,_,oldBottom -> if(bottom-top!=oldBottom-oldTop) post { fitChannels() } }
        rail.addOnLayoutChangeListener { _,_,top,_,bottom,_,oldTop,_,oldBottom -> if(bottom-top!=oldBottom-oldTop) post { fitChannels() } }
        addView(side,LayoutParams(dp(railWidth),-1).apply { rightMargin=dp(16) })
        addView(pane,LayoutParams(0,-1,1f))
        val titleRow=LinearLayout(context).apply { orientation=HORIZONTAL; gravity=Gravity.CENTER_VERTICAL }
        titleRow.addView(heading,LayoutParams(0,-2,1f)); titleRow.addView(count)
        pane.addView(titleRow); pane.addView(preview)
        scroll.addView(contents); pane.addView(scroll,LayoutParams(-1,0,1f))
        footer.addView(refresh,LayoutParams(-1,-2)); footer.addView(moreButton,LayoutParams(-1,-2))
    }
    private fun saveChannel() {
        val index=cards.indexOfFirst { it.key==lastFocus }.coerceAtLeast(0)
        positions[active]=ChannelPosition(lastFocus,index,scroll.scrollY)
    }
    fun capturePosition(): Position {
        saveChannel()
        val index=cards.indexOfFirst { it.key==lastFocus }.coerceAtLeast(0)
        return Position(findFocus()?.tag?.toString() ?: lastFocus,active,index%columns,index/columns,scroll.scrollY,positions.toMap())
    }
    fun updateShelves(next: List<Shelf>,requestFocus: Boolean=hasFocus()) {
        val position=capturePosition(); render(next,position.focus,requestFocus,footerMore,position)
    }
    fun refreshSelection() { cards.firstOrNull { it.key==lastFocus }?.entry?.let { selected(it.series,it.label) } }
    fun reloadArtwork()=loadNearbySelection()

    fun render(shelves: List<Shelf>,focus: String,requestFocus: Boolean,more: (() -> Unit)?,position: Position?=null) {
        this.shelves=shelves.filter { it.entries.isNotEmpty() || it.key=="hot" }; footerMore=more
        position?.let { positions.clear(); positions.putAll(it.channels) }
        active=position?.shelf?.takeIf { key -> this.shelves.any { it.key==key } }
            ?: focus.substringBefore(':').takeIf { key -> this.shelves.any { it.key==key } } ?: "hot"
        if(this.shelves.none { it.key==active }) active=this.shelves.firstOrNull()?.key ?: "hot"
        rail.removeAllViews(); channels.clear()
        this.shelves.forEach { shelf ->
            val button=label(shelf.title,14f).apply {
                id=View.generateViewId(); tag="channel:${shelf.key}"; isFocusable=true; isFocusableInTouchMode=true
                minHeight=dp(42); maxLines=2; gravity=Gravity.CENTER_VERTICAL; setPadding(dp(10),dp(8),dp(8),dp(8))
                contentDescription="${shelf.title}，${shelf.entries.size} 部，确认切换频道"
                setOnFocusChangeListener { _,_ -> paintChannels() }
                setOnClickListener { if(active!=shelf.key) { saveChannel(); active=shelf.key; showChannel(false) }; paintChannels() }
                setOnKeyListener { _,key,event ->
                    if(key==KeyEvent.KEYCODE_DPAD_RIGHT) { if(event.action==KeyEvent.ACTION_DOWN) enterContent(); true } else false
                }
            }
            rail.addView(button,LayoutParams(-1,-2).apply { bottomMargin=dp(4) }); channels[shelf.key]=button
        }
        channels.values.toList().forEachIndexed { i,v ->
            v.nextFocusUpId=channels.values.toList().getOrNull(i-1)?.id ?: top.id
            v.nextFocusDownId=channels.values.toList().getOrNull(i+1)?.id ?: refresh.id
            v.nextFocusLeftId=v.id
        }
        moreButton.visibility=if(more==null) GONE else VISIBLE
        showChannel(false)
        val preferred=position?.focus ?: focus
        if(requestFocus) when {
            preferred.startsWith("channel:") -> (channels[preferred.removePrefix("channel:")] ?: channels[active])?.requestFocus()
            preferred=="home:refresh" -> refresh.requestFocus()
            preferred=="home:more" && more!=null -> moreButton.requestFocus()
            else -> { cards.firstOrNull { it.key==preferred }?.let { lastFocus=it.key }; enterContent() }
        }
        top.nextFocusDownId=firstId()
    }
    private fun paintChannels() {
        channels.forEach { (key,v) ->
            v.isSelected=key==active
            v.background=TvStyle.shape(context,if(v.hasFocus()) TvStyle.raised else if(key==active) 0xFF30201D.toInt() else TvStyle.background,if(v.hasFocus()) TvStyle.accent else android.graphics.Color.TRANSPARENT,8)
            v.setTextColor(if(key==active) TvStyle.accent else TvStyle.text)
            v.setTypeface(null,if(key==active || v.hasFocus()) Typeface.BOLD else Typeface.NORMAL)
        }
    }
    private fun showChannel(requestFocus: Boolean) {
        revision++; val ticket=revision; restoring=true
        contents.removeAllViews(); cards.clear()
        val shelf=shelves.firstOrNull { it.key==active }
        heading.text=shelf?.title ?: "热门发现"; count.text="${shelf?.entries?.size ?: 0} 部"
        val saved=positions[active]
        val entries=shelf?.entries.orEmpty()
        columns=if(large || resources.displayMetrics.widthPixels/resources.displayMetrics.density<900 || entries.size<=7) 5 else 7
        val width=((resources.displayMetrics.widthPixels*.9f-dp(railWidth+16+4)-dp(8)*(columns-1))/columns).toInt().coerceAtLeast(dp(64))
        val groups: List<Entry?> = entries+(if(shelf?.more!=null) listOf(null) else emptyList())
        groups.chunked(columns).forEach { items ->
            val line=LinearLayout(context).apply { orientation=HORIZONTAL; gravity=Gravity.TOP }
            items.forEachIndexed { column,entry ->
                val key=if(entry!=null) "$active:${entry.series.id}" else "$active:more"
                val view=LinearLayout(context).apply { orientation=VERTICAL; id=View.generateViewId(); tag=key; isFocusable=true; isFocusableInTouchMode=true; setPadding(dp(3),dp(3),dp(3),dp(6)); background=TvStyle.card(context,false) }
                val image=entry?.let { ImageView(context).apply { scaleType=ImageView.ScaleType.FIT_CENTER; background=TvStyle.shape(context,TvStyle.surface,radius=6); clipToOutline=true; importantForAccessibility=IMPORTANT_FOR_ACCESSIBILITY_NO } }
                view.addView(image ?: label("›",36f).apply { gravity=Gravity.CENTER },LayoutParams(-1,((width-dp(6))/TvStyle.POSTER_ASPECT).toInt()))
                view.addView(label(entry?.series?.title ?: "查看全部",14f).apply { minLines=2; maxLines=2; ellipsize=TextUtils.TruncateAt.END; setPadding(dp(2),dp(5),dp(2),0); typeface=Typeface.create("sans-serif-medium",Typeface.NORMAL) })
                view.addView(label(entry?.label ?: shelf?.title.orEmpty(),12f,TvStyle.muted).apply { minLines=1; maxLines=1; ellipsize=TextUtils.TruncateAt.END; setPadding(dp(2),dp(2),0,0) })
                if(entry?.progress!=null) view.addView(ProgressBar(context,null,android.R.attr.progressBarStyleHorizontal).apply { max=100; progress=entry.progress; progressTintList=android.content.res.ColorStateList.valueOf(TvStyle.accent) },LayoutParams(-1,dp(3)).apply { topMargin=dp(3) })
                val card=Card(key,view,image,entry); cards+=card
                view.contentDescription=entry?.let { "${shelf?.title}，${it.series.title}，${it.label}，${if(it.resume) "确认继续观看" else "确认查看剧集"}" } ?: "查看全部${shelf?.title}"
                view.setOnClickListener { lastFocus=key; remember(key); entry?.let { open(it.series,it.resume) } ?: shelf?.more?.invoke() }
                view.setOnLongClickListener { entry?.let { actions(it.series,view) }; entry!=null }
                view.setOnKeyListener { _,code,event ->
                    when {
                        code==KeyEvent.KEYCODE_MENU && entry!=null -> { if(event.action==KeyEvent.ACTION_UP) actions(entry.series,view); true }
                        code==KeyEvent.KEYCODE_DPAD_LEFT && column==0 -> { if(event.action==KeyEvent.ACTION_DOWN) channels[active]?.requestFocus(); true }
                        else -> false
                    }
                }
                view.setOnFocusChangeListener { _,f ->
                    view.background=TvStyle.card(context,f)
                    view.animate().cancel(); view.animate().alpha(if(f) 1f else .94f).setDuration(100).start()
                    if(f) {
                        lastFocus=key; remember(key); entry?.let { selected(it.series,it.label) }
                        top.nextFocusDownId=view.id; connectTop(view.id)
                        refresh.nextFocusRightId=view.id; moreButton.nextFocusRightId=view.id
                        if(!restoring) { reveal(view,true); loadNearbySelection() }
                    }
                }
                line.addView(view,LayoutParams(width,-2).apply { if(column<columns-1) rightMargin=dp(8) })
            }
            contents.addView(line,LayoutParams(-1,-2).apply { bottomMargin=dp(8) })
        }
        if(cards.isEmpty()) {
            contents.addView(label("还没有可显示的剧集。可刷新片库，或在设置中恢复隐藏推荐。",16f,TvStyle.muted).apply { setPadding(dp(8),dp(28),dp(8),dp(16)) })
            preview.show(null,"")
        }
        lastFocus=cards.firstOrNull { it.key==saved?.focus }?.key ?: cards.getOrNull((saved?.index ?: 0).coerceIn(0,(cards.size-1).coerceAtLeast(0)))?.key.orEmpty()
        cards.forEachIndexed { i,card ->
            card.view.nextFocusLeftId=if(i%columns==0) channels[active]?.id ?: top.id else cards[i-1].view.id
            card.view.nextFocusRightId=if(i%columns==columns-1 || i==cards.lastIndex) card.view.id else cards[i+1].view.id
            card.view.nextFocusUpId=cards.getOrNull(i-columns)?.view?.id ?: top.id
            card.view.nextFocusDownId=cards.getOrNull(i+columns)?.view?.id ?: if(i/columns<cards.lastIndex/columns) cards.last().view.id else refresh.id
        }
        refresh.nextFocusUpId=cards.lastOrNull()?.view?.id ?: channels[active]?.id ?: top.id
        refresh.nextFocusDownId=if(footerMore!=null) moreButton.id else refresh.id; refresh.nextFocusLeftId=refresh.id; refresh.nextFocusRightId=firstId()
        moreButton.nextFocusUpId=refresh.id; moreButton.nextFocusDownId=moreButton.id; moreButton.nextFocusLeftId=moreButton.id; moreButton.nextFocusRightId=firstId()
        paintChannels(); refreshSelection(); connectTop(firstId())
        scroll.animate().cancel(); scroll.alpha=.92f; scroll.animate().alpha(1f).setDuration(140).start()
        post layout@{
            if(ticket!=revision) return@layout
            fitArtwork(); fitChannels()
            post restore@{
                if(ticket!=revision) return@restore
                scroll.scrollTo(0,saved?.vertical ?: 0); restoring=false
                if(requestFocus) enterContent()
                cards.firstOrNull { it.view.hasFocus() }?.let { reveal(it.view,false) }
                loadNearbySelection()
            }
        }
    }
    private fun enterContent() {
        (cards.firstOrNull { it.key==lastFocus }?.view ?: cards.firstOrNull()?.view ?: refresh).requestFocus()
    }
    private fun reveal(view: View,smooth: Boolean) {
        val line=view.parent as View
        val target=if(large) line.top else when { line.top<scroll.scrollY -> line.top; line.bottom>scroll.scrollY+scroll.height -> line.bottom-scroll.height; else -> scroll.scrollY }.coerceAtLeast(0)
        if(smooth) scroll.smoothScrollTo(0,target) else scroll.scrollTo(0,target)
    }
    private fun loadNearbySelection() {
        if(restoring || cards.isEmpty()) return
        val index=cards.indexOfFirst { it.key==lastFocus }.coerceAtLeast(0)
        val first=((index/columns-1).coerceAtLeast(0))*columns
        cards.subList(first,minOf(cards.size,(index/columns+3)*columns)).forEach { card ->
            val image=card.image ?: return@forEach
            if(image.isLaidOut && !image.isLayoutRequested) loadCover(image,card.entry!!.series.cover)
        }
    }
    /** Keep the fixed footer from cutting the final visible channel in half. */
    private fun fitChannels() {
        val available=side.height-channelHeading.height-footer.height
        if(available<=0 || rail.childCount==0) return
        val complete=(0 until rail.childCount).map { index ->
            val child=rail.getChildAt(index)
            child.bottom+(child.layoutParams as LayoutParams).bottomMargin
        }.lastOrNull { it<=available } ?: available
        if(railScroll.layoutParams.height!=complete) railScroll.layoutParams=railScroll.layoutParams.apply { height=complete }
    }
    private fun fitArtwork() {
        if(scroll.height<=0 || cards.isEmpty()) return
        val caption=cards.maxOf { TvStyle.captionHeight(it.view) }
        val desired=((cards.first().view.width-dp(6))/TvStyle.POSTER_ASPECT).toInt()
        val budget=if(large || cards.size<=columns) scroll.height else (scroll.height-dp(16))/2
        val imageHeight=minOf(desired,(budget-caption).coerceAtLeast(dp(64)))
        cards.forEach { card -> card.view.getChildAt(0).let { image -> if(image.layoutParams.height!=imageHeight) image.layoutParams=image.layoutParams.apply { height=imageHeight } } }
    }
    override fun onAttachedToWindow() { super.onAttachedToWindow(); post { reloadArtwork() } }
    override fun onSizeChanged(w: Int,h: Int,oldw: Int,oldh: Int) { super.onSizeChanged(w,h,oldw,oldh); if(w!=oldw || h!=oldh) post { fitArtwork(); fitChannels(); post { loadNearbySelection() } } }
    fun firstId()=cards.firstOrNull { it.key==lastFocus }?.view?.id ?: cards.firstOrNull()?.view?.id ?: refresh.id
}
