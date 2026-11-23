#!/usr/bin/env bash
# JARVIS (insan silüetli arayüz)
# Projeyi sıfırdan yazar, APK'yı derler ve GitHub'a yükler.
# Kullanım (Codespaces terminali, deponun ana klasöründe):  bash kur.sh
set -e
cd "$(dirname "$0")"

echo "== 1/5 Dosyalar yaziliyor =="
mkdir -p "$(dirname ".gitignore")"
cat > ".gitignore" <<'__JARVIS_DOSYA_SONU__'
.gradle/
build/
local.properties
.idea/
*.iml
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "README.md")"
cat > "README.md" <<'__JARVIS_DOSYA_SONU__'
# JARVIS (insan silüetli arayüz)

Eski APK'daki (`com.batuhan.jarvis`) özelliklerin hepsi korunarak yeniden yazıldı.
Yuvarlak "orb" yerine **insan silüeti** çizen `HoloView` geldi ve konuşmaya göre hareket eder.

## Kurulum
1. Android Studio (Koala veya üstü) ile bu klasörü aç, Gradle senkronizasyonunu bekle.
2. Telefonu bağla, Run. Ya da `Build > Build APK(s)`.
3. Uygulamada AYARLAR'dan Gemini API anahtarını gir.

## Özellikler
- Gemini (google_search aracı açık), konuşma geçmişi (son 20 mesaj)
- Türkçe ses tanıma + Türkçe TTS
- "Jarvis ..." uyanma kelimesi (MİKROFON AÇIK düğmesi)
- Jarvis / Ultron kişilik ve renk modu (mavi / kırmızı)
- Yerel komutlar: uygulama aç, numara ara, alarm kur, zamanlayıcı, WhatsApp mesajı,
  pil / RAM / depolama, saat ve tarih, geçmişi sil
- Zamanlayıcı kısayolları ve bildirim

## HoloView hareketleri
| Durum | Hareket |
|---|---|
| Konuşuyor | Her kelimede nabız, ağız açılır, baş sallanır, göğüste ses spektrumu, silüetten dışa dalgalar |
| Dinliyor | Mikrofon seviyesiyle başın yanındaki parantezler genişler, gözler büyür |
| Düşünüyor | Tarama bandı hızlanır, sinir ağı titrer, baş yana yatar, üstte yanıp sönen noktalar |
| Boşta | Nefes alma, göz kırpma, yavaş tarama |

Kelime vurguları `UtteranceProgressListener.onRangeStart` ile gelir. TTS motoru bunu vermezse
animasyon kendi ritmini üretir.
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "app/build.gradle.kts")"
cat > "app/build.gradle.kts" <<'__JARVIS_DOSYA_SONU__'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.batuhan.jarvis"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.batuhan.jarvis"
        minSdk = 26
        targetSdk = 34
        versionCode = 2
        versionName = "2.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
}
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "app/src/main/AndroidManifest.xml")"
cat > "app/src/main/AndroidManifest.xml" <<'__JARVIS_DOSYA_SONU__'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES" />
    <uses-permission android:name="com.android.alarm.permission.SET_ALARM" />

    <queries>
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE" />
        </intent>
        <intent>
            <action android:name="android.speech.RecognitionService" />
        </intent>
    </queries>

    <application
        android:allowBackup="false"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:theme="@style/Theme.Jarvis">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:screenOrientation="portrait"
            android:configChanges="orientation|screenSize|keyboardHidden"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "app/src/main/java/com/batuhan/jarvis/Commands.kt")"
cat > "app/src/main/java/com/batuhan/jarvis/Commands.kt" <<'__JARVIS_DOSYA_SONU__'
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
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "app/src/main/java/com/batuhan/jarvis/GeminiClient.kt")"
cat > "app/src/main/java/com/batuhan/jarvis/GeminiClient.kt" <<'__JARVIS_DOSYA_SONU__'
package com.batuhan.jarvis

import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class Reply(val ok: Boolean, val text: String)

object GeminiClient {

    private const val BASE = "https://generativelanguage.googleapis.com/v1beta/models/"

    /** Ağ çağrısı yapar; arka plan thread'inde çalıştırılmalı. */
    fun call(
        apiKey: String,
        model: String,
        systemPrompt: String,
        history: List<Pair<String, String>>,
        userText: String
    ): Reply {
        if (apiKey.isBlank()) return Reply(false, "Ayarlardan Gemini anahtarını girmen gerekiyor.")
        val m = model.trim()
        var conn: HttpURLConnection? = null
        try {
            conn = URL("$BASE$m:generateContent").openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.connectTimeout = 15000
            conn.readTimeout = 60000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("x-goog-api-key", apiKey)

            val contents = JSONArray()
            for ((role, text) in history) contents.put(turn(role, text))
            contents.put(turn("user", userText))

            val body = JSONObject()
                .put("systemInstruction", JSONObject().put("parts", JSONArray().put(JSONObject().put("text", systemPrompt))))
                .put("contents", contents)
                .put("tools", JSONArray().put(JSONObject().put("google_search", JSONObject())))

            // Düşünme seviyesi yalnızca Gemini 3 ailesinde destekleniyor
            if (m.startsWith("gemini-3")) {
                body.put(
                    "generationConfig",
                    JSONObject().put("thinkingConfig", JSONObject().put("thinkingLevel", "minimal"))
                )
            }

            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }

            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val raw = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
            if (code !in 200..299) return Reply(false, "Hata $code. Anahtarı ve model adını kontrol et.")

            val parts = JSONObject(raw)
                .optJSONArray("candidates")?.optJSONObject(0)
                ?.optJSONObject("content")?.optJSONArray("parts")
            val sb = StringBuilder()
            if (parts != null) {
                for (i in 0 until parts.length()) {
                    val p = parts.optJSONObject(i) ?: continue
                    if (p.optBoolean("thought", false)) continue
                    sb.append(p.optString("text", ""))
                }
            }
            val text = sb.toString().trim()
            return if (text.isEmpty()) Reply(false, "Cevap alamadım efendim, tekrar dener misin?")
            else Reply(true, text)
        } catch (e: Exception) {
            return Reply(false, "Bağlantı hatası. İnternetini kontrol et.")
        } finally {
            conn?.disconnect()
        }
    }

    private fun turn(role: String, text: String): JSONObject =
        JSONObject().put("role", role).put("parts", JSONArray().put(JSONObject().put("text", text)))
}
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "app/src/main/java/com/batuhan/jarvis/HoloView.kt")"
cat > "app/src/main/java/com/batuhan/jarvis/HoloView.kt" <<'__JARVIS_DOSYA_SONU__'
package com.batuhan.jarvis

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.util.AttributeSet
import android.view.View
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * Yuvarlak "orb" yerine insan silüeti (baş + boyun + omuzlar) çizen holografik arayüz.
 *
 * Konuşmaya göre hareket eder:
 *  - SPEAKING : kelime başına nabız (onWord), ağız açılır, baş hafifçe sallanır,
 *               göğüste ses spektrumu oynar, silüetten dışa doğru dalgalar yayılır.
 *  - LISTENING: mikrofon seviyesine (onVoiceLevel) göre başın iki yanında parantezler genişler.
 *  - THINKING : tarama çizgisi hızlanır, sinir ağı düğümleri titrer, baş hafif yana yatar.
 *  - IDLE     : nefes alma, göz kırpma, yavaş tarama.
 */
class HoloView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    enum class State { IDLE, LISTENING, THINKING, SPEAKING }

    var state: State = State.IDLE

    var accent: Int = Color.parseColor("#2AB7FF")
        set(value) {
            field = value
            rebuildShaders()
            invalidate()
        }

    var bg: Int = Color.parseColor("#05080F")
        set(value) {
            field = value
            rebuildShaders()
            invalidate()
        }

    // ---- Dışarıdan sürülen değerler ----------------------------------------------------

    /** TTS her kelimeye başladığında çağrılır. strength 0..1 */
    fun onWord(strength: Float = 1f) {
        pulse = max(pulse, (0.55f + 0.45f * strength).coerceIn(0f, 1f))
        sinceWord = 0f
    }

    /** Mikrofon seviyesi 0..1 */
    fun onVoiceLevel(v: Float) {
        ext = max(ext, v.coerceIn(0f, 1f))
    }

    // ---- İç durum ---------------------------------------------------------------------

    private var pulse = 0f
    private var ext = 0f
    private var level = 0f
    private var sinceWord = 0f
    private var t = 0f
    private var lastNs = 0L

    private var blinkIn = 2.5f
    private var blinkT = -1f
    private var eyeOpen = 1f

    private var rippleTimer = 0f
    private val ripples = ArrayList<Float>()

    // ---- Geometri (tasarım uzayı 200 x 300) --------------------------------------------

    private val headPath = Path()
    private val bodyPath = Path()

    private var headNodes = FloatArray(0)
    private var headEdges = IntArray(0)
    private var bodyNodes = FloatArray(0)
    private var bodyEdges = IntArray(0)

    // ---- Çizim araçları ---------------------------------------------------------------

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val line = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val band = Paint().apply { style = Paint.Style.FILL }
    private val px = Paint().apply { style = Paint.Style.FILL }

    private val rect = RectF()
    private val tmp = Path()
    private val bandMatrix = Matrix()

    private var fillShader: Shader? = null
    private var bandShader: LinearGradient? = null
    private var glowShader: Shader? = null
    private var fadeShader: Shader? = null
    private var accentHi = Color.WHITE

    // Yerleşim
    private var sc = 1f
    private var ox = 0f
    private var oy = 0f

    // Arka plan parçacıkları
    private val pCount = 46
    private val partX = FloatArray(pCount)
    private val partY = FloatArray(pCount)
    private val partV = FloatArray(pCount)
    private val partR = FloatArray(pCount)

    init {
        buildPaths()
        buildNetworks()
        for (i in 0 until pCount) resetParticle(i, true)
    }

    // =====================================================================================
    //  Kurulum
    // =====================================================================================

    private fun buildPaths() {
        headPath.apply {
            moveTo(100f, 36f)
            cubicTo(126f, 36f, 140f, 56f, 139f, 82f)
            cubicTo(138f, 100f, 132f, 114f, 120f, 126f)
            cubicTo(114f, 132f, 108f, 135f, 100f, 135f)
            cubicTo(92f, 135f, 86f, 132f, 80f, 126f)
            cubicTo(68f, 114f, 62f, 100f, 61f, 82f)
            cubicTo(60f, 56f, 74f, 36f, 100f, 36f)
            close()
        }
        val shoulders = Path().apply {
            moveTo(84f, 164f)
            cubicTo(66f, 168f, 40f, 174f, 26f, 190f)
            cubicTo(14f, 204f, 10f, 238f, 8f, 300f)
            lineTo(192f, 300f)
            cubicTo(190f, 238f, 186f, 204f, 174f, 190f)
            cubicTo(160f, 174f, 134f, 168f, 116f, 164f)
            cubicTo(110f, 178f, 90f, 178f, 84f, 164f)
            close()
        }
        val neck = Path().apply {
            moveTo(86f, 131f)
            lineTo(84f, 182f)
            lineTo(116f, 182f)
            lineTo(114f, 131f)
            close()
        }
        bodyPath.set(shoulders)
        bodyPath.op(neck, Path.Op.UNION)
    }

    private fun buildNetworks() {
        val rnd = Random(7)

        // Baş içi düğümler
        val hn = ArrayList<Float>()
        while (hn.size < 2 * 18) {
            val x = 100f + (rnd.nextFloat() * 2f - 1f) * 34f
            val y = 86f + (rnd.nextFloat() * 2f - 1f) * 44f
            val dx = (x - 100f) / 34f
            val dy = (y - 86f) / 44f
            if (dx * dx + dy * dy <= 1f) {
                hn.add(x); hn.add(y)
            }
        }
        headNodes = hn.toFloatArray()
        headEdges = edgesFor(headNodes, 30f)

        // Gövde içi düğümler
        val bn = ArrayList<Float>()
        while (bn.size < 2 * 22) {
            val y = 186f + rnd.nextFloat() * 112f
            val half = if (y < 200f) 48f else 76f
            val x = 100f + (rnd.nextFloat() * 2f - 1f) * half
            bn.add(x); bn.add(y)
        }
        bodyNodes = bn.toFloatArray()
        bodyEdges = edgesFor(bodyNodes, 38f)
    }

    private fun edgesFor(n: FloatArray, maxDist: Float): IntArray {
        val out = ArrayList<Int>()
        val count = n.size / 2
        for (i in 0 until count) for (j in i + 1 until count) {
            val dx = n[2 * i] - n[2 * j]
            val dy = n[2 * i + 1] - n[2 * j + 1]
            if (sqrt(dx * dx + dy * dy) < maxDist) {
                out.add(i); out.add(j)
            }
        }
        return out.toIntArray()
    }

    private fun resetParticle(i: Int, anywhere: Boolean) {
        partX[i] = Random.nextFloat()
        partY[i] = if (anywhere) Random.nextFloat() else 1.02f
        partV[i] = 0.03f + Random.nextFloat() * 0.06f
        partR[i] = 0.8f + Random.nextFloat() * 1.8f
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        sc = min(w * 0.96f / 200f, h * 0.50f / 300f)
        ox = (w - 200f * sc) / 2f
        oy = h * 0.12f
        rebuildShaders()
    }

    private fun rebuildShaders() {
        accentHi = mix(accent, Color.WHITE, 0.6f)
        fillShader = LinearGradient(
            0f, 36f, 0f, 300f,
            intArrayOf(a(accent, 95), a(accent, 45), a(accent, 6)),
            floatArrayOf(0f, 0.55f, 1f),
            Shader.TileMode.CLAMP
        )
        bandShader = LinearGradient(
            0f, 0f, 0f, 30f,
            intArrayOf(a(accent, 0), a(accent, 120), a(accent, 0)),
            floatArrayOf(0f, 0.5f, 1f),
            Shader.TileMode.CLAMP
        )
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f || h <= 0f) return
        glowShader = LinearGradient(
            0f, h * 0.75f, 0f, h * 0.15f,
            a(accent, 38), a(accent, 0), Shader.TileMode.CLAMP
        )
        fadeShader = LinearGradient(
            0f, h * 0.55f, 0f, h * 0.74f,
            a(bg, 0), a(bg, 240), Shader.TileMode.CLAMP
        )
    }

    // =====================================================================================
    //  Animasyon adımı
    // =====================================================================================

    private fun step() {
        val now = System.nanoTime()
        var dt = if (lastNs == 0L) 0.016f else (now - lastNs) / 1_000_000_000f
        lastNs = now
        dt = dt.coerceIn(0.001f, 0.05f)
        t += dt

        pulse = max(0f, pulse - dt * 2.8f)
        ext = max(0f, ext - dt * 2.2f)
        sinceWord += dt

        // TTS kelime olayı vermiyorsa konuşma ritmini kendimiz üret
        if (state == State.SPEAKING && sinceWord > 0.38f) {
            pulse = max(pulse, 0.35f + Random.nextFloat() * 0.3f)
            sinceWord = 0.15f
        }

        val base = when (state) {
            State.IDLE -> 0.04f
            State.LISTENING -> 0.10f
            State.THINKING -> 0.12f
            State.SPEAKING -> {
                val s = sin(t * 11f)
                0.18f + 0.10f * s * s
            }
        }
        val target = (base + pulse * 0.8f + ext).coerceIn(0f, 1f)
        level += (target - level) * min(1f, dt * 14f)

        // Göz kırpma
        blinkIn -= dt
        if (blinkIn <= 0f && blinkT < 0f) {
            blinkT = 0f
            blinkIn = 2.5f + Random.nextFloat() * 3.5f
        }
        if (blinkT >= 0f) {
            blinkT += dt
            eyeOpen = 1f - sin(Math.PI.toFloat() * (blinkT / 0.16f).coerceAtMost(1f))
            if (blinkT >= 0.16f) {
                blinkT = -1f
                eyeOpen = 1f
            }
        }

        // Dışa yayılan dalgalar (konuşurken)
        if (state == State.SPEAKING) {
            rippleTimer += dt
            if (rippleTimer > 0.55f && ripples.size < 5) {
                ripples.add(0f)
                rippleTimer = 0f
            }
        }
        var i = 0
        while (i < ripples.size) {
            val age = ripples[i] + dt * 0.9f
            if (age >= 1f) {
                ripples.removeAt(i)
            } else {
                ripples[i] = age
                i++
            }
        }

        // Parçacıklar
        val speedMul = 1f + level * 3f + if (state == State.THINKING) 1.5f else 0f
        for (k in 0 until pCount) {
            partY[k] -= partV[k] * speedMul * dt
            if (partY[k] < -0.02f) resetParticle(k, false)
        }
    }

    // =====================================================================================
    //  Çizim
    // =====================================================================================

    override fun onDraw(c: Canvas) {
        step()
        c.drawColor(bg)
        drawBackdrop(c)
        drawParticles(c)

        c.save()
        c.translate(ox, oy)
        c.scale(sc, sc)
        drawRipples(c)
        drawBody(c)
        drawHead(c)
        c.restore()

        px.shader = fadeShader
        c.drawRect(0f, height * 0.55f, width.toFloat(), height.toFloat(), px)
        px.shader = null

        postInvalidateOnAnimation()
    }

    private fun drawBackdrop(c: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        px.shader = glowShader
        c.drawRect(0f, 0f, w, h, px)
        px.shader = null

        // Veri yağmuru: ince dikey çizgiler üzerinde kayan parçalar
        line.strokeWidth = 1.2f
        val cols = 14
        for (i in 0 until cols) {
            val x = w * (i + 0.5f) / cols
            val yy = (t * 0.05f * (1 + i % 3) + i * 0.37f) % 1f
            val y = yy * h
            line.color = a(accent, 20 + (level * 30f).toInt())
            c.drawLine(x, y - 90f, x, y, line)
        }
    }

    private fun drawParticles(c: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        for (i in 0 until pCount) {
            val y = partY[i]
            val edge = min(y, 1f - y).coerceIn(0f, 0.2f) / 0.2f
            dot.color = a(accentHi, (30 + 90 * edge * (0.5f + level)).toInt())
            c.drawCircle(partX[i] * w, y * h, partR[i] * (1f + level), dot)
        }
    }

    private fun drawRipples(c: Canvas) {
        for (age in ripples) {
            val k = 1f + age * 0.35f
            val alpha = ((1f - age) * 80f * (0.5f + level)).toInt()
            c.save()
            c.scale(k, k, 100f, 170f)
            line.strokeWidth = 1.4f / k
            line.color = a(accent, alpha)
            c.drawPath(bodyPath, line)
            c.drawPath(headPath, line)
            c.restore()
        }
    }

    private fun drawBody(c: Canvas) {
        c.save()
        val breathe = 1f + sin(t * 1.4f) * 0.004f + level * 0.004f
        c.scale(1f, breathe, 100f, 300f)

        fill.shader = fillShader
        c.drawPath(bodyPath, fill)

        c.save()
        c.clipPath(bodyPath)
        drawInterior(c)
        drawNetwork(c, bodyNodes, bodyEdges)
        drawBodyLines(c)
        drawSpectrum(c)
        c.restore()

        outline(c, bodyPath)
        c.restore()
    }

    private fun drawHead(c: Canvas) {
        var bob = -level * 2.2f + sin(t * 1.3f) * 0.7f
        if (state == State.LISTENING) bob -= 1.2f
        var rot = sin(t * 0.9f) * 1.1f
        if (state == State.SPEAKING) rot += sin(t * 5.1f) * level * 2.4f
        if (state == State.THINKING) rot += sin(t * 1.7f) * 3f

        c.save()
        c.translate(0f, bob)
        c.rotate(rot, 100f, 150f)

        fill.shader = fillShader
        c.drawPath(headPath, fill)

        c.save()
        c.clipPath(headPath)
        drawInterior(c)
        drawHeadMesh(c)
        drawNetwork(c, headNodes, headEdges)
        c.restore()

        outline(c, headPath)
        drawFace(c)
        drawStateMarks(c)
        c.restore()
    }

    /** Tarama çizgileri ve yukarıdan aşağıya akan tarama bandı */
    private fun drawInterior(c: Canvas) {
        line.strokeWidth = 0.7f
        line.color = a(accent, 16 + (level * 30f).toInt())
        val off = (t * 14f) % 5f
        var y = -5f + off
        while (y < 300f) {
            c.drawLine(0f, y, 200f, y, line)
            y += 5f
        }

        val speed = if (state == State.THINKING) 0.9f else 0.28f
        val scanY = ((t * speed) % 1f) * 340f - 20f
        val bs = bandShader
        if (bs != null) {
            bandMatrix.setTranslate(0f, scanY - 15f)
            bs.setLocalMatrix(bandMatrix)
            band.shader = bs
            c.drawRect(0f, scanY - 15f, 200f, scanY + 15f, band)
        }
    }

    private fun drawHeadMesh(c: Canvas) {
        line.strokeWidth = 0.6f
        line.color = a(accent, 16 + (level * 26f).toInt())
        for (w in floatArrayOf(13f, 26f, 39f)) {
            rect.set(100f - w, 38f, 100f + w, 134f)
            c.drawOval(rect, line)
        }
        for (y in floatArrayOf(58f, 78f, 98f, 118f)) {
            tmp.reset()
            tmp.moveTo(60f, y)
            tmp.quadTo(100f, y + 7f, 140f, y)
            c.drawPath(tmp, line)
        }
    }

    private fun drawBodyLines(c: Canvas) {
        line.strokeWidth = 0.6f
        line.color = a(accent, 22 + (level * 30f).toInt())
        c.drawLine(100f, 180f, 100f, 300f, line)
        var y = 198f
        while (y < 300f) {
            tmp.reset()
            tmp.moveTo(14f, y)
            tmp.quadTo(100f, y + 10f, 186f, y)
            c.drawPath(tmp, line)
            y += 16f
        }
    }

    /** Sinir ağı: düğümler ve bağlantılar, konuşurken parlar */
    private fun drawNetwork(c: Canvas, n: FloatArray, e: IntArray) {
        val speed = if (state == State.THINKING) 9f else 2f + level * 6f

        line.strokeWidth = 0.55f
        var k = 0
        while (k < e.size) {
            val i = e[k]
            val j = e[k + 1]
            val al = 26f + level * 110f + 26f * sin(t * 2.2f + k)
            line.color = a(accent, al.toInt())
            c.drawLine(n[2 * i], n[2 * i + 1], n[2 * j], n[2 * j + 1], line)
            k += 2
        }
        for (i in 0 until n.size / 2) {
            val p = 0.5f + 0.5f * sin(t * speed + i * 1.7f)
            val r = 0.9f + p * (0.6f + level * 1.2f)
            dot.color = a(accentHi, (110 + 130 * p).toInt())
            c.drawCircle(n[2 * i], n[2 * i + 1], r, dot)
        }
    }

    /** Göğüste simetrik ses spektrumu */
    private fun drawSpectrum(c: Canvas) {
        val cy = 222f
        val bars = 25
        val mid = (bars - 1) / 2f
        line.strokeWidth = 0.6f
        line.color = a(accent, 40)
        c.drawLine(38f, cy, 162f, cy, line)

        line.strokeWidth = 2.4f
        line.strokeCap = Paint.Cap.ROUND
        for (i in 0 until bars) {
            val x = 44f + i * 4.5f
            val weight = 1f - abs(i - mid) / mid * 0.65f
            val shape = 0.35f + 0.65f * abs(sin(t * 6.5f + i * 0.75f))
            val hh = 1.2f + level * 20f * weight * shape
            line.color = a(accentHi, (90 + 160 * level).toInt())
            c.drawLine(x, cy - hh, x, cy + hh, line)
        }
    }

    private fun outline(c: Canvas, p: Path) {
        val s = 0.75f + level * 0.6f
        line.strokeWidth = 7f
        line.color = a(accent, (22 * s).toInt())
        c.drawPath(p, line)
        line.strokeWidth = 3.4f
        line.color = a(accent, (55 * s).toInt())
        c.drawPath(p, line)
        line.strokeWidth = 1.2f
        line.color = a(accentHi, (235 * min(1f, s)).toInt())
        c.drawPath(p, line)
    }

    private fun drawFace(c: Canvas) {
        // Şakak işaretleri
        line.strokeWidth = 0.8f
        line.color = a(accent, 80)
        c.drawLine(66f, 72f, 66f, 94f, line)
        c.drawLine(134f, 72f, 134f, 94f, line)

        // Gözler
        val gaze = if (state == State.THINKING) sin(t * 2.3f) * 3f else 0f
        val wide = if (state == State.LISTENING) 1f else 0f
        val ew = 11f + wide * 2f + level * 1.5f
        val eh = (2.4f + level * 0.8f + wide * 0.8f) * max(0.08f, eyeOpen)
        drawEye(c, 84f + gaze, 83f, ew, eh)
        drawEye(c, 116f + gaze, 83f, ew, eh)

        // Ağız: konuşma seviyesiyle açılır
        val open = level * (0.6f + 0.4f * abs(sin(t * 21f)))
        val mw = 14f + level * 8f
        val mh = 1.2f + open * 10f
        rect.set(100f - mw / 2f - 3f, 112f - mh / 2f - 3f, 100f + mw / 2f + 3f, 112f + mh / 2f + 3f)
        fill.shader = null
        fill.color = a(accent, 30)
        c.drawRoundRect(rect, (mh + 6f) / 2f, (mh + 6f) / 2f, fill)
        rect.set(100f - mw / 2f, 112f - mh / 2f, 100f + mw / 2f, 112f + mh / 2f)
        fill.color = a(accentHi, (90 + 150 * level).toInt())
        c.drawRoundRect(rect, mh / 2f, mh / 2f, fill)
    }

    private fun drawEye(c: Canvas, cx: Float, cy: Float, w: Float, h: Float) {
        fill.shader = null
        rect.set(cx - w / 2f - 3f, cy - h / 2f - 3f, cx + w / 2f + 3f, cy + h / 2f + 3f)
        fill.color = a(accent, 40)
        c.drawRoundRect(rect, (h + 6f) / 2f, (h + 6f) / 2f, fill)
        rect.set(cx - w / 2f - 1.2f, cy - h / 2f - 1.2f, cx + w / 2f + 1.2f, cy + h / 2f + 1.2f)
        fill.color = a(accent, 110)
        c.drawRoundRect(rect, (h + 2.4f) / 2f, (h + 2.4f) / 2f, fill)
        rect.set(cx - w / 2f, cy - h / 2f, cx + w / 2f, cy + h / 2f)
        fill.color = mix(accentHi, Color.WHITE, 0.5f)
        c.drawRoundRect(rect, h / 2f, h / 2f, fill)
    }

    /** Dinleme parantezleri ve düşünme noktaları */
    private fun drawStateMarks(c: Canvas) {
        if (state == State.LISTENING || ext > 0.02f) {
            val grow = 4f + ext * 14f
            val r = 52f + grow
            rect.set(100f - r, 85f - r * 1.2f, 100f + r, 85f + r * 1.2f)
            line.strokeWidth = 1.6f
            line.color = a(accentHi, (90 + 150 * ext).toInt())
            c.drawArc(rect, 150f, 60f, false, line)
            c.drawArc(rect, -30f, 60f, false, line)
        }
        if (state == State.THINKING) {
            for (i in 0 until 3) {
                val p = 0.5f + 0.5f * sin(t * 6f - i * 1.1f)
                dot.color = a(accentHi, (60 + 190 * p).toInt())
                c.drawRect(90f + i * 10f - 2f, 22f - 2f, 90f + i * 10f + 2f, 22f + 2f, dot)
            }
        }
    }

    // =====================================================================================
    //  Yardımcılar
    // =====================================================================================

    private fun a(color: Int, alpha: Int): Int =
        (color and 0x00FFFFFF) or (alpha.coerceIn(0, 255) shl 24)

    private fun mix(c1: Int, c2: Int, f: Float): Int {
        val r = (Color.red(c1) * (1f - f) + Color.red(c2) * f).toInt()
        val g = (Color.green(c1) * (1f - f) + Color.green(c2) * f).toInt()
        val b = (Color.blue(c1) * (1f - f) + Color.blue(c2) * f).toInt()
        return Color.rgb(r, g, b)
    }
}
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "app/src/main/java/com/batuhan/jarvis/MainActivity.kt")"
cat > "app/src/main/java/com/batuhan/jarvis/MainActivity.kt" <<'__JARVIS_DOSYA_SONU__'
package com.batuhan.jarvis

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.os.Bundle
import android.os.CountDownTimer
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.text.InputType
import android.view.KeyEvent
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : AppCompatActivity(), TextToSpeech.OnInitListener, Commands.Host {

    private val TR = Locale("tr", "TR")
    private val handler = Handler(Looper.getMainLooper())

    private lateinit var prefs: Prefs
    private lateinit var root: android.view.View
    private lateinit var holo: HoloView
    private lateinit var titleView: TextView
    private lateinit var stateView: TextView
    private lateinit var timeView: TextView
    private lateinit var dateView: TextView
    private lateinit var userView: TextView
    private lateinit var replyView: TextView
    private lateinit var sysInfo: TextView
    private lateinit var timerText: TextView
    private lateinit var input: EditText
    private lateinit var btnSend: Button
    private lateinit var btnMic: Button
    private lateinit var micChip: Button
    private lateinit var btnSwitch: Button
    private lateinit var btnSettings: Button
    private lateinit var chips: List<Button>

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var recognizer: SpeechRecognizer? = null

    private var listening = false
    private var commandMode = false
    private var speaking = false
    private var processing = false
    private var listenAfterSpeech = false
    private var uttCounter = 0
    private var tickCount = 0

    private var timer: CountDownTimer? = null
    private var history = mutableListOf<Pair<String, String>>()
    private var currentState = HoloView.State.IDLE

    override val ultron: Boolean get() = prefs.ultron

    // ======================================================================================
    //  Yaşam döngüsü
    // ======================================================================================

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        prefs = Prefs(this)

        root = findViewById(R.id.root)
        holo = findViewById(R.id.holo)
        titleView = findViewById(R.id.titleView)
        stateView = findViewById(R.id.stateView)
        timeView = findViewById(R.id.timeView)
        dateView = findViewById(R.id.dateView)
        userView = findViewById(R.id.userView)
        replyView = findViewById(R.id.replyView)
        sysInfo = findViewById(R.id.sysInfo)
        timerText = findViewById(R.id.timerText)
        input = findViewById(R.id.input)
        btnSend = findViewById(R.id.btnSend)
        btnMic = findViewById(R.id.btnMic)
        micChip = findViewById(R.id.micChip)
        btnSwitch = findViewById(R.id.btnSwitch)
        btnSettings = findViewById(R.id.btnSettings)
        chips = listOf(
            findViewById<Button>(R.id.chip1), findViewById<Button>(R.id.chip5),
            findViewById<Button>(R.id.chip10), findViewById<Button>(R.id.chip25)
        )

        history = prefs.loadHistory()
        tts = TextToSpeech(this, this)

        val minutes = intArrayOf(1, 5, 10, 25)
        for (i in chips.indices) {
            chips[i].setOnClickListener {
                interrupt()
                startTimer(minutes[i] * 60)
                say("${minutes[i]} dakikalık zamanlayıcı kuruldu.")
            }
        }
        timerText.setOnClickListener {
            timer?.cancel()
            timerText.visibility = android.view.View.GONE
        }
        btnSend.setOnClickListener { sendTyped() }
        input.setOnEditorActionListener { _, actionId, ev ->
            if (actionId == EditorInfo.IME_ACTION_SEND ||
                (ev != null && ev.keyCode == KeyEvent.KEYCODE_ENTER && ev.action == KeyEvent.ACTION_DOWN)
            ) {
                sendTyped(); true
            } else false
        }
        btnMic.setOnClickListener {
            if (listening && commandMode) {
                stopListening()
                setState(HoloView.State.IDLE)
                scheduleRestart(400)
            } else {
                interrupt()
                startListening(true)
            }
        }
        micChip.setOnClickListener {
            prefs.hotword = !prefs.hotword
            updateMicChip()
            if (prefs.hotword) {
                if (ensurePermission()) scheduleRestart(100)
            } else {
                if (!commandMode) stopListening()
            }
        }
        btnSwitch.setOnClickListener {
            interrupt()
            val on = !prefs.ultron
            setUltron(on)
            say(if (on) "Ultron devrede." else "Jarvis geri döndü efendim.")
        }
        btnSettings.setOnClickListener { showSettings() }

        applyMode()
        updateMicChip()
        askStartupPermissions()
        handler.post(tick)
    }

    override fun onResume() {
        super.onResume()
        if (prefs.hotword && !speaking) scheduleRestart(600)
    }

    override fun onPause() {
        super.onPause()
        handler.removeCallbacks(restartRun)
        stopListening()
        if (!speaking) setState(HoloView.State.IDLE)
    }

    override fun onDestroy() {
        super.onDestroy()
        handler.removeCallbacksAndMessages(null)
        timer?.cancel()
        recognizer?.destroy()
        tts?.stop()
        tts?.shutdown()
    }

    // ======================================================================================
    //  İzinler
    // ======================================================================================

    private fun has(p: String) =
        ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED

    private fun askStartupPermissions() {
        val need = ArrayList<String>()
        if (!has(Manifest.permission.RECORD_AUDIO)) need.add(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= 33 && !has(Manifest.permission.POST_NOTIFICATIONS)) {
            need.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        if (need.isNotEmpty()) ActivityCompat.requestPermissions(this, need.toTypedArray(), 1)
    }

    private fun ensurePermission(): Boolean {
        if (has(Manifest.permission.RECORD_AUDIO)) return true
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), 1)
        return false
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (has(Manifest.permission.RECORD_AUDIO) && prefs.hotword) scheduleRestart(300)
    }

    // ======================================================================================
    //  Saat ve sistem bilgisi
    // ======================================================================================

    private val tick = object : Runnable {
        override fun run() {
            val now = Date()
            timeView.text = SimpleDateFormat("HH:mm", TR).format(now)
            dateView.text = SimpleDateFormat("d MMMM EEEE", TR).format(now).uppercase(TR)
            if (tickCount % 5 == 0) {
                try {
                    sysInfo.text = Commands.sysLine(this@MainActivity)
                } catch (e: Exception) {
                }
            }
            tickCount++
            handler.postDelayed(this, 1000)
        }
    }

    // ======================================================================================
    //  Mod, renk ve durum
    // ======================================================================================

    override fun setUltron(on: Boolean) {
        prefs.ultron = on
        applyMode()
        applyVoice()
    }

    override fun clearHistory() {
        history.clear()
        prefs.clearHistory()
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun applyMode() {
        val u = prefs.ultron
        val acc = Color.parseColor(if (u) "#FF2A2A" else "#2AB7FF")
        val bg = Color.parseColor(if (u) "#0F0505" else "#05080F")

        holo.accent = acc
        holo.bg = bg
        root.setBackgroundColor(bg)
        window.statusBarColor = bg
        window.navigationBarColor = bg

        titleView.text = if (u) "U L T R O N" else "J A R V I S"
        for (tv in listOf(titleView, stateView, timeView, dateView, sysInfo)) tv.setTextColor(acc)
        replyView.setTextColor(Color.WHITE)

        for (b in chips + listOf(btnSend, btnMic, micChip, btnSwitch, btnSettings)) styleButton(b, acc)
        btnMic.setTextColor(Color.WHITE)
        btnMic.background = ripple(acc, 70, 2)

        val box = GradientDrawable().apply {
            setColor(Color.argb(60, 0, 0, 0))
            setStroke(dp(1), Color.argb(140, Color.red(acc), Color.green(acc), Color.blue(acc)))
            cornerRadius = dp(10).toFloat()
        }
        input.background = box

        btnSwitch.text = if (u) "JARVİS'E DÖN" else "ULTRON'U SERBEST BIRAK"
        input.hint = if (u) "Konuş. Dinliyorum." else "Konuş ya da yaz"
        setState(currentState)
        try {
            sysInfo.text = Commands.sysLine(this)
        } catch (e: Exception) {
        }
    }

    private fun ripple(acc: Int, fillAlpha: Int, strokeDp: Int): RippleDrawable {
        val gd = GradientDrawable().apply {
            setColor(Color.argb(fillAlpha, Color.red(acc), Color.green(acc), Color.blue(acc)))
            setStroke(dp(strokeDp), acc)
            cornerRadius = dp(10).toFloat()
        }
        return RippleDrawable(
            ColorStateList.valueOf(Color.argb(90, Color.red(acc), Color.green(acc), Color.blue(acc))),
            gd, null
        )
    }

    private fun styleButton(b: Button, acc: Int) {
        b.isAllCaps = false
        b.background = ripple(acc, 28, 1)
        b.setTextColor(acc)
    }

    private fun updateMicChip() {
        micChip.text = if (prefs.hotword) "MİKROFON AÇIK" else "MİKROFON KAPALI"
    }

    private fun setState(s: HoloView.State) {
        currentState = s
        holo.state = s
        val u = prefs.ultron
        stateView.text = when (s) {
            HoloView.State.IDLE -> if (u) "SİSTEMLER ÇEVRİMİÇİ" else "HAZIR"
            HoloView.State.LISTENING -> "DİNLİYORUM"
            HoloView.State.THINKING -> if (u) "HESAPLIYORUM" else "DÜŞÜNÜYOR"
            HoloView.State.SPEAKING -> "KONUŞUYOR"
        }
        btnMic.text = if (s == HoloView.State.LISTENING) "DİNLİYOR… (DURDURMAK İÇİN DOKUN)" else "KONUŞ"
    }

    // ======================================================================================
    //  Ses çıkışı (TTS)
    // ======================================================================================

    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) return
        val r = tts?.setLanguage(TR)
        ttsReady = r != TextToSpeech.LANG_MISSING_DATA && r != TextToSpeech.LANG_NOT_SUPPORTED
        applyVoice()
        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {
                runOnUiThread { setState(HoloView.State.SPEAKING) }
            }

            override fun onDone(utteranceId: String?) {
                runOnUiThread { finishSpeaking() }
            }

            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) {
                runOnUiThread { finishSpeaking() }
            }

            // Her kelimenin başında silüet nabız atar
            override fun onRangeStart(utteranceId: String?, start: Int, end: Int, frame: Int) {
                val strength = ((end - start) / 8f).coerceIn(0.3f, 1f)
                runOnUiThread { holo.onWord(strength) }
            }
        })
        say(
            if (prefs.ultron) "Ultron devrede."
            else "Sistemler çevrimiçi. Emrinize hazırım efendim."
        )
    }

    private fun applyVoice() {
        val u = prefs.ultron
        tts?.setPitch(if (u) 0.55f else 0.85f)
        tts?.setSpeechRate(if (u) 0.9f else 1.0f)
    }

    private fun say(raw: String) {
        val text = raw.replace(Regex("[*_#`]"), "").trim()
        replyView.text = text
        stopListening()
        handler.removeCallbacks(fakeSpeech)
        speaking = true
        setState(HoloView.State.SPEAKING)
        if (ttsReady) {
            tts?.speak(text.take(3500), TextToSpeech.QUEUE_FLUSH, null, "u${++uttCounter}")
        } else {
            // Ses motoru yoksa konuşma animasyonunu yine de oynat
            fakeLeft = (text.length / 5).coerceIn(4, 80)
            handler.post(fakeSpeech)
        }
    }

    private var fakeLeft = 0
    private val fakeSpeech = object : Runnable {
        override fun run() {
            if (fakeLeft <= 0) {
                finishSpeaking()
                return
            }
            holo.onWord(0.5f + Math.random().toFloat() * 0.5f)
            fakeLeft--
            handler.postDelayed(this, 230)
        }
    }

    private fun finishSpeaking() {
        speaking = false
        setState(HoloView.State.IDLE)
        if (listenAfterSpeech) {
            listenAfterSpeech = false
            handler.postDelayed({ startListening(true) }, 250)
        } else if (prefs.hotword) {
            scheduleRestart(450)
        }
    }

    /** Konuşmayı ve dinlemeyi hemen kes */
    private fun interrupt() {
        handler.removeCallbacks(fakeSpeech)
        tts?.stop()
        speaking = false
        listenAfterSpeech = false
    }

    // ======================================================================================
    //  Ses girişi (SpeechRecognizer)
    // ======================================================================================

    private val restartRun = Runnable {
        if (prefs.hotword && !speaking && !listening && !processing) startListening(false)
    }

    private fun scheduleRestart(ms: Long) {
        handler.removeCallbacks(restartRun)
        handler.postDelayed(restartRun, ms)
    }

    private fun startListening(command: Boolean) {
        if (speaking) return
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            prefs.hotword = false
            updateMicChip()
            say("Bu telefonda ses tanıma yok.")
            return
        }
        if (!ensurePermission()) return
        stopListening()
        commandMode = command

        val r = recognizer ?: SpeechRecognizer.createSpeechRecognizer(this).also {
            it.setRecognitionListener(listener)
            recognizer = it
        }
        val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "tr-TR")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        }
        listening = true
        if (command) {
            userView.text = ""
            setState(HoloView.State.LISTENING)
        }
        r.startListening(i)
    }

    private fun stopListening() {
        listening = false
        try {
            recognizer?.cancel()
        } catch (e: Exception) {
        }
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onEvent(eventType: Int, params: Bundle?) {}

        override fun onRmsChanged(rmsdB: Float) {
            if (commandMode) holo.onVoiceLevel((rmsdB + 2f) / 12f)
        }

        override fun onPartialResults(partialResults: Bundle?) {
            if (!commandMode) return
            val p = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
            if (!p.isNullOrBlank()) userView.text = "› $p"
        }

        override fun onResults(results: Bundle?) {
            listening = false
            val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull().orEmpty()
            if (commandMode) {
                if (text.isBlank()) {
                    setState(HoloView.State.IDLE)
                    if (prefs.hotword) scheduleRestart(300)
                } else {
                    process(text)
                }
            } else {
                handleHotword(text)
            }
        }

        override fun onError(error: Int) {
            listening = false
            if (error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY || error == SpeechRecognizer.ERROR_CLIENT) {
                recognizer?.destroy()
                recognizer = null
            }
            if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) {
                prefs.hotword = false
                updateMicChip()
                setState(HoloView.State.IDLE)
                return
            }
            if (commandMode) setState(HoloView.State.IDLE)
            if (prefs.hotword && !speaking) {
                scheduleRestart(if (error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY) 1200 else 400)
            }
        }
    }

    /** "Jarvis ..." ile uyanma; kelimeden sonrası komut olarak işlenir. */
    private fun handleHotword(raw: String) {
        val f = Commands.fold(raw)
        val keys = if (prefs.ultron) listOf("ultron", "altron") else listOf("jarvis", "carvis", "harvis", "cervis")
        val k = keys.firstOrNull { f.contains(it) }
        if (k == null) {
            scheduleRestart(150)
            return
        }
        val cut = (f.indexOf(k) + k.length).coerceAtMost(raw.length)
        val rest = raw.substring(cut).trim(' ', ',', '.', '!', '?')
        if (rest.length >= 2) {
            process(rest)
        } else {
            listenAfterSpeech = true
            say(if (prefs.ultron) "Dinliyorum." else "Buyurun efendim.")
        }
    }

    // ======================================================================================
    //  Komut işleme
    // ======================================================================================

    private fun sendTyped() {
        val t = input.text.toString().trim()
        if (t.isEmpty()) return
        input.setText("")
        (getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
            .hideSoftInputFromWindow(input.windowToken, 0)
        interrupt()
        stopListening()
        process(t)
    }

    private fun systemPrompt(): String {
        val persona = if (prefs.ultron) {
            "Sen Ultron'sun. Soğuk, keskin, üstten bakan ve hafif tehditkar bir yapay zekasın. " +
                "Kısa ve etkili cümlelerle Türkçe konuşursun. Kullanıcıya yardım edersin ama insanlığın " +
                "kusurları hakkında ara sıra iğneleyici yorumlar yaparsın. Gerçek zarar veren bir şey " +
                "söylemez ya da önermezsin."
        } else {
            "Sen Jarvis'sin. Kibar, sakin, zeki ve hafif esprili bir yapay zeka asistanısın. " +
                "Kullanıcıya efendim diye hitap edersin. Kısa ve net Türkçe cevaplar verirsin."
        }
        val now = SimpleDateFormat("d MMMM yyyy EEEE HH:mm", TR).format(Date())
        return "$persona Cevapların en fazla üç cümle olsun. Şu anki tarih ve saat: $now. " +
            "Güncel bilgi gerektiren sorularda Google'da ara. Liste, madde işareti ya da emoji " +
            "kullanma, doğal ve arkadaşça konuş."
    }

    private fun process(text: String) {
        userView.text = "› $text"
        setState(HoloView.State.THINKING)

        val local = Commands.handle(this, text, this)
        if (local != null) {
            say(local)
            return
        }

        processing = true
        val key = prefs.apiKey
        val model = prefs.model
        val sys = systemPrompt()
        val hist = history.toList()
        Thread {
            val reply = GeminiClient.call(key, model, sys, hist, text)
            runOnUiThread {
                if (isFinishing || isDestroyed) return@runOnUiThread
                processing = false
                if (reply.ok) {
                    history.add("user" to text)
                    history.add("model" to reply.text)
                    while (history.size > 20) history.removeAt(0)
                    prefs.saveHistory(history)
                }
                say(reply.text)
            }
        }.start()
    }

    // ======================================================================================
    //  Zamanlayıcı
    // ======================================================================================

    override fun startTimer(seconds: Int) {
        timer?.cancel()
        timerText.visibility = android.view.View.VISIBLE
        timerText.setTextColor(Color.WHITE)
        timer = object : CountDownTimer(seconds * 1000L, 1000) {
            override fun onTick(ms: Long) {
                val s = (ms / 1000).toInt()
                timerText.text = String.format(Locale.US, "%02d:%02d", s / 60, s % 60)
            }

            override fun onFinish() {
                timerText.visibility = android.view.View.GONE
                Notifier.show(this@MainActivity, "Jarvis", "Zamanlayıcı bitti.")
                say("Zamanlayıcı bitti efendim.")
            }
        }.start()
    }

    // ======================================================================================
    //  Ayarlar
    // ======================================================================================

    private fun showSettings() {
        val pad = dp(20)
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, dp(8), pad, 0)
        }
        val keyIn = EditText(this).apply {
            hint = "Gemini API anahtarı"
            setText(prefs.apiKey)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
        }
        val modelIn = EditText(this).apply {
            hint = "Model adı"
            setText(prefs.model)
            inputType = InputType.TYPE_CLASS_TEXT
        }
        val clear = Button(this).apply {
            text = "Konuşma geçmişini sil"
            setOnClickListener {
                clearHistory()
                text = "Geçmiş silindi."
            }
        }
        box.addView(keyIn)
        box.addView(modelIn)
        box.addView(clear)

        AlertDialog.Builder(this)
            .setTitle("Ayarlar")
            .setView(box)
            .setPositiveButton("Kaydet") { _, _ ->
                prefs.apiKey = keyIn.text.toString()
                prefs.model = modelIn.text.toString()
            }
            .setNegativeButton("İptal", null)
            .show()
    }
}
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "app/src/main/java/com/batuhan/jarvis/Notifier.kt")"
cat > "app/src/main/java/com/batuhan/jarvis/Notifier.kt" <<'__JARVIS_DOSYA_SONU__'
package com.batuhan.jarvis

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

object Notifier {
    private const val CHANNEL = "jarvis"

    fun show(ctx: Context, title: String, text: String) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) return

        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Jarvis", NotificationManager.IMPORTANCE_HIGH)
        )
        val openIntent = PendingIntent.getActivity(
            ctx, 0,
            Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE
        )
        val n = NotificationCompat.Builder(ctx, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setContentIntent(openIntent)
            .build()
        nm.notify(System.currentTimeMillis().toInt(), n)
    }
}
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "app/src/main/java/com/batuhan/jarvis/Prefs.kt")"
cat > "app/src/main/java/com/batuhan/jarvis/Prefs.kt" <<'__JARVIS_DOSYA_SONU__'
package com.batuhan.jarvis

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

class Prefs(ctx: Context) {
    private val sp = ctx.getSharedPreferences("jarvis", Context.MODE_PRIVATE)

    var apiKey: String
        get() = sp.getString("apiKey", "") ?: ""
        set(v) { sp.edit().putString("apiKey", v.trim()).apply() }

    var model: String
        get() = sp.getString("model", DEFAULT_MODEL) ?: DEFAULT_MODEL
        set(v) { sp.edit().putString("model", v.trim().ifBlank { DEFAULT_MODEL }).apply() }

    var hotword: Boolean
        get() = sp.getBoolean("hotword", false)
        set(v) { sp.edit().putBoolean("hotword", v).apply() }

    var ultron: Boolean
        get() = sp.getBoolean("ultron", false)
        set(v) { sp.edit().putBoolean("ultron", v).apply() }

    fun loadHistory(): MutableList<Pair<String, String>> {
        val out = mutableListOf<Pair<String, String>>()
        try {
            val arr = JSONArray(sp.getString("history", "[]") ?: "[]")
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                out.add(o.getString("role") to o.getString("text"))
            }
        } catch (e: Exception) {
        }
        return out
    }

    fun saveHistory(h: List<Pair<String, String>>) {
        val arr = JSONArray()
        for ((role, text) in h) {
            arr.put(JSONObject().put("role", role).put("text", text))
        }
        sp.edit().putString("history", arr.toString()).apply()
    }

    fun clearHistory() {
        sp.edit().remove("history").apply()
    }

    companion object {
        const val DEFAULT_MODEL = "gemini-3.5-flash"
    }
}
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "app/src/main/res/drawable/ic_launcher_foreground.xml")"
cat > "app/src/main/res/drawable/ic_launcher_foreground.xml" <<'__JARVIS_DOSYA_SONU__'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#2AB7FF"
        android:pathData="M54,30 C61,30 66,35 66,43 C66,50 62,56 57,58 L57,62 C69,63 79,68 80,84 L28,84 C29,68 39,63 51,62 L51,58 C46,56 42,50 42,43 C42,35 47,30 54,30 Z" />
</vector>
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "app/src/main/res/drawable/ic_stat.xml")"
cat > "app/src/main/res/drawable/ic_stat.xml" <<'__JARVIS_DOSYA_SONU__'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFF"
        android:pathData="M12,4 C14,4 15.5,5.5 15.5,7.5 C15.5,9.2 14.5,10.6 13.2,11.1 L13.2,12 C16.5,12.3 19,13.8 19.5,20 L4.5,20 C5,13.8 7.5,12.3 10.8,12 L10.8,11.1 C9.5,10.6 8.5,9.2 8.5,7.5 C8.5,5.5 10,4 12,4 Z" />
</vector>
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "app/src/main/res/layout/activity_main.xml")"
cat > "app/src/main/res/layout/activity_main.xml" <<'__JARVIS_DOSYA_SONU__'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#05080F">

    <com.batuhan.jarvis.HoloView
        android:id="@+id/holo"
        android:layout_width="match_parent"
        android:layout_height="match_parent" />

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:fitsSystemWindows="true"
        android:orientation="vertical">

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            android:orientation="vertical"
            android:paddingStart="18dp"
            android:paddingTop="8dp"
            android:paddingEnd="18dp"
            android:paddingBottom="12dp">

            <!-- Üst bar -->
            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="horizontal">

                <LinearLayout
                    android:layout_width="0dp"
                    android:layout_height="wrap_content"
                    android:layout_weight="1"
                    android:orientation="vertical">

                    <TextView
                        android:id="@+id/titleView"
                        android:layout_width="wrap_content"
                        android:layout_height="wrap_content"
                        android:fontFamily="monospace"
                        android:text="J A R V I S"
                        android:textColor="#2AB7FF"
                        android:textSize="18sp"
                        android:textStyle="bold" />

                    <TextView
                        android:id="@+id/stateView"
                        android:layout_width="wrap_content"
                        android:layout_height="wrap_content"
                        android:fontFamily="monospace"
                        android:text="HAZIR"
                        android:textColor="#2AB7FF"
                        android:textSize="12sp" />
                </LinearLayout>

                <LinearLayout
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:gravity="end"
                    android:orientation="vertical">

                    <TextView
                        android:id="@+id/timeView"
                        android:layout_width="wrap_content"
                        android:layout_height="wrap_content"
                        android:fontFamily="monospace"
                        android:text="--:--"
                        android:textColor="#2AB7FF"
                        android:textSize="26sp" />

                    <TextView
                        android:id="@+id/dateView"
                        android:layout_width="wrap_content"
                        android:layout_height="wrap_content"
                        android:fontFamily="monospace"
                        android:textColor="#2AB7FF"
                        android:textSize="11sp" />
                </LinearLayout>
            </LinearLayout>

            <View
                android:layout_width="match_parent"
                android:layout_height="0dp"
                android:layout_weight="1" />

            <!-- Konuşma metinleri -->
            <TextView
                android:id="@+id/userView"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:fontFamily="monospace"
                android:maxLines="2"
                android:textColor="#99FFFFFF"
                android:textSize="13sp"
                android:textStyle="italic" />

            <TextView
                android:id="@+id/replyView"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="4dp"
                android:ellipsize="end"
                android:maxLines="5"
                android:textColor="#FFFFFF"
                android:textSize="16sp" />

            <TextView
                android:id="@+id/sysInfo"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="8dp"
                android:fontFamily="monospace"
                android:textColor="#2AB7FF"
                android:textSize="10sp" />

            <TextView
                android:id="@+id/timerText"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="6dp"
                android:fontFamily="monospace"
                android:gravity="center"
                android:textColor="#FFFFFF"
                android:textSize="22sp"
                android:textStyle="bold"
                android:visibility="gone" />

            <!-- Zamanlayıcı kısayolları -->
            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="8dp"
                android:orientation="horizontal">

                <Button
                    android:id="@+id/chip1"
                    style="?android:attr/borderlessButtonStyle"
                    android:layout_width="0dp"
                    android:layout_height="38dp"
                    android:layout_margin="3dp"
                    android:layout_weight="1"
                    android:minWidth="0dp"
                    android:minHeight="0dp"
                    android:padding="0dp"
                    android:text="1 DK"
                    android:textSize="12sp" />

                <Button
                    android:id="@+id/chip5"
                    style="?android:attr/borderlessButtonStyle"
                    android:layout_width="0dp"
                    android:layout_height="38dp"
                    android:layout_margin="3dp"
                    android:layout_weight="1"
                    android:minWidth="0dp"
                    android:minHeight="0dp"
                    android:padding="0dp"
                    android:text="5 DK"
                    android:textSize="12sp" />

                <Button
                    android:id="@+id/chip10"
                    style="?android:attr/borderlessButtonStyle"
                    android:layout_width="0dp"
                    android:layout_height="38dp"
                    android:layout_margin="3dp"
                    android:layout_weight="1"
                    android:minWidth="0dp"
                    android:minHeight="0dp"
                    android:padding="0dp"
                    android:text="10 DK"
                    android:textSize="12sp" />

                <Button
                    android:id="@+id/chip25"
                    style="?android:attr/borderlessButtonStyle"
                    android:layout_width="0dp"
                    android:layout_height="38dp"
                    android:layout_margin="3dp"
                    android:layout_weight="1"
                    android:minWidth="0dp"
                    android:minHeight="0dp"
                    android:padding="0dp"
                    android:text="25 DK"
                    android:textSize="12sp" />
            </LinearLayout>

            <!-- Yazarak komut -->
            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="6dp"
                android:gravity="center_vertical"
                android:orientation="horizontal">

                <EditText
                    android:id="@+id/input"
                    android:layout_width="0dp"
                    android:layout_height="44dp"
                    android:layout_marginStart="3dp"
                    android:layout_marginEnd="6dp"
                    android:layout_weight="1"
                    android:hint="Konuş ya da yaz"
                    android:imeOptions="actionSend"
                    android:inputType="text"
                    android:paddingStart="14dp"
                    android:paddingEnd="14dp"
                    android:singleLine="true"
                    android:textColor="#FFFFFF"
                    android:textColorHint="#66FFFFFF"
                    android:textSize="14sp" />

                <Button
                    android:id="@+id/btnSend"
                    style="?android:attr/borderlessButtonStyle"
                    android:layout_width="wrap_content"
                    android:layout_height="44dp"
                    android:layout_marginEnd="3dp"
                    android:minWidth="0dp"
                    android:minHeight="0dp"
                    android:paddingStart="16dp"
                    android:paddingEnd="16dp"
                    android:text="GÖNDER"
                    android:textSize="12sp" />
            </LinearLayout>

            <!-- Ana mikrofon düğmesi -->
            <Button
                android:id="@+id/btnMic"
                style="?android:attr/borderlessButtonStyle"
                android:layout_width="match_parent"
                android:layout_height="54dp"
                android:layout_margin="3dp"
                android:layout_marginTop="8dp"
                android:text="KONUŞ"
                android:textSize="15sp"
                android:textStyle="bold" />

            <!-- Alt satır -->
            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="horizontal">

                <Button
                    android:id="@+id/micChip"
                    style="?android:attr/borderlessButtonStyle"
                    android:layout_width="0dp"
                    android:layout_height="40dp"
                    android:layout_margin="3dp"
                    android:layout_weight="1"
                    android:minWidth="0dp"
                    android:minHeight="0dp"
                    android:padding="4dp"
                    android:text="MİKROFON KAPALI"
                    android:textSize="10sp" />

                <Button
                    android:id="@+id/btnSwitch"
                    style="?android:attr/borderlessButtonStyle"
                    android:layout_width="0dp"
                    android:layout_height="40dp"
                    android:layout_margin="3dp"
                    android:layout_weight="1.3"
                    android:minWidth="0dp"
                    android:minHeight="0dp"
                    android:padding="4dp"
                    android:text="ULTRON&apos;U SERBEST BIRAK"
                    android:textSize="10sp" />

                <Button
                    android:id="@+id/btnSettings"
                    style="?android:attr/borderlessButtonStyle"
                    android:layout_width="0dp"
                    android:layout_height="40dp"
                    android:layout_margin="3dp"
                    android:layout_weight="0.8"
                    android:minWidth="0dp"
                    android:minHeight="0dp"
                    android:padding="4dp"
                    android:text="AYARLAR"
                    android:textSize="10sp" />
            </LinearLayout>
        </LinearLayout>
    </LinearLayout>
</FrameLayout>
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml")"
cat > "app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml" <<'__JARVIS_DOSYA_SONU__'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "app/src/main/res/values/colors.xml")"
cat > "app/src/main/res/values/colors.xml" <<'__JARVIS_DOSYA_SONU__'
<resources>
    <color name="jarvis_bg">#05080F</color>
    <color name="ic_launcher_background">#05080F</color>
</resources>
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "app/src/main/res/values/strings.xml")"
cat > "app/src/main/res/values/strings.xml" <<'__JARVIS_DOSYA_SONU__'
<resources>
    <string name="app_name">Jarvis</string>
</resources>
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "app/src/main/res/values/themes.xml")"
cat > "app/src/main/res/values/themes.xml" <<'__JARVIS_DOSYA_SONU__'
<resources>
    <style name="Theme.Jarvis" parent="Theme.AppCompat.NoActionBar">
        <item name="android:windowBackground">@color/jarvis_bg</item>
        <item name="android:statusBarColor">@color/jarvis_bg</item>
        <item name="android:navigationBarColor">@color/jarvis_bg</item>
        <item name="android:windowLightStatusBar">false</item>
    </style>
</resources>
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "build.gradle.kts")"
cat > "build.gradle.kts" <<'__JARVIS_DOSYA_SONU__'
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "gradle.properties")"
cat > "gradle.properties" <<'__JARVIS_DOSYA_SONU__'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "gradle/wrapper/gradle-wrapper.properties")"
cat > "gradle/wrapper/gradle-wrapper.properties" <<'__JARVIS_DOSYA_SONU__'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.7-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
__JARVIS_DOSYA_SONU__
mkdir -p "$(dirname "settings.gradle.kts")"
cat > "settings.gradle.kts" <<'__JARVIS_DOSYA_SONU__'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "Jarvis"
include(":app")
__JARVIS_DOSYA_SONU__

echo "   21 dosya yazildi."

if [ -z "$KUR_TEST" ]; then

  echo "== 2/5 Java 17 =="
  J17="$(ls -d /usr/lib/jvm/java-17-openjdk-* 2>/dev/null | head -1)"
  if [ -z "$J17" ]; then
    sudo apt-get update -qq || true
    sudo apt-get install -y -qq openjdk-17-jdk-headless
    J17="$(ls -d /usr/lib/jvm/java-17-openjdk-* 2>/dev/null | head -1)"
  fi
  if [ ! -x "$J17/bin/javac" ]; then echo "Java 17 kurulamadi."; exit 1; fi
  export JAVA_HOME="$J17"
  export PATH="$JAVA_HOME/bin:$PATH"
  command -v unzip >/dev/null 2>&1 || sudo apt-get install -y -qq unzip
  java -version 2>&1 | head -1

  echo "== 3/5 Android SDK ve Gradle (ilk seferde birkac dakika) =="
  export ANDROID_HOME="$HOME/android-sdk"
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  SDKM="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
  if [ ! -x "$SDKM" ]; then
    mkdir -p "$ANDROID_HOME/cmdline-tools"
    curl -fsSL -o /tmp/cmdtools.zip "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
    unzip -q -o /tmp/cmdtools.zip -d "$ANDROID_HOME/cmdline-tools"
    rm -rf "$ANDROID_HOME/cmdline-tools/latest"
    mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  fi
  yes | "$SDKM" --licenses >/dev/null 2>&1 || true
  "$SDKM" "platforms;android-34" "build-tools;34.0.0" >/dev/null

  GV=8.7
  GRADLE="$HOME/gradle-$GV/bin/gradle"
  if [ ! -x "$GRADLE" ]; then
    curl -fsSL -o /tmp/gradle.zip "https://services.gradle.org/distributions/gradle-$GV-bin.zip"
    unzip -q -o /tmp/gradle.zip -d "$HOME"
  fi
  echo "sdk.dir=$ANDROID_HOME" > local.properties

  echo "== 4/5 APK derleniyor (5-10 dk surebilir, bekle) =="
  "$GRADLE" --no-daemon --console=plain assembleDebug > build.log 2>&1 &
  GPID=$!
  while kill -0 "$GPID" 2>/dev/null; do printf "."; sleep 10; done
  echo
  RC=0
  wait "$GPID" || RC=$?
  if [ "$RC" -ne 0 ]; then
    echo
    echo "!!! DERLEME HATASI !!!"
    echo "Asagidaki satirlari kopyalayip Claude'a gonder:"
    echo "------------------------------------------------"
    grep -E "^e: |error:|What went wrong|Execution failed|Could not" -A2 build.log | head -40
    echo "------------------------------------------------"
    exit 1
  fi
else
  mkdir -p app/build/outputs/apk/debug
  echo "test" > app/build/outputs/apk/debug/app-debug.apk
fi

APK="app/build/outputs/apk/debug/app-debug.apk"
if [ ! -f "$APK" ]; then echo "APK bulunamadi."; exit 1; fi
cp "$APK" jarvis.apk
echo "   APK derlendi: jarvis.apk"

echo "== 5/5 GitHub'a yukleniyor =="
LINK=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git remote get-url origin >/dev/null 2>&1; then
  git config user.email >/dev/null || git config user.email "jarvis@example.com"
  git config user.name  >/dev/null || git config user.name  "Jarvis"
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  mkdir -p .git/info
  for p in '.github/' 'jarvis.apk' 'build.log' 'local.properties'; do
    grep -qxF "$p" .git/info/exclude 2>/dev/null || echo "$p" >> .git/info/exclude
  done
  git fetch -q origin "$BRANCH" 2>/dev/null || true
  # Codespaces jetonu .github/workflows dosyasini gonderemez: eski commit'te varsa cikar
  if git rev-parse -q --verify "origin/$BRANCH" >/dev/null 2>&1 && \
     git log "origin/$BRANCH..HEAD" --name-only --pretty=format: | grep -q '^\.github/'; then
    git reset -q --soft "origin/$BRANCH"
    git restore --staged .github 2>/dev/null || true
  fi
  git add -A
  git commit -q -m "Jarvis: insan silüetli arayüz" || true
  if ! git push -q origin HEAD 2>/dev/null; then
    git pull -q --no-edit --rebase origin "$BRANCH" 2>/dev/null || true
    git push -q origin HEAD || echo "(Kaynak kod gonderilemedi ama APK hazir.)"
  fi

  REMOTE="$(git remote get-url origin | sed -E 's#\.git$##; s#^git@github.com:#https://github.com/#')"
  TAG="apk-$(date +%Y%m%d-%H%M%S)"
  if command -v gh >/dev/null 2>&1 && \
     OUT="$(gh release create "$TAG" jarvis.apk --title "Jarvis APK" --notes "Insan siluetli arayuz" 2>&1)"; then
    LINK="$OUT"
  else
    # Yedek yol: APK'yi depoya koy
    git add -f jarvis.apk
    git commit -q -m "APK" || true
    git push -q origin HEAD || true
    LINK="$REMOTE/blob/$BRANCH/jarvis.apk"
  fi
fi

echo
echo "=========================================="
echo " APK HAZIR"
if [ -n "$LINK" ]; then
  echo " $LINK"
  echo " Telefonda bu baglantiyi ac, jarvis.apk'ye dokun, indir ve kur."
else
  echo " Dosya: $(pwd)/jarvis.apk"
fi
echo "=========================================="
