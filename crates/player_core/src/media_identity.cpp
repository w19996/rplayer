#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>

// 这个文件集中维护“从路径和文件名推导媒体身份”的规则。
//
// 调用链是：Dart 创建 MediaItem -> Rust FFI 包装入参 -> 调用这里的 C ABI。
// 这里不负责扫描目录、请求 WebDAV、请求 TMDB 或写数据库；它只负责把已经扫描到
// 的本地/WebDAV 路径和文件名解析成搜索提示，例如电视剧搜索名、年份、季、集。
//
// 规则放在 C++ 的目的，是让本地路径和远程路径共用同一套解析逻辑，避免 Dart 和
// Rust 各留一份相似但逐渐漂移的实现。
namespace {

struct ParsedDigits {
    bool has_value = false;
    int value = 0;
    std::size_t consumed = 0;
};

struct SeasonEpisode {
    bool has_season = false;
    int season = 0;
    bool has_episode = false;
    int episode = 0;
};

std::string input_string(const char* value) {
    return value == nullptr ? std::string() : std::string(value);
}

// 这些基础判断刻意只处理 ASCII。
//
// 媒体标题本身可以是中文、日文或其它 UTF-8 字节，这些字节会原样保留；但我们要识别
// 的结构性标记通常是 ASCII，例如路径分隔符、S01E02、年份、1080p、x265 等。
// 只对 ASCII 做大小写和空白处理，可以避免错误拆分多字节标题字符。
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

std::string local_dirname(const std::string& path) {
    const auto index = path.find_last_of("/\\");
    return index == std::string::npos ? std::string() : path.substr(0, index);
}

std::string basename_from_parts(const std::vector<std::string>& parts) {
    return parts.empty() ? std::string() : parts.back();
}

bool starts_with(const std::string& value, const std::string& prefix) {
    return value.size() >= prefix.size() &&
           std::equal(prefix.begin(), prefix.end(), value.begin());
}

// 判断一个目录名是否只是“季目录”。
//
// 例如 ".../Show/Season 1/S01E01.mkv" 里，真正应该拿去搜索 TMDB 的剧名是
// "Show"，不是 "Season 1"。因此遇到 Season 1、S01、Specials、SP 等目录时，
// 需要继续向上取父目录作为电视剧搜索名。
bool looks_like_season_folder_name(const std::string& value) {
    const std::string text = trim(value);
    if (text.empty()) {
        return false;
    }
    const std::string lower = lower_ascii(text);
    if (lower == "special" || lower == "specials" || lower == "sp") {
        return true;
    }
    if (starts_with(lower, "season")) {
        std::string rest = trim(lower.substr(6));
        if (rest.empty()) {
            return false;
        }
        while (rest.size() > 1 && rest.front() == '0') {
            rest.erase(rest.begin());
        }
        return !rest.empty() && rest.size() <= 2 &&
               std::all_of(rest.begin(), rest.end(), [](unsigned char ch) {
                   return std::isdigit(ch) != 0;
               });
    }
    if (lower.front() == 's') {
        std::string rest = trim(lower.substr(1));
        if (rest.empty()) {
            return false;
        }
        while (rest.size() > 1 && rest.front() == '0') {
            rest.erase(rest.begin());
        }
        return !rest.empty() && rest.size() <= 2 &&
               std::all_of(rest.begin(), rest.end(), [](unsigned char ch) {
                   return std::isdigit(ch) != 0;
               });
    }
    return false;
}

// 从本地文件路径推导电视剧搜索名。
//
// Windows 本地路径可能同时出现 '\' 和 '/'，所以这里把两者都当作路径分隔符。
// 如果视频直接在剧集目录下，例如 "D:/TV/Show/01.mkv"，返回 "Show"；
// 如果视频在季目录下，例如 "D:/TV/Show/Season 1/S01E01.mkv"，返回 "Show"。
std::string series_title_from_local_path(const std::string& path) {
    const std::string dir = local_dirname(path);
    const auto dir_parts = split_path(dir, true);
    const std::string folder = basename_from_parts(dir_parts);
    if (looks_like_season_folder_name(folder) && dir_parts.size() >= 2) {
        return dir_parts[dir_parts.size() - 2];
    }
    return folder;
}

// 从远程 WebDAV 路径推导电视剧搜索名。
//
// WebDAV 路径按 URL 语义处理，只把 '/' 当作路径分隔符，反斜杠不作为目录分隔符。
// 这样可以避免把远程文件名里偶然出现的 '\' 误当成目录层级。
std::string series_title_from_remote_path(const std::string& path) {
    const auto parts = split_path(path, false);
    if (parts.size() < 2) {
        return std::string();
    }
    const std::string folder = parts[parts.size() - 2];
    if (looks_like_season_folder_name(folder) && parts.size() >= 3) {
        return parts[parts.size() - 3];
    }
    return folder;
}

// 把发布组风格的文件名切成 token。
//
// 例如 "Show.S01E02.1080p.WEB-DL.mkv" 会按 '.', '_', '-', 括号和空白拆分。
// 非 ASCII 字节不会被改写，因此中文标题会完整保留；后续只会过滤掉年份、季集标记
// 和清晰度/编码等噪声 token。
std::vector<std::string> tokenize(const std::string& input) {
    std::vector<std::string> tokens;
    std::string current;
    for (const char ch : input) {
        const bool separator = ch == '.' || ch == '_' || ch == '-' || ch == '[' ||
                               ch == ']' || ch == '(' || ch == ')' ||
                               ascii_space(static_cast<unsigned char>(ch));
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

// 不使用 std::stoi，而是手写无异常的数字解析。
//
// Android 上 std::stoi 会额外引入 C++ 异常/RTTI 相关符号；如果打包或加载 C++
// runtime 不完整，就会在 dlopen libplayer_core.so 时因为缺符号失败。这里的数字
// 范围非常小，手写解析更可控，也避免把异常机制带进这个热路径。
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

bool parse_year(const std::vector<std::string>& tokens, int& year) {
    for (const auto& token : tokens) {
        int value = 0;
        if (parse_u16_token(token, value) && value >= 1888 && value <= 2100) {
            year = value;
            return true;
        }
    }
    return false;
}

// 解析 S01E02 / S1E2 这类紧凑季集标记。
//
// 这里只吃 1-2 位季号和 1-2 位集号，保持和旧逻辑一致。更复杂的命名规则以后也应
// 扩展在这里，而不是再回到 Dart 或 Rust 里另写一套。
ParsedDigits parse_one_or_two_digits(const std::string& input, std::size_t start) {
    ParsedDigits result;
    std::string digits;
    for (std::size_t index = start; index < input.size() && digits.size() < 2; ++index) {
        const unsigned char ch = static_cast<unsigned char>(input[index]);
        if (std::isdigit(ch) == 0) {
            break;
        }
        digits.push_back(static_cast<char>(ch));
    }
    result.consumed = digits.size();
    if (!digits.empty()) {
        for (const unsigned char ch : digits) {
            result.value = result.value * 10 + static_cast<int>(ch - '0');
        }
        result.has_value = true;
    }
    return result;
}

SeasonEpisode parse_season_episode(const std::string& input) {
    const std::string lower = lower_ascii(input);
    for (std::size_t index = 0; index < lower.size(); ++index) {
        if (lower[index] != 's') {
            continue;
        }
        const std::size_t season_start = index + 1;
        const ParsedDigits season = parse_one_or_two_digits(lower, season_start);
        const std::size_t e_index = season_start + season.consumed;
        if (!season.has_value || e_index >= lower.size() || lower[e_index] != 'e') {
            continue;
        }
        const ParsedDigits episode = parse_one_or_two_digits(lower, e_index + 1);
        return SeasonEpisode{true, season.value, episode.has_value, episode.value};
    }
    return SeasonEpisode{};
}

// 处理“纯数字开头文件名”的剧集推断。
//
// 很多剧集目录里文件名可能只是 "01~4K.mp4"、"2.mkv"。如果父级目录已经提供了剧名，
// 且文件名开头是 1..999 的数字，就按第 1 季对应集数处理。这样可以让没有 SxxExx
// 的文件也能参与 TMDB 季集匹配。
bool infer_episode_from_numeric_basename(const std::string& input, int& episode) {
    std::size_t index = 0;
    while (index < input.size() && ascii_space(static_cast<unsigned char>(input[index]))) {
        ++index;
    }
    std::string digits;
    for (; index < input.size() && digits.size() < 3; ++index) {
        const unsigned char ch = static_cast<unsigned char>(input[index]);
        if (std::isdigit(ch) == 0) {
            break;
        }
        digits.push_back(static_cast<char>(ch));
    }
    if (digits.empty()) {
        return false;
    }
    int value = 0;
    for (const unsigned char ch : digits) {
        value = value * 10 + static_cast<int>(ch - '0');
    }
    if (value < 1 || value > 999) {
        return false;
    }
    episode = value;
    return true;
}

bool is_episode_token(const std::string& token) {
    const std::string lower = lower_ascii(token);
    return starts_with(lower, "s") && lower.find('e') != std::string::npos;
}

// 过滤不应该进入 TMDB 搜索词的发布/编码噪声。
//
// 这些 token 只用于判断文件版本或画质，不是剧名的一部分；如果保留在搜索词里，
// 会降低 TMDB 搜索命中率。
bool is_noise_token(const std::string& token) {
    const std::string lower = lower_ascii(token);
    static const std::vector<std::string> noise = {
        "2160p", "1080p", "720p", "480p", "webrip", "web", "web-dl",
        "bluray", "bdrip", "x264", "x265", "h264", "h265", "hevc", "aac",
        "ddp", "dts", "hdr", "dv", "remux",
    };
    return std::find(noise.begin(), noise.end(), lower) != noise.end();
}

std::string json_escape(const std::string& value) {
    std::ostringstream out;
    for (const unsigned char ch : value) {
        switch (ch) {
            case '"':
                out << "\\\"";
                break;
            case '\\':
                out << "\\\\";
                break;
            case '\b':
                out << "\\b";
                break;
            case '\f':
                out << "\\f";
                break;
            case '\n':
                out << "\\n";
                break;
            case '\r':
                out << "\\r";
                break;
            case '\t':
                out << "\\t";
                break;
            default:
                if (ch < 0x20) {
                    const char* hex = "0123456789abcdef";
                    out << "\\u00" << hex[(ch >> 4) & 0x0F] << hex[ch & 0x0F];
                } else {
                    out << static_cast<char>(ch);
                }
                break;
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

char* owned_c_string(const std::string& value) {
    char* output = static_cast<char*>(std::malloc(value.size() + 1));
    if (output == nullptr) {
        return nullptr;
    }
    std::memcpy(output, value.c_str(), value.size() + 1);
    return output;
}

// 解析 folder + file 得到 MediaIdentity 的 JSON。
//
// 返回 JSON 而不是结构体，是为了让 C ABI 保持简单：Rust 只需要接收字符串，再交给
// serde_json 反序列化或直接传回 Dart。这样避免跨语言传递复杂结构体时遇到布局、
// 内存所有权和 ABI 兼容问题。
std::string parse_media_identity_json(const std::string& folder_name, const std::string& file_name) {
    const std::string basename = strip_extension(file_name);
    const std::string raw_title = folder_name + " " + basename;
    const std::vector<std::string> raw_tokens = tokenize(raw_title);
    int year = 0;
    const bool has_year = parse_year(raw_tokens, year);

    SeasonEpisode parsed = parse_season_episode(raw_title);
    int inferred_episode = 0;
    const bool inferred = !parsed.has_season && !parsed.has_episode &&
                          !trim(folder_name).empty() &&
                          infer_episode_from_numeric_basename(basename, inferred_episode);
    if (inferred) {
        parsed.has_season = true;
        parsed.season = 1;
        parsed.has_episode = true;
        parsed.episode = inferred_episode;
    }

    const std::string title_source = inferred ? folder_name : raw_title;
    std::vector<std::string> normalized_tokens;
    for (const auto& token : tokenize(title_source)) {
        int token_year = 0;
        if (is_noise_token(token) || parse_year({token}, token_year) || is_episode_token(token)) {
            continue;
        }
        normalized_tokens.push_back(token);
    }

    std::ostringstream normalized;
    for (std::size_t index = 0; index < normalized_tokens.size(); ++index) {
        if (index > 0) {
            normalized << ' ';
        }
        normalized << normalized_tokens[index];
    }
    const std::string normalized_title = trim(normalized.str());

    std::string kind = "Unknown";
    if (parsed.has_season || parsed.has_episode) {
        kind = "TvEpisode";
    } else if (!normalized_title.empty()) {
        kind = "Movie";
    }

    std::ostringstream json;
    json << "{"
         << "\"raw_title\":" << json_string(raw_title) << ","
         << "\"normalized_title\":" << json_string(normalized_title) << ","
         << "\"year\":" << json_optional_int(has_year, year) << ","
         << "\"season\":" << json_optional_int(parsed.has_season, parsed.season) << ","
         << "\"episode\":" << json_optional_int(parsed.has_episode, parsed.episode) << ","
         << "\"kind\":" << json_string(kind)
         << "}";
    return json.str();
}

}  // namespace

// Rust 调用的 C ABI：解析媒体身份。
//
// 返回值是 malloc 分配的 UTF-8 JSON 字符串，调用方必须用
// player_core_cpp_free_string 释放，不能用 Rust 或 Dart 自己的 allocator 释放。
extern "C" char* player_core_cpp_parse_media_identity_json(
    const char* folder_name,
    const char* file_name) {
    return owned_c_string(parse_media_identity_json(input_string(folder_name), input_string(file_name)));
}

// Rust 调用的 C ABI：从路径推导电视剧搜索名。
//
// 返回的是 JSON 字符串值，例如 "\"Show\""，而不是裸字符串 "Show"。这样可以
// 复用 player_core 现有 FFI 响应包装和 Dart 侧 jsonDecode 逻辑。
extern "C" char* player_core_cpp_media_series_title_json(
    const char* source_type,
    const char* path) {
    const std::string source = lower_ascii(input_string(source_type));
    const std::string input_path = input_string(path);
    const std::string title = source == "webdav" || source == "remote"
                                  ? series_title_from_remote_path(input_path)
                                  : series_title_from_local_path(input_path);
    return owned_c_string(json_string(title));
}

extern "C" void player_core_cpp_free_string(char* value) {
    std::free(value);
}
