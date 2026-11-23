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
