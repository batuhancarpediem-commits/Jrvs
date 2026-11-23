package com.batuhan.jarvis

import android.app.ActivityManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.BatteryManager
import android.os.Environment
import android.os.StatFs
import android.provider.AlarmClock
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Yerel komutlar: internet gerektirmeden telefonda yapılan işler. Eşleşme yoksa null döner (Gemini'ye gider). */
object Commands {

    interface Host {
        val ultron: Boolean
        fun startTimer(seconds: Int)
        fun clearHistory()
        fun setUltron(on: Boolean)
    }

    private val TR = Locale("tr", "TR")

    /** Küçük harfe çevirir ve Türkçe karakterleri ASCII'ye indirger: eşleştirmeyi kolaylaştırır. */
    fun fold(s: String): String {
        val sb = StringBuilder(s.length)
        for (ch in s.lowercase(TR)) {
            sb.append(
                when (ch) {
                    'ı' -> 'i'
                    'ş' -> 's'
                    'ç' -> 'c'
                    'ğ' -> 'g'
                    'ö' -> 'o'
                    'ü' -> 'u'
                    else -> ch
                }
            )
        }
        return sb.toString()
    }

    fun handle(ctx: Context, raw: String, host: Host): String? {
        val t = fold(raw).trim().trimEnd('.', '!', '?', ',')
        val words = t.split(Regex("\\s+")).filter { it.isNotEmpty() }
        fun fin(s: String) = if (host.ultron) "$s." else "$s efendim."

        // --- Mod değiştirme ---
        if (!host.ultron && t.contains("ultron")) {
            host.setUltron(true)
            return "Ultron devrede."
        }
        if (host.ultron && t.contains("jarvis")) {
            host.setUltron(false)
            return "Jarvis geri döndü efendim."
        }

        // --- Geçmişi sil ---
        if (t.contains("gecmis") && (t.contains("sil") || t.contains("temizle"))) {
            host.clearHistory()
            return "Geçmiş silindi."
        }

        // --- Saat / tarih ---
        if (Regex("saat kac|saati soyle").containsMatchIn(t)) {
            return fin("Saat " + SimpleDateFormat("HH:mm", TR).format(Date()))
        }
        if (Regex("bugunun tarihi|tarih ne|bugun tarih|bugun gunlerden|hangi gun|gunlerden ne|ayin kaci").containsMatchIn(t)) {
            return fin("Bugün " + SimpleDateFormat("d MMMM yyyy EEEE", TR).format(Date()))
        }

        // --- Zamanlayıcı ---
        val tm = Regex("(\\d{1,3})\\s*(dakika|dk|saniye|sn)").find(t)
        if (tm != null && Regex("zamanlayici|sayac|geri sayim|kronometre|timer").containsMatchIn(t)) {
            val n = tm.groupValues[1].toInt()
            val sec = tm.groupValues[2]
            return if (sec == "saniye" || sec == "sn") {
                host.startTimer(n)
                "$n saniyelik zamanlayıcı kuruldu."
            } else {
                host.startTimer(n * 60)
                "$n dakikalık zamanlayıcı kuruldu."
            }
        }

        // --- Alarm ---
        if (t.contains("alarm")) {
            var h = -1
            var m = 0
            val hm = Regex("(\\d{1,2})[ :.](\\d{2})").find(t)
            if (hm != null) {
                h = hm.groupValues[1].toInt()
                m = hm.groupValues[2].toInt()
            } else {
                val only = Regex("(\\d{1,2})").find(t)
                if (only != null) h = only.groupValues[1].toInt()
            }
            if (h !in 0..23 || m !in 0..59) return "Alarm için saati söyler misin?"
            return try {
                ctx.startActivity(
                    Intent(AlarmClock.ACTION_SET_ALARM)
                        .putExtra(AlarmClock.EXTRA_HOUR, h)
                        .putExtra(AlarmClock.EXTRA_MINUTES, m)
                        .putExtra(AlarmClock.EXTRA_MESSAGE, "Jarvis")
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                fin("Alarm %02d:%02d için hazırlandı".format(h, m))
            } catch (e: Exception) {
                "Alarm uygulaması bulunamadı."
            }
        }

        // --- WhatsApp mesajı ---
        if (t.contains("whatsapp") && Regex("mesaj|yaz|gonder").containsMatchIn(t)) {
            val stop = setOf(
                "jarvis", "ultron", "whatsapp", "whatsappa", "mesaj", "mesaji", "gonder",
                "gonderir", "misin", "yaz", "lutfen", "diye"
            )
            val msg = raw.split(Regex("\\s+"))
                .filter { w -> fold(w).replace(Regex("['’].*$"), "").trim(',', '.', '!', '?') !in stop }
                .joinToString(" ").trim()
            if (msg.isNotEmpty()) {
                return try {
                    val uri = Uri.parse("https://wa.me/?text=" + URLEncoder.encode(msg, "UTF-8"))
                    ctx.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    if (host.ultron) "WhatsApp açılıyor. Kişiyi seçip gönder tuşuna bas."
                    else "WhatsApp açılıyor efendim, kişiyi seçip gönder tuşuna basman yeterli."
                } catch (e: ActivityNotFoundException) {
                    "WhatsApp bulunamadı."
                }
            }
        }

        // --- Arama ---
        val digits = raw.filter { it.isDigit() }
        if (digits.length >= 3 && (words.contains("ara") || words.contains("arar") || t.contains("numarasini ara"))) {
            return try {
                ctx.startActivity(
                    Intent(Intent.ACTION_DIAL, Uri.parse("tel:$digits")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                fin("Arama ekranı hazır")
            } catch (e: ActivityNotFoundException) {
                "Arama uygulaması bulunamadı."
            }
        }

        // --- Sistem bilgisi ---
        val all = t.contains("sistem durum") || t.contains("sistem bilgi")
        val wantBat = all || words.any { it in setOf("pil", "pili", "batarya", "bataryam", "bataryayi", "sarj", "sarjim") }
        val wantRam = all || words.any { it in setOf("ram", "bellek", "bellegi", "belegi") }
        val wantDisk = all || words.any { it in setOf("depolama", "depolamayi", "disk", "hafiza", "hafizayi") }
        if (wantBat || wantRam || wantDisk) {
            val parts = ArrayList<String>()
            if (wantBat) {
                val (lvl, charging) = battery(ctx)
                parts.add("Pil yüzde $lvl" + if (charging) ", şarj oluyor." else ".")
            }
            if (wantRam) parts.add(ramText(ctx))
            if (wantDisk) parts.add(diskText())
            return parts.joinToString(" ")
        }

        // --- Uygulama aç ---
        val openMatch = Regex("^(.*?)\\s*(uygulamasini|uygulamasi|uygulamayi|uygulama)?\\s*(acar misin|acsana|ac|baslat|calistir)$")
            .find(t)
        if (openMatch != null) {
            val hasApp = openMatch.groupValues[2].isNotEmpty()
            val stopWords = setOf("jarvis", "ultron", "lutfen", "bana", "bir", "su", "sunu")
            val name = openMatch.groupValues[1].split(" ")
                .map { it.replace(Regex("['’].*$"), "") }
                .filter { it.isNotEmpty() && it !in stopWords }
                .joinToString(" ")
            if (name.isNotEmpty() && (hasApp || name.split(" ").size <= 3)) {
                val found = findApp(ctx, name)
                if (found != null) {
                    ctx.startActivity(found.second.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    return fin("${found.first} açılıyor")
                }
                if (hasApp) return "Böyle bir uygulama bulamadım efendim."
            }
        }

        return null
    }

    // ------------------------------------------------------------------------------------

    private fun findApp(ctx: Context, name: String): Pair<String, Intent>? {
        val pm = ctx.packageManager
        val apps = pm.getInstalledApplications(0).mapNotNull { info ->
            val intent = pm.getLaunchIntentForPackage(info.packageName) ?: return@mapNotNull null
            val label = pm.getApplicationLabel(info).toString()
            Triple(label, fold(label), intent)
        }
        val hit = apps.firstOrNull { it.second == name }
            ?: apps.firstOrNull { it.second.startsWith(name) }
            ?: apps.firstOrNull { it.second.contains(name) }
            ?: apps.firstOrNull { it.second.length >= 3 && name.contains(it.second) }
        return hit?.let { it.first to it.third }
    }

    fun battery(ctx: Context): Pair<Int, Boolean> {
        val bm = ctx.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val st = ctx.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val status = st?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        return level to charging
    }

    fun ramPercent(ctx: Context): Int {
        val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mi)
        if (mi.totalMem <= 0) return 0
        return (100 - mi.availMem * 100 / mi.totalMem).toInt()
    }

    fun diskPercent(): Int {
        val fs = StatFs(Environment.getDataDirectory().path)
        if (fs.totalBytes <= 0) return 0
        return (100 - fs.availableBytes * 100 / fs.totalBytes).toInt()
    }

    private fun gb(b: Long) = "%.1f".format(TR, b / 1_073_741_824.0)

    private fun ramText(ctx: Context): String {
        val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mi)
        return "Bellek ${gb(mi.totalMem - mi.availMem)} gigabayt dolu, toplam ${gb(mi.totalMem)}."
    }

    private fun diskText(): String {
        val fs = StatFs(Environment.getDataDirectory().path)
        return "Depolamanın yüzde ${diskPercent()} kadarı dolu, ${gb(fs.availableBytes)} gigabayt boş."
    }

    /** Ekrandaki küçük durum satırı */
    fun sysLine(ctx: Context): String {
        val (lvl, ch) = battery(ctx)
        return "PİL %$lvl${if (ch) "+" else ""}  ·  RAM %${ramPercent(ctx)}  ·  DEPO %${diskPercent()}"
    }
}
