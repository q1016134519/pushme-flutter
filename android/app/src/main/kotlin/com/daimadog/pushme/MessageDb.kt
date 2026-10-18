package com.daimadog.pushme

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * 消息本地库。
 * 表结构与旧版 PushMe 完全一致（Message 表），
 * 首次启动会自动导入随包附带的旧版消息数据。
 */
class MessageDb private constructor(context: Context) :
    SQLiteOpenHelper(context, DB_NAME, null, VERSION) {

    companion object {
        const val DB_NAME = "App.db"
        const val VERSION = 2

        @Volatile
        private var instance: MessageDb? = null

        fun get(context: Context): MessageDb {
            return instance ?: synchronized(this) {
                instance ?: run {
                    val ctx = context.applicationContext
                    ensureSeed(ctx)
                    MessageDb(ctx).also { instance = it }
                }
            }
        }

        /** Flutter 打包后资源位于 assets/flutter_assets/ 下，这里按优先级尝试多个路径 */
        private val SEED_PATHS = arrayOf(
            "flutter_assets/assets/seed/pushme_seed.db",
            "assets/seed/pushme_seed.db",
            "seed/pushme_seed.db"
        )

        /** 首次启动：把 assets 中的旧版数据复制为正式数据库 */
        private fun ensureSeed(ctx: Context) {
            try {
                val dir = ctx.getDatabasePath(DB_NAME)
                dir.parentFile?.mkdirs()
                if (dir.exists() && dir.length() > 0) return
                val flag = File(ctx.filesDir, "seed_imported.flag")
                if (flag.exists() && dir.exists()) return

                var ok = false
                var lastErr: String? = null
                for (p in SEED_PATHS) {
                    try {
                        ctx.assets.open(p).use { input ->
                            dir.outputStream().use { out -> input.copyTo(out) }
                        }
                        if (dir.length() > 0) { ok = true; break }
                    } catch (e: Exception) {
                        lastErr = "$p -> ${e.message}"
                    }
                }
                if (ok) {
                    flag.writeText("1")
                } else {
                    android.util.Log.w("PushMeDb", "seed copy failed: $lastErr")
                }
            } catch (e: Exception) {
                android.util.Log.w("PushMeDb", "seed copy failed: ${e.message}")
            }
        }
    }

    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        db.enableWriteAheadLogging()
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """CREATE TABLE IF NOT EXISTS `Message` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `title` TEXT NOT NULL DEFAULT '',
                `content` TEXT NOT NULL DEFAULT '',
                `date` TEXT NOT NULL DEFAULT '',
                `type` TEXT NOT NULL DEFAULT '',
                `read` INTEGER NOT NULL DEFAULT 1,
                `star` INTEGER NOT NULL DEFAULT 0,
                `user` TEXT NOT NULL DEFAULT '',
                `face` TEXT NOT NULL DEFAULT '',
                `theme` TEXT NOT NULL DEFAULT ''
            )"""
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS index_Message_type ON Message(type)")
        db.execSQL("CREATE INDEX IF NOT EXISTS index_Message_user ON Message(user)")
        db.execSQL("CREATE INDEX IF NOT EXISTS index_Message_date ON Message(date)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        onCreate(db)
    }

    // ---------------- 写入 ----------------

    fun insert(
        title: String,
        content: String,
        date: String,
        type: String,
        user: String,
        face: String,
        theme: String,
        unread: Boolean
    ): Long {
        val db = writableDatabase
        try {
            db.rawQuery(
                "SELECT id FROM Message WHERE title=? AND content=? AND date=? LIMIT 1",
                arrayOf(title, content, date)
            ).use { c ->
                if (c.moveToFirst()) return c.getLong(0)
            }
        } catch (_: Exception) {
        }
        val cv = ContentValues().apply {
            put("title", title)
            put("content", content)
            put("date", date)
            put("type", type)
            put("read", if (unread) 0 else 1)
            put("star", 0)
            put("user", user)
            put("face", face)
            put("theme", theme)
        }
        return db.insert("Message", null, cv)
    }

    fun markRead(ids: List<Long>, read: Boolean) {
        if (ids.isEmpty()) return
        writableDatabase.execSQL(
            "UPDATE Message SET read=${if (read) 1 else 0} WHERE id IN (${ids.joinToString(",")})"
        )
    }

    fun star(ids: List<Long>, star: Boolean) {
        if (ids.isEmpty()) return
        writableDatabase.execSQL(
            "UPDATE Message SET star=${if (star) 1 else 0} WHERE id IN (${ids.joinToString(",")})"
        )
    }

    fun delete(ids: List<Long>) {
        if (ids.isEmpty()) return
        writableDatabase.execSQL("DELETE FROM Message WHERE id IN (${ids.joinToString(",")})")
    }

    fun clearAll() = writableDatabase.execSQL("DELETE FROM Message")

    fun markAllRead() = writableDatabase.execSQL("UPDATE Message SET read=1 WHERE read=0")

    // ---------------- 查询 ----------------

    private fun whereClause(
        query: String,
        field: String,
        theme: String,
        status: String
    ): Pair<String, MutableList<String>> {
        val sb = StringBuilder("1=1")
        val args = mutableListOf<String>()
        if (query.isNotBlank()) {
            val q = "%$query%"
            when (field) {
                "标题" -> { sb.append(" AND title LIKE ?"); args.add(q) }
                "内容" -> { sb.append(" AND content LIKE ?"); args.add(q) }
                else -> { sb.append(" AND (title LIKE ? OR content LIKE ?)"); args.add(q); args.add(q) }
            }
        }
        if (theme.isNotBlank() && theme != "全部") {
            val t = when (theme) {
                "信息" -> "i"; "成功" -> "s"; "警告" -> "w"; "失败" -> "f"; else -> ""
            }
            if (t.isNotEmpty()) { sb.append(" AND theme=?"); args.add(t) }
        }
        when (status) {
            "已读" -> sb.append(" AND read=1")
            "未读" -> sb.append(" AND read=0")
            "收藏" -> sb.append(" AND star=1")
            "未藏" -> sb.append(" AND star=0")
        }
        return sb.toString() to args
    }

    fun list(
        offset: Int,
        limit: Int,
        query: String,
        field: String,
        theme: String,
        status: String,
        sortBy: String,
        sort: String
    ): JSONObject {
        val (where, args) = whereClause(query, field, theme, status)
        val order = when (sortBy) {
            "主题" -> "theme"
            "标题" -> "title"
            "类型" -> "type"
            else -> "date"
        } + if (sort == "asc") " ASC" else " DESC"
        val db = readableDatabase
        val arr = JSONArray()
        db.rawQuery(
            "SELECT id,title,content,date,type,read,star,user,face,theme FROM Message " +
                "WHERE $where ORDER BY $order, id DESC LIMIT ? OFFSET ?",
            (args + listOf(limit.toString(), offset.toString())).toTypedArray()
        ).use { c ->
            while (c.moveToNext()) arr.put(rowToJson(c))
        }
        val total = db.rawQuery("SELECT COUNT(*) FROM Message WHERE $where", args.toTypedArray()).use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
        return JSONObject().put("total", total).put("items", arr)
    }

    private fun rowToJson(c: Cursor): JSONObject {
        val type = c.getString(4) ?: ""
        return JSONObject()
            .put("id", c.getLong(0))
            .put("title", c.getString(1) ?: "")
            .put("content", c.getString(2) ?: "")
            .put("date", c.getString(3) ?: "")
            .put("type", type)
            .put("read", c.getInt(5) == 1)
            .put("star", c.getInt(6) == 1)
            .put("user", c.getString(7) ?: "")
            .put("face", c.getString(8) ?: "")
            .put("theme", c.getString(9) ?: "")
            .put("preview", TitleParser.preview(c.getString(2), type))
    }

    fun get(id: Long): JSONObject? {
        readableDatabase.rawQuery(
            "SELECT id,title,content,date,type,read,star,user,face,theme FROM Message WHERE id=?",
            arrayOf(id.toString())
        ).use { c -> return if (c.moveToFirst()) rowToJson(c) else null }
    }

    fun counts(): JSONObject {
        val db = readableDatabase
        var total = 0
        var unread = 0
        var starred = 0
        db.rawQuery("SELECT COUNT(*), SUM(read=0), SUM(star=1) FROM Message", null).use {
            if (it.moveToFirst()) {
                total = it.getInt(0)
                unread = it.getInt(1)
                starred = it.getInt(2)
            }
        }
        return JSONObject().put("total", total).put("unread", unread).put("starred", starred)
    }

    fun stats(): JSONObject {
        val db = readableDatabase
        val byTheme = JSONObject().apply {
            put("i", 0); put("s", 0); put("w", 0); put("f", 0); put("none", 0)
        }
        db.rawQuery("SELECT theme, COUNT(*) FROM Message GROUP BY theme", null).use { c ->
            while (c.moveToNext()) {
                val k = c.getString(0) ?: ""
                if (k.isEmpty()) byTheme.put("none", byTheme.optInt("none") + c.getInt(1))
                else byTheme.put(k, c.getInt(1))
            }
        }
        val byType = JSONArray()
        db.rawQuery("SELECT type, COUNT(*) FROM Message GROUP BY type ORDER BY 2 DESC", null).use { c ->
            while (c.moveToNext()) {
                byType.put(
                    JSONObject()
                        .put("name", if ((c.getString(0) ?: "").isEmpty()) "text" else c.getString(0))
                        .put("count", c.getInt(1))
                )
            }
        }
        val byUser = JSONArray()
        db.rawQuery(
            "SELECT CASE WHEN user='' THEN '未分组' ELSE user END AS u, COUNT(*) FROM Message " +
                "GROUP BY u ORDER BY 2 DESC LIMIT 8", null
        ).use { c ->
            while (c.moveToNext()) byUser.put(JSONObject().put("name", c.getString(0)).put("count", c.getInt(1)))
        }
        val days = JSONArray()
        val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val cal = Calendar.getInstance()
        cal.add(Calendar.DAY_OF_YEAR, -13)
        val countMap = HashMap<String, Int>()
        // 键值形如 2026-10-17
        db.rawQuery("SELECT substr(date,1,10) d, COUNT(*) FROM Message GROUP BY d", null).use { c ->
            while (c.moveToNext()) countMap[c.getString(0) ?: ""] = c.getInt(1)
        }
        for (i in 0 until 14) {
            val key = fmt.format(cal.time)
            days.put(JSONObject().put("date", key).put("count", countMap[key] ?: 0))
            cal.add(Calendar.DAY_OF_YEAR, 1)
        }
        return JSONObject()
            .put("byTheme", byTheme)
            .put("byType", byType)
            .put("byUser", byUser)
            .put("byDay", days)
    }

    fun todayCount(): Int {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        return readableDatabase.rawQuery(
            "SELECT COUNT(*) FROM Message WHERE date LIKE ?", arrayOf("$today%")
        ).use { if (it.moveToFirst()) it.getInt(0) else 0 }
    }
}
