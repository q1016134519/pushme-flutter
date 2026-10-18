package com.daimadog.pushme

/**
 * 标题/内容解析：
 *  - 标题前缀 [i] [s] [w] [f] -> 主题色（信息/成功/警告/失败）
 *  - [#分组!图片地址]        -> 分组名（头像文字）+ 头像图片
 *  - [~频道名]               -> 通知频道
 */
object TitleParser {

    private val THEME_RE = Regex("^\\[([iswfISWF])]\\s*(.*)$", RegexOption.DOT_MATCHES_ALL)
    private val GROUP_RE = Regex("\\[#([^!\\]]+)(?:!([^\\]]+))?]")
    private val CHANNEL_RE = Regex("\\[~([^]]+)]")

    data class Parsed(
        val title: String,
        val theme: String,
        val user: String,
        val face: String,
        val channel: String
    )

    fun parse(rawTitle: String?): Parsed {
        var title = rawTitle ?: ""
        var theme = ""

        THEME_RE.find(title)?.let { m ->
            theme = m.groupValues[1].lowercase()
            title = m.groupValues[2]
        }

        var user = ""
        var face = ""
        GROUP_RE.find(title)?.let { m ->
            user = m.groupValues[1].trim()
            face = m.groupValues[2].trim()
            title = title.replace(m.value, "")
        }

        var channel = ""
        CHANNEL_RE.find(title)?.let { m ->
            channel = m.groupValues[1].trim()
            title = title.replace(m.value, "")
        }

        return Parsed(
            title = title.trim(),
            theme = theme,
            user = user,
            face = face,
            channel = channel
        )
    }

    /** 列表摘要：把 markdown / html 转成纯文本并截断 */
    fun preview(content: String?, type: String?, limit: Int = 200): String {
        if (content.isNullOrEmpty()) return ""
        var text = content
        when (type) {
            "html" -> {
                text = text.replace(Regex("(?s)<(style|script)(\\s[^>]*)?>(.*?)</\\1>"), " ")
                text = text.replace(Regex("<br\\s*/?>", RegexOption.IGNORE_CASE), "\n")
                text = text.replace(Regex("</(p|div|h[1-6]|li|tr)>", RegexOption.IGNORE_CASE), "\n")
                text = text.replace(Regex("<[^>]+>"), " ")
                text = text.replace("&nbsp;", " ").replace("&amp;", "&")
                    .replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"")
            }
            "markdown" -> {
                text = text.replace(Regex("```[\\s\\S]*?```"), " ")
                text = text.replace(Regex("!\\[[^]]*]\\([^)]*\\)"), " ")
                text = text.replace(Regex("\\[([^]]*)]\\([^)]*\\)"), "$1")
                text = text.replace(Regex("(?m)^#{1,6}\\s*"), "")
                text = text.replace(Regex("(?m)^\\s*[>\\-*+]\\s+"), "")
                text = text.replace(Regex("[*_`~]"), "")
            }
        }
        text = text.replace(Regex("\\s+"), " ").trim()
        return if (text.length > limit) text.substring(0, limit) + "…" else text
    }
}
