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
