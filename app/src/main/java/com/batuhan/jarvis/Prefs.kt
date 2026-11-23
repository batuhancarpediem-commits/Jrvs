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
