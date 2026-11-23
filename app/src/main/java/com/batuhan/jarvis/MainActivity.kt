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
