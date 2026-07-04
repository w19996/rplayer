#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <regex>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace {

struct ParsedDigits {
    bool has_value = false;
    int value = 0;
    std::size_t consumed = 0;
};

struct ParseInfo {
    std::string cleaned_title;
    std::string media_type_hint = "unknown";
    bool title_search_allowed = false;
    bool has_year = false;
    int year = 0;
    bool has_season = false;
    int season = 0;
    bool has_episode = false;
    int episode = 0;
    std::vector<std::string> version_tags;
    bool matches_version_dir_regex = false;
    bool is_common_dir = false;
    bool is_pure_version_dir = false;
    bool is_pure_season_dir = false;
};

struct VersionContext {
    bool has_value = false;
    std::string version_name;
    std::string version_dir_path;
    std::vector<std::string> tags;
};

struct SearchCandidate {
    std::string title;
    std::string media_type_hint = "unknown";
    bool has_year = false;
    int year = 0;
    bool has_season = false;
    int season = 0;
    bool has_episode = false;
    int episode = 0;
    std::string version_name;
    std::vector<std::string> version_tags;
    std::string version_dir_path;
    std::string source_type;
    std::string source_path;
    double confidence = 0.0;
    std::vector<std::string> warnings;
};

std::string input_string(const char* value) {
    return value == nullptr ? std::string() : std::string(value);
}

bool ascii_space(unsigned char ch) {
    return std::isspace(ch) != 0;
}

std::string trim(const std::string& value) {
    std::size_t start = 0;
    while (start < value.size() && ascii_space(static_cast<unsigned char>(value[start]))) {
        ++start;
    }
    std::size_t end = value.size();
    while (end > start && ascii_space(static_cast<unsigned char>(value[end - 1]))) {
        --end;
    }
    return value.substr(start, end - start);
}

std::string lower_ascii(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
        return static_cast<char>(std::tolower(ch));
    });
    return value;
}

bool starts_with(const std::string& value, const std::string& prefix) {
    return value.size() >= prefix.size() &&
           std::equal(prefix.begin(), prefix.end(), value.begin());
}

bool contains_text(const std::string& value, const std::string& needle) {
    return value.find(needle) != std::string::npos;
}

std::string strip_extension(const std::string& file_name) {
    const auto index = file_name.find_last_of('.');
    return index == std::string::npos ? file_name : file_name.substr(0, index);
}

std::vector<std::string> split_path(const std::string& path, bool include_backslash) {
    std::vector<std::string> parts;
    std::string current;
    for (const char ch : path) {
        const bool separator = ch == '/' || (include_backslash && ch == '\\');
        if (separator) {
            if (!current.empty()) {
                parts.push_back(current);
                current.clear();
            }
        } else {
            current.push_back(ch);
        }
    }
    if (!current.empty()) {
        parts.push_back(current);
    }
    return parts;
}

std::string join_path(const std::vector<std::string>& parts, std::size_t end_exclusive) {
    if (end_exclusive == 0 || parts.empty()) {
        return std::string();
    }
    std::ostringstream out;
    for (std::size_t index = 0; index < end_exclusive && index < parts.size(); ++index) {
        if (index > 0) {
            out << '/';
        }
        out << parts[index];
    }
    return out.str();
}

std::string last_path_part(const std::string& path) {
    const auto parts = split_path(path, true);
    return parts.empty() ? std::string() : parts.back();
}

std::string parent_path_string(const std::string& path) {
    const auto parts = split_path(path, true);
    if (parts.size() <= 1) {
        return std::string();
    }
    return join_path(parts, parts.size() - 1);
}

std::string basename_from_parts(const std::vector<std::string>& parts) {
    return parts.empty() ? std::string() : parts.back();
}

bool parse_u16_token(const std::string& token, int& value) {
    if (token.empty() || token.size() > 5) {
        return false;
    }
    int parsed = 0;
    for (const unsigned char ch : token) {
        if (std::isdigit(ch) == 0) {
            return false;
        }
        parsed = parsed * 10 + static_cast<int>(ch - '0');
        if (parsed > 65535) {
            return false;
        }
    }
    value = parsed;
    return true;
}

bool parse_year_token(const std::string& token, int& year) {
    int value = 0;
    if (parse_u16_token(token, value) && value >= 1888 && value <= 2100) {
        year = value;
        return true;
    }
    return false;
}

ParsedDigits parse_digits(const std::string& input, std::size_t start, std::size_t max_digits) {
    ParsedDigits result;
    for (std::size_t index = start; index < input.size() && result.consumed < max_digits; ++index) {
        const unsigned char ch = static_cast<unsigned char>(input[index]);
        if (std::isdigit(ch) == 0) {
            break;
        }
        result.value = result.value * 10 + static_cast<int>(ch - '0');
        result.has_value = true;
        ++result.consumed;
    }
    return result;
}

std::vector<std::string> tokenize(const std::string& input) {
    std::vector<std::string> tokens;
    std::string current;
    for (const char ch : input) {
        const bool separator = ch == '.' || ch == '_' || ch == '-' || ch == '~' ||
                               ch == '+' ||
                               ch == '[' || ch == ']' || ch == '(' || ch == ')' ||
                               ch == '{' || ch == '}' || ascii_space(static_cast<unsigned char>(ch));
        if (separator) {
            if (!current.empty()) {
                tokens.push_back(current);
                current.clear();
            }
        } else {
            current.push_back(ch);
        }
    }
    if (!current.empty()) {
        tokens.push_back(current);
    }
    return tokens;
}

bool is_common_dir_name(const std::string& text) {
    const std::string lower = lower_ascii(trim(text));
    static const std::vector<std::string> common = {
        "tv", "series", "shows", "movies", "media", "video", "videos",
        "download", "downloads", "quark", "alist", "openlist",
    };
    if (std::find(common.begin(), common.end(), lower) != common.end()) {
        return true;
    }
    static const std::vector<std::string> zh = {
        "影视", "视频", "电视剧", "剧集", "动漫", "番剧", "综艺",
        "电影", "资源", "下载", "夸克", "夸克网盘", "百度网盘", "阿里云盘",
        "来自：分享", "来自分享", "分享", "片头尾", "花絮",
    };
    return std::find(zh.begin(), zh.end(), text) != zh.end();
}

bool is_named_version_common_dir_name(const std::string& text) {
    const std::string lower = lower_ascii(trim(text));
    static const std::vector<std::string> common_versions = {
        "extras", "extra", "bonus", "special features", "featurettes",
        "behind the scenes", "behind-the-scenes", "bts", "trailers", "trailer",
    };
    if (std::find(common_versions.begin(), common_versions.end(), lower) != common_versions.end()) {
        return true;
    }
    static const std::vector<std::string> zh = {
        "片头尾", "花絮", "特典", "番外", "彩蛋", "预告", "幕后",
    };
    return std::find(zh.begin(), zh.end(), text) != zh.end();
}

std::string common_dir_media_hint(const std::string& text) {
    const std::string lower = lower_ascii(trim(text));
    if (lower == "movie" || lower == "movies" || text == "电影") {
        return "movie";
    }
    if (lower == "tv" || lower == "series" || lower == "shows" || lower == "show" ||
        text == "电视剧" || text == "剧集" || text == "动漫" || text == "番剧" || text == "综艺") {
        return "tv";
    }
    return "unknown";
}

std::string merge_media_hint(const std::string& left, const std::string& right) {
    if (left == right) {
        return left;
    }
    if (left == "tv" || right == "tv") {
        return "tv";
    }
    if (left == "movie" || right == "movie") {
        return "movie";
    }
    return "unknown";
}

const std::vector<std::string>& ascii_version_words() {
    static const std::vector<std::string> tags = {
        "dolbyvision", "hdr10+", "hdr10", "2160p", "1080p", "720p", "480p",
        "120fps", "60fps", "webrip", "web-dl", "bluray", "blu-ray", "bdrip",
        "remux", "hdtv", "tvrip", "dvdrip", "truehd", "dts-hd", "h265",
        "h.265", "hevc", "h264", "h.264", "x265", "x264", "avc", "av1",
        "vp9", "10bit", "8bit", "atmos", "dolby", "hdr", "sdr", "uhd",
        "fhd", "4k", "8k", "hq", "dl", "dv", "hlg", "bd", "hd", "sd",
        "web", "raw", "internal", "subs", "subtitle", "subtitles", "aac",
        "ac3", "eac3", "ddp", "dts", "5.1", "7.1",
    };
    return tags;
}

bool is_version_token(const std::string& token) {
    const std::string lower = lower_ascii(token);
    const auto& tags = ascii_version_words();
    if (std::find(tags.begin(), tags.end(), lower) != tags.end()) {
        return true;
    }
    if (lower == "video" || lower == "videos") {
        return true;
    }
    static const std::vector<std::string> zh = {
        "高码率", "低码率", "高帧率", "原盘", "蓝光", "压制版",
        "网盘版", "收藏版", "无水印", "杜比", "杜比视界", "国语", "粤语",
        "日语", "英语", "中字", "简中", "繁中", "内封", "外挂字幕",
        "简繁字幕", "简繁英字幕", "中英字幕", "字幕", "简繁", "双语",
    };
    if (std::find(zh.begin(), zh.end(), token) != zh.end()) {
        return true;
    }
    if (lower.size() > 3 && lower.size() <= 6 && lower.rfind("fps") == lower.size() - 3) {
        int value = 0;
        return parse_u16_token(lower.substr(0, lower.size() - 3), value);
    }
    return false;
}

void erase_all(std::string& value, const std::string& needle) {
    if (needle.empty()) {
        return;
    }
    std::size_t index = 0;
    while ((index = value.find(needle, index)) != std::string::npos) {
        value.erase(index, needle.size());
    }
}

void replace_all_with_space(std::string& value, const std::string& needle) {
    if (needle.empty()) {
        return;
    }
    std::size_t index = 0;
    while ((index = value.find(needle, index)) != std::string::npos) {
        value.replace(index, needle.size(), " ");
        ++index;
    }
}

std::string normalize_text_separators(std::string value) {
    static const std::vector<std::string> separators = {
        "（", "）", "【", "】", "《", "》", "「", "」", "『", "』",
        "，", "、", "；", ";",
    };
    for (const auto& separator : separators) {
        replace_all_with_space(value, separator);
    }
    return value;
}

std::string remove_ascii_word_case_insensitive(const std::string& value, const std::string& needle) {
    std::string output = value;
    std::string lower = lower_ascii(output);
    std::size_t index = 0;
    while ((index = lower.find(needle, index)) != std::string::npos) {
        output.erase(index, needle.size());
        lower.erase(index, needle.size());
    }
    return output;
}

std::string strip_embedded_version_words(const std::string& token, std::vector<std::string>& version_tags) {
    std::string remaining = token;
    for (const auto& tag : ascii_version_words()) {
        const std::string before = remaining;
        remaining = remove_ascii_word_case_insensitive(remaining, tag);
        if (before != remaining) {
            version_tags.push_back(tag);
        }
    }
    static const std::vector<std::string> zh_tags = {
        "杜比视界", "简繁英字幕", "简繁字幕", "中英字幕", "外挂字幕",
        "高码率", "低码率", "高帧率", "原盘", "蓝光", "压制版",
        "网盘版", "收藏版", "无水印", "杜比", "国语", "粤语", "日语",
        "英语", "中字", "简中", "繁中", "内封", "字幕", "简繁", "双语",
    };
    for (const auto& tag : zh_tags) {
        const std::string before = remaining;
        erase_all(remaining, tag);
        if (before != remaining) {
            version_tags.push_back(tag);
        }
    }
    return trim(remaining);
}

std::vector<std::string> split_lines(const std::string& input) {
    std::vector<std::string> lines;
    std::string current;
    for (const char ch : input) {
        if (ch == '\n') {
            lines.push_back(trim(current));
            current.clear();
        } else if (ch != '\r') {
            current.push_back(ch);
        }
    }
    lines.push_back(trim(current));
    return lines;
}

std::vector<std::regex>& custom_version_directory_regexes() {
    static std::vector<std::regex> patterns;
    return patterns;
}

std::string set_custom_version_directory_regexes(const std::string& patterns_text) {
    std::vector<std::regex> compiled;
    int index = 0;
    for (const auto& pattern : split_lines(patterns_text)) {
        if (pattern.empty()) {
            continue;
        }
        ++index;
        if (pattern.size() > 512) {
            return "invalid version directory regex #" + std::to_string(index) + ": pattern is too long";
        }
        try {
            compiled.emplace_back(pattern, std::regex_constants::icase);
        } catch (const std::regex_error& error) {
            return "invalid version directory regex #" + std::to_string(index) +
                   ": " + pattern + " (" + error.what() + ")";
        }
    }

    custom_version_directory_regexes() = std::move(compiled);
    return std::string();
}

bool is_version_directory_by_regex(const std::string& text, std::vector<std::string>& version_tags) {
    static const std::vector<std::regex> patterns = {
        std::regex(R"((8k|4k|2160p|1080p|720p|480p|uhd|fhd|hd|sd))", std::regex_constants::icase),
        std::regex(R"(((120|60|[2-9][0-9])\s*fps))", std::regex_constants::icase),
        std::regex(R"((hdr10\+?|dolby\s*vision|dolbyvision|dv|hlg|sdr|hdr))", std::regex_constants::icase),
        std::regex(R"((web\s*[- ]?\s*dl|webrip|blu\s*[- ]?\s*ray|bdrip|remux|hdtv|tvrip|dvdrip|raw|hq|dl))", std::regex_constants::icase),
        std::regex(R"((h\.?\s*265|x265|hevc|h\.?\s*264|x264|avc|av1|vp9|10\s*bit|8\s*bit))", std::regex_constants::icase),
        std::regex(R"((aac|eac3|ac3|ddp|dts\s*-?\s*hd|dts|truehd|atmos|5\.1|7\.1))", std::regex_constants::icase),
        std::regex(R"(第\s*(\d+|[一二三四五六七八九十零〇两]+)\s*(章|季))", std::regex_constants::icase),
    };
    const std::string normalized = normalize_text_separators(text);
    for (const auto& pattern : patterns) {
        if (std::regex_search(normalized, pattern)) {
            version_tags.push_back(trim(text));
            return true;
        }
    }
    for (const auto& pattern : custom_version_directory_regexes()) {
        if (std::regex_search(normalized, pattern)) {
            version_tags.push_back(trim(text));
            return true;
        }
    }
    return false;
}

bool is_episode_marker_token(const std::string& token) {
    const std::string lower = lower_ascii(token);
    if (starts_with(lower, "ep")) {
        int value = 0;
        return parse_u16_token(lower.substr(2), value);
    }
    if (lower.size() >= 2 && lower.front() == 'e') {
        int value = 0;
        return parse_u16_token(lower.substr(1), value);
    }
    return lower.find('s') != std::string::npos && lower.find('e') != std::string::npos;
}

bool is_total_episode_count_token(const std::string& token) {
    if (!starts_with(token, "全")) {
        return false;
    }
    return contains_text(token, "集") || contains_text(token, "季") || contains_text(token, "话");
}

bool parse_sxe(const std::string& input, bool& has_season, int& season, bool& has_episode, int& episode) {
    const std::string lower = lower_ascii(input);
    for (std::size_t index = 0; index < lower.size(); ++index) {
        if (lower[index] != 's') {
            continue;
        }
        const ParsedDigits season_digits = parse_digits(lower, index + 1, 2);
        const std::size_t e_index = index + 1 + season_digits.consumed;
        if (!season_digits.has_value || e_index >= lower.size() || lower[e_index] != 'e') {
            continue;
        }
        const ParsedDigits episode_digits = parse_digits(lower, e_index + 1, 3);
        has_season = true;
        season = season_digits.value;
        if (episode_digits.has_value) {
            has_episode = true;
            episode = episode_digits.value;
        }
        return true;
    }
    return false;
}

bool parse_ep_token(const std::string& token, int& episode) {
    const std::string lower = lower_ascii(token);
    if (starts_with(lower, "ep")) {
        return parse_u16_token(lower.substr(2), episode) && episode > 0;
    }
    if (lower.size() >= 2 && lower.front() == 'e') {
        return parse_u16_token(lower.substr(1), episode) && episode > 0;
    }
    return false;
}

int chinese_number_value(const std::string& text) {
    if (text == "零") return 0;
    if (text == "一") return 1;
    if (text == "二" || text == "两") return 2;
    if (text == "三") return 3;
    if (text == "四") return 4;
    if (text == "五") return 5;
    if (text == "六") return 6;
    if (text == "七") return 7;
    if (text == "八") return 8;
    if (text == "九") return 9;
    if (text == "十") return 10;
    if (starts_with(text, "十")) {
        const int ones = chinese_number_value(text.substr(std::string("十").size()));
        return ones >= 0 ? 10 + ones : -1;
    }
    const auto ten = text.find("十");
    if (ten != std::string::npos) {
        const int tens = chinese_number_value(text.substr(0, ten));
        const int ones = chinese_number_value(text.substr(ten + std::string("十").size()));
        if (tens > 0) {
            return tens * 10 + std::max(0, ones);
        }
    }
    return -1;
}

bool parse_chinese_between(const std::string& input, const std::string& prefix, const std::string& suffix, int& value) {
    const auto start = input.find(prefix);
    if (start == std::string::npos) {
        return false;
    }
    const auto number_start = start + prefix.size();
    const auto end = input.find(suffix, number_start);
    if (end == std::string::npos || end <= number_start) {
        return false;
    }
    const std::string number_text = input.substr(number_start, end - number_start);
    int parsed = 0;
    if (parse_u16_token(number_text, parsed)) {
        value = parsed;
        return true;
    }
    parsed = chinese_number_value(number_text);
    if (parsed >= 0) {
        value = parsed;
        return true;
    }
    return false;
}

bool parse_season_words(const std::string& input, int& season) {
    const std::string lower = lower_ascii(input);
    const auto pos = lower.find("season");
    if (pos != std::string::npos) {
        std::size_t index = pos + 6;
        while (index < lower.size() && !std::isdigit(static_cast<unsigned char>(lower[index]))) {
            ++index;
        }
        const ParsedDigits digits = parse_digits(lower, index, 2);
        if (digits.has_value) {
            season = digits.value;
            return true;
        }
    }
    if (!lower.empty() && lower[0] == 's') {
        const ParsedDigits digits = parse_digits(lower, 1, 2);
        if (digits.has_value && digits.consumed + 1 == lower.size()) {
            season = digits.value;
            return true;
        }
    }
    return parse_chinese_between(input, "第", "季", season);
}

bool infer_episode_from_numeric_basename(const std::string& input, int& episode) {
    std::size_t index = 0;
    while (index < input.size() && ascii_space(static_cast<unsigned char>(input[index]))) {
        ++index;
    }
    const ParsedDigits digits = parse_digits(input, index, 3);
    if (!digits.has_value || digits.value < 1 || digits.value > 999) {
        return false;
    }
    episode = digits.value;
    return true;
}

std::string join_tokens(const std::vector<std::string>& tokens) {
    std::ostringstream out;
    for (std::size_t index = 0; index < tokens.size(); ++index) {
        if (index > 0) {
            out << ' ';
        }
        out << tokens[index];
    }
    return trim(out.str());
}

std::vector<std::string> merge_tags(const std::vector<std::string>& a, const std::vector<std::string>& b) {
    std::vector<std::string> out = a;
    for (const auto& tag : b) {
        if (std::find(out.begin(), out.end(), tag) == out.end()) {
            out.push_back(tag);
        }
    }
    return out;
}

ParseInfo parse_text(const std::string& text, bool filename) {
    ParseInfo info;
    const std::string stem = normalize_text_separators(filename ? strip_extension(text) : text);
    info.is_common_dir = !filename && is_common_dir_name(trim(stem));
    std::vector<std::string> version_dir_tags;
    info.matches_version_dir_regex = !filename && is_version_directory_by_regex(stem, version_dir_tags);
    if (info.is_common_dir) {
        info.media_type_hint = common_dir_media_hint(trim(stem));
    }

    if (parse_sxe(stem, info.has_season, info.season, info.has_episode, info.episode)) {
        info.media_type_hint = "tv";
    }
    if (!info.has_season) {
        info.has_season = parse_season_words(stem, info.season);
        if (info.has_season) {
            info.media_type_hint = "tv";
        }
    }
    int episode_from_cn = 0;
    if (!info.has_episode && parse_chinese_between(stem, "第", "集", episode_from_cn)) {
        info.has_episode = true;
        info.episode = episode_from_cn;
        info.media_type_hint = "tv";
    }

    std::vector<std::string> title_tokens;
    for (const auto& token : tokenize(stem)) {
        int year = 0;
        int ep = 0;
        int season = 0;
        if (parse_year_token(token, year)) {
            info.has_year = true;
            info.year = year;
            continue;
        }
        if (is_version_token(token)) {
            info.version_tags.push_back(token);
            continue;
        }
        const std::string stripped = strip_embedded_version_words(token, info.version_tags);
        if (stripped.empty()) {
            continue;
        }
        if (is_episode_marker_token(token) || parse_ep_token(token, ep)) {
            info.media_type_hint = "tv";
            if (ep > 0 && !info.has_episode) {
                info.has_episode = true;
                info.episode = ep;
            }
            continue;
        }
        if (is_total_episode_count_token(token)) {
            info.media_type_hint = "tv";
            continue;
        }
        if (parse_season_words(token, season)) {
            info.media_type_hint = "tv";
            if (!info.has_season) {
                info.has_season = true;
                info.season = season;
            }
            continue;
        }
        int numeric = 0;
        if (parse_u16_token(token, numeric)) {
            if (filename && !info.has_episode && numeric > 0 && numeric <= 999) {
                info.has_episode = true;
                info.episode = numeric;
                info.media_type_hint = "tv";
            }
            continue;
        }
        title_tokens.push_back(stripped);
    }

    info.cleaned_title = join_tokens(title_tokens);
    if (info.matches_version_dir_regex) {
        info.version_tags = merge_tags(info.version_tags, version_dir_tags);
        if (info.cleaned_title.size() < 2) {
            info.cleaned_title.clear();
            info.has_season = false;
        }
    }
    if (info.media_type_hint == "unknown" && info.has_year && !info.has_episode && !info.has_season) {
        info.media_type_hint = "movie";
    }
    const bool title_empty = info.cleaned_title.empty();
    info.is_pure_version_dir = !filename && title_empty && !info.version_tags.empty() && !info.has_season;
    info.is_pure_season_dir = !filename && title_empty && info.has_season;
    info.title_search_allowed = !title_empty && info.cleaned_title.size() >= 2;
    return info;
}

std::string version_name_from_tags(const std::vector<std::string>& tags) {
    const std::string name = join_tokens(tags);
    return name.empty() ? "Original" : name;
}

SearchCandidate make_candidate(
    const ParseInfo& title_info,
    const ParseInfo& file_info,
    const VersionContext& context,
    const std::string& context_media_hint,
    const std::string&,
    const std::string& source_path,
    bool from_filename) {
    SearchCandidate candidate;
    candidate.title = title_info.cleaned_title;
    candidate.media_type_hint = merge_media_hint(context_media_hint, title_info.media_type_hint);
    candidate.media_type_hint = merge_media_hint(candidate.media_type_hint, file_info.media_type_hint);
    if (candidate.media_type_hint == "unknown" &&
        (title_info.has_year || file_info.has_year) &&
        !file_info.has_episode &&
        !file_info.has_season &&
        !title_info.has_season) {
        candidate.media_type_hint = "movie";
    }
    candidate.has_year = title_info.has_year || file_info.has_year;
    candidate.year = title_info.has_year ? title_info.year : file_info.year;
    candidate.has_episode = candidate.media_type_hint == "tv" && file_info.has_episode;
    candidate.episode = candidate.has_episode ? file_info.episode : 0;
    candidate.source_type = from_filename ? "filename" : "directory";
    candidate.source_path = source_path;

    if (candidate.media_type_hint == "tv" && file_info.has_season) {
        candidate.has_season = true;
        candidate.season = file_info.season;
        if (title_info.has_season && title_info.season != file_info.season) {
            candidate.warnings.push_back("season_conflict");
        }
    } else if (candidate.media_type_hint == "tv" && title_info.has_season) {
        candidate.has_season = true;
        candidate.season = title_info.season;
    } else if (candidate.media_type_hint == "tv") {
        candidate.has_season = true;
        candidate.season = 1;
    }

    candidate.version_tags = merge_tags(context.tags, title_info.version_tags);
    candidate.version_tags = merge_tags(candidate.version_tags, file_info.version_tags);
    if (context.has_value) {
        candidate.version_name = context.version_name;
        candidate.version_dir_path = context.version_dir_path;
    } else {
        candidate.version_name = "默认";
        candidate.version_dir_path = from_filename ? parent_path_string(source_path) : source_path;
    }
    candidate.confidence = from_filename ? 0.55 : 0.85;
    if (candidate.media_type_hint == "tv" && !candidate.has_episode) {
        candidate.warnings.push_back("missing_episode");
    }
    return candidate;
}

std::string json_escape(const std::string& value) {
    std::ostringstream out;
    for (const unsigned char ch : value) {
        switch (ch) {
            case '"': out << "\\\""; break;
            case '\\': out << "\\\\"; break;
            case '\b': out << "\\b"; break;
            case '\f': out << "\\f"; break;
            case '\n': out << "\\n"; break;
            case '\r': out << "\\r"; break;
            case '\t': out << "\\t"; break;
            default:
                if (ch < 0x20) {
                    const char* hex = "0123456789abcdef";
                    out << "\\u00" << hex[(ch >> 4) & 0x0F] << hex[ch & 0x0F];
                } else {
                    out << static_cast<char>(ch);
                }
        }
    }
    return out.str();
}

std::string json_string(const std::string& value) {
    return "\"" + json_escape(value) + "\"";
}

std::string json_optional_int(bool has_value, int value) {
    return has_value ? std::to_string(value) : "null";
}

std::string json_string_array(const std::vector<std::string>& values) {
    std::ostringstream out;
    out << '[';
    for (std::size_t index = 0; index < values.size(); ++index) {
        if (index > 0) {
            out << ',';
        }
        out << json_string(values[index]);
    }
    out << ']';
    return out.str();
}

std::string candidate_json(const SearchCandidate& candidate) {
    std::ostringstream json;
    json << "{"
         << "\"title\":" << json_string(candidate.title) << ","
         << "\"media_type_hint\":" << json_string(candidate.media_type_hint) << ","
         << "\"year\":" << json_optional_int(candidate.has_year, candidate.year) << ","
         << "\"season_number\":" << json_optional_int(candidate.has_season, candidate.season) << ","
         << "\"episode_number\":" << json_optional_int(candidate.has_episode, candidate.episode) << ","
         << "\"version_name\":" << json_string(candidate.version_name) << ","
         << "\"version_tags\":" << json_string_array(candidate.version_tags) << ","
         << "\"version_dir_path\":" << json_string(candidate.version_dir_path) << ","
         << "\"source_type\":" << json_string(candidate.source_type) << ","
         << "\"source_path\":" << json_string(candidate.source_path) << ","
         << "\"confidence\":" << candidate.confidence << ","
         << "\"warnings\":" << json_string_array(candidate.warnings)
         << "}";
    return json.str();
}

std::string candidates_json(const std::vector<SearchCandidate>& candidates) {
    std::ostringstream json;
    json << '[';
    for (std::size_t index = 0; index < candidates.size(); ++index) {
        if (index > 0) {
            json << ',';
        }
        json << candidate_json(candidates[index]);
    }
    json << ']';
    return json.str();
}

std::vector<SearchCandidate> parse_path_candidates(const std::string& source_type, const std::string& path) {
    const bool remote = lower_ascii(source_type) == "webdav" || lower_ascii(source_type) == "remote";
    const auto parts = split_path(path, !remote);
    if (parts.empty()) {
        return {};
    }

    const std::string file_name = basename_from_parts(parts);
    ParseInfo file_info = parse_text(file_name, true);
    if (!file_info.has_episode) {
        int episode = 0;
        if (infer_episode_from_numeric_basename(strip_extension(file_name), episode)) {
            file_info.has_episode = true;
            file_info.episode = episode;
            file_info.media_type_hint = "tv";
        }
    }

    std::vector<SearchCandidate> candidates;
    VersionContext context;
    std::string context_media_hint = "unknown";
    bool pending_leaf_title = false;
    ParseInfo pending_leaf_info;
    std::string pending_leaf_path;
    if (parts.size() >= 2) {
        for (std::size_t offset = 0; offset + 1 < parts.size(); ++offset) {
            const std::size_t index = parts.size() - 2 - offset;
            const std::string dir_name = parts[index];
            if (index == 0 && contains_text(dir_name, ":")) {
                continue;
            }
            const ParseInfo dir_info = parse_text(dir_name, false);
            const std::string dir_path = join_path(parts, index + 1);

            if (dir_info.is_pure_version_dir) {
                if (!context.has_value) {
                    context.version_name = dir_name;
                    context.version_dir_path = dir_path;
                }
                context.has_value = true;
                context.tags = merge_tags(context.tags, dir_info.version_tags);
                continue;
            }
            if (dir_info.is_pure_season_dir || dir_info.is_common_dir) {
                if (dir_info.is_common_dir && !context.has_value &&
                    index + 2 == parts.size() && is_named_version_common_dir_name(trim(dir_name))) {
                    context.has_value = true;
                    context.version_name = dir_name;
                    context.version_dir_path = dir_path;
                }
                if (dir_info.is_pure_season_dir && !file_info.has_season) {
                    file_info.has_season = true;
                    file_info.season = dir_info.season;
                    file_info.media_type_hint = "tv";
                }
                if (dir_info.is_pure_season_dir) {
                    context_media_hint = merge_media_hint(context_media_hint, "tv");
                } else {
                    context_media_hint = merge_media_hint(context_media_hint, dir_info.media_type_hint);
                }
                continue;
            }
            if (dir_info.title_search_allowed) {
                const bool episodic_file = file_info.has_episode || file_info.has_season;
                if (!context.has_value && !pending_leaf_title && episodic_file &&
                    dir_info.matches_version_dir_regex && candidates.empty()) {
                    pending_leaf_title = true;
                    pending_leaf_info = dir_info;
                    pending_leaf_path = dir_path;
                    continue;
                }
                VersionContext candidate_context = context;
                if (pending_leaf_title && !candidate_context.has_value) {
                    candidate_context.has_value = true;
                    candidate_context.version_name = last_path_part(pending_leaf_path);
                    candidate_context.version_dir_path = pending_leaf_path;
                    candidate_context.tags = pending_leaf_info.version_tags;
                }
                candidates.push_back(make_candidate(
                    dir_info, file_info, candidate_context, context_media_hint, source_type, dir_path, false));
                if (pending_leaf_title) {
                    candidates.push_back(make_candidate(
                        pending_leaf_info, file_info, context, context_media_hint, source_type, pending_leaf_path, false));
                    pending_leaf_title = false;
                }
                if (file_info.title_search_allowed) {
                    candidates.push_back(make_candidate(
                        file_info, file_info, candidate_context, context_media_hint, source_type, path, true));
                }
            }
        }
    }

    if (candidates.empty() && pending_leaf_title) {
        candidates.push_back(make_candidate(
            pending_leaf_info, file_info, context, context_media_hint, source_type, pending_leaf_path, false));
    }
    if (candidates.empty() && file_info.title_search_allowed) {
        candidates.push_back(make_candidate(file_info, file_info, context, context_media_hint, source_type, path, true));
    }
    return candidates;
}

std::string parse_media_identity_json(const std::string& folder_name, const std::string& file_name) {
    const std::string synthetic_path = folder_name.empty() ? file_name : folder_name + "/" + file_name;
    const auto candidates = parse_path_candidates("local", synthetic_path);
    const ParseInfo file_info = parse_text(file_name, true);
    const std::string raw_title = folder_name + " " + strip_extension(file_name);

    std::string normalized_title;
    bool has_year = file_info.has_year;
    int year = file_info.year;
    bool has_season = file_info.has_season;
    int season = file_info.season;
    bool has_episode = file_info.has_episode;
    int episode = file_info.episode;
    if (!candidates.empty()) {
        const SearchCandidate& candidate = candidates.front();
        normalized_title = candidate.title;
        has_year = candidate.has_year;
        year = candidate.year;
        has_season = file_info.has_season || file_info.has_episode || candidate.has_season;
        season = candidate.has_season ? candidate.season : (file_info.has_season ? file_info.season : 1);
        has_episode = file_info.has_episode || candidate.has_episode;
        episode = candidate.has_episode ? candidate.episode : file_info.episode;
    } else {
        normalized_title = file_info.cleaned_title;
    }

    std::string kind = "Unknown";
    if (has_episode || has_season) {
        kind = "TvEpisode";
    } else if (!normalized_title.empty()) {
        kind = "Movie";
    }

    std::ostringstream json;
    json << "{"
         << "\"raw_title\":" << json_string(raw_title) << ","
         << "\"normalized_title\":" << json_string(normalized_title) << ","
         << "\"year\":" << json_optional_int(has_year, year) << ","
         << "\"season\":" << json_optional_int(has_season, season) << ","
         << "\"episode\":" << json_optional_int(has_episode, episode) << ","
         << "\"kind\":" << json_string(kind)
         << "}";
    return json.str();
}

char* owned_c_string(const std::string& value) {
    char* output = static_cast<char*>(std::malloc(value.size() + 1));
    if (output == nullptr) {
        return nullptr;
    }
    std::memcpy(output, value.c_str(), value.size() + 1);
    return output;
}

}  // namespace

extern "C" char* player_core_cpp_parse_media_path_candidates_json(
    const char* source_type,
    const char* path) {
    return owned_c_string(candidates_json(parse_path_candidates(
        input_string(source_type),
        input_string(path))));
}

extern "C" char* player_core_cpp_parse_media_identity_json(
    const char* folder_name,
    const char* file_name) {
    return owned_c_string(parse_media_identity_json(input_string(folder_name), input_string(file_name)));
}

extern "C" char* player_core_cpp_media_series_title_json(
    const char* source_type,
    const char* path) {
    const auto candidates = parse_path_candidates(input_string(source_type), input_string(path));
    const std::string title = candidates.empty() ? std::string() : candidates.front().title;
    return owned_c_string(json_string(title));
}

extern "C" char* player_core_cpp_set_version_directory_regexes(const char* patterns) {
    return owned_c_string(set_custom_version_directory_regexes(input_string(patterns)));
}

extern "C" void player_core_cpp_free_string(char* value) {
    std::free(value);
}
