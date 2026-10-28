-- =============================================================================
-- AbysseanRadar.lua : アビセアン (不可視の NM) の追跡アドオン (v0.6.1)
-- =============================================================================
-- 【目的】
-- アビセアンは、ジェイドを持ってヒーリングすると、方角と距離がチャットログに出る。
-- 何度か場所を変えてヒーリングした結果を重ねて、アビセアンの「今いそうな場所」を推定し、
-- 小さな円形のレーダー (北が上) に表示する。
--
-- 【仕組み】
--   - ヒーリングのメッセージ (実データの書式):
--       「灰色のジェイドは、大きく振動し、南の方向の約10Ym先に向かって光を発した。」
--     を読み、打った地点・方角・距離を覚える (radar_math.lua)
--   - 方角は 8 方位 (幅 ±22.5 度) なので 1 回では広い。場所を変えて何回か測ると絞れる
--   - アビセアンは動く (実測で約 1〜1.4 ヤルム/秒) ので、古い測定ほど緩く扱う
--   - 座標は X が東、Y が北 (実データで確認した向き)
--   - 受け取って計算して表示するだけ。ゲームのサーバーへ送る操作・メモリの読み書きは一切しない
--   - 段階 (小・大・強・激 = 小さく・大きく・力強く・激しく振動) ごと、色ごとに別の追跡にして、同時に出す。
--     星の横に段階の漢字を付け、色も変える (小 = 水色、大 = 橙、強 = 赤、激 = 紫)
--   - レーダーはマウスでドラッグして動かせる。ホイールで範囲を変えられる (v0.3.0)
--   - 表示の向きは 2 通り (//ar mode): 自分が向いている方が上 (heading、既定) / 北が上 (north)
--   - 右クリック (レーダーの上) で、表示の向きを切り替える (v0.5.0)
--   - 近づいたらチャットで知らせる (v0.5.0)。既定は 30Ym と 10Ym。sounds/near.wav・sounds/close.wav を置くと、音も鳴る (任意)
--   - 色・透明度・知らせの距離は //ar color / alpha / near / close / notify / sound で変えられる
--   - 地図 (v0.6.0): そのゾーンの地図があれば、レーダーの代わりに、自分を中央に置いた円形の地図 (北が上) を出す。
--     地図の画像は同梱しない。tools/convert_maps.ps1 で、自分で取得した mappy の地図 (GIF) を小さな欠片の PNG にして maps/ に置く。
--     座標の合わせ方は maps/map.ini (mappy の map.ini と同じ。変換スクリプトがコピーする)
--     images には切り抜きが無いので、見える欠片だけを並べ、はみ出す分は輪の形のマスク (images/map_mask.png) で隠す
--   - 印: アビセアン・NM = 赤い星、PH = 青いダイヤ (PH は NMTimer と合わせるときに使う)。標的が動いていそうなら、小さな矢印で向きを示す
--   - 答え合わせ (v0.2.1): アビセアンが姿を現したら (「襲いかかってきた」「砕け散った」)、近くで戦闘中の敵の位置と、
--     最後の推定を比べて、ずれを出す。//ar truth は、ターゲットした敵の位置で同じ比較をする
--
-- 【記録】 data/ping.log : 対象のメッセージを、自分の座標・向き・時刻と一緒に記録 (v0.1.0 から継続)
--
-- 【文字コード】 チャット (incoming text) は Shift-JIS → windower.from_shift_jis で UTF-8 にして使う。
--               レーダーの文字 (libs/texts.lua) は UTF-8
-- =============================================================================

_addon.name     = "AbysseanRadar"
_addon.author   = "hikaruoshino"
_addon.version  = "0.6.1"
_addon.commands = {"abyradar", "ar"}

local config = require("config")
local texts  = require("texts")
local images = require("images")

local radar_math = assert(loadfile(windower.addon_path .. "radar_math.lua"))()

-- -----------------------------------------------------------------------------
-- 設定 (data/settings.xml)
-- -----------------------------------------------------------------------------
local defaults = {}
defaults.pos = {x = 40, y = 250}
defaults.text = {font = "Meiryo", size = 10, alpha = 255}
defaults.bg = {alpha = 170, red = 10, green = 15, blue = 25}
defaults.padding = 6
defaults.flags = {draggable = false}     -- 文字の枠は動かさない (レーダーをドラッグすると、文字の枠もついていく)
defaults.show = true          -- レーダーを出す
defaults.radar_pos = {x = 60, y = 300}  -- レーダーの左上の位置 (ドラッグで動かす)
defaults.mode = "heading"     -- "heading" = 自分が向いている方が上 / "north" = 北が上
defaults.radar_size = 180     -- レーダーの直径 (ピクセル)
defaults.range = 80           -- レーダーの半径が表す距離 (ヤルム)
defaults.speed = 1.5          -- アビセアンが動く最大の速さ (ヤルム/秒)。古い測定の許す範囲に使う
defaults.logging = true       -- data/ping.log に記録する
defaults.map = true          -- 地図を出す (maps/ に、そのゾーンの地図があるとき)
defaults.map_d = 190          -- 地図の円の直径 (ピクセル)。縁の輪は、その外側に、倍率に合わせた太さで付く
defaults.map_zoom = 2.0       -- 地図の拡大 (画像 1 ピクセルを何ピクセルで出すか)。地図の上でホイールを回しても変えられる
defaults.map_alpha = 200      -- 地図の濃さ (0〜255)
defaults.alpha = 255          -- レーダーの背景の濃さ (0〜255)
defaults.notify = true        -- 近づいたらチャットで知らせる
defaults.notify_near = 30     -- 「近づきました」の距離 (ヤルム)
defaults.notify_close = 10    -- 「すぐ近くです」の距離 (ヤルム)
defaults.sound = false        -- 知らせの音 (sounds/near.wav・sounds/close.wav があれば鳴らす)
defaults.color1 = "150,210,255"   -- 段階の色: 小
defaults.color2 = "255,170,60"    -- 大
defaults.color3 = "235,50,50"     -- 強
defaults.color4 = "205,70,235"    -- 激

local settings = config.load(defaults)

local DATA_DIR = windower.addon_path .. "data/"
local LOG_FILE = DATA_DIR .. "ping.log"
local IMG = windower.addon_path .. "images/"

-- この言葉を含む行を、解析できなくても記録する (書式の調べもの用)
local KEYWORDS = {"光を発した", "Ym先", "ビジタント", "発光状況", "砕け散った", "襲いかかってきた"}
local TRACK_KEEP_SEC = 240        -- 最後の測定からこれだけ経つと、追跡をやめる
local MAX_PINGS = 12              -- 追跡ごとに覚える測定の数
local REFRESH_SEC = 0.1

-- -----------------------------------------------------------------------------
-- 小さな道具
-- -----------------------------------------------------------------------------
local function sjis(str)
    if not str then return "" end
    return windower.to_shift_jis and windower.to_shift_jis(str) or str
end

local function chat(text, color)
    windower.add_to_chat(color or 207, sjis(text))
end

local function to_utf8(str)
    if windower.from_shift_jis then return windower.from_shift_jis(str) end
    return str
end

-- 色の制御文字 (0x1E・0x1F とその次の 1 文字) と、そのほかの制御文字を消す
local function clean(str)
    str = str:gsub("[\30\31].", "")
    str = str:gsub("%c", "")
    return str
end

local function color_text(str, r, g, b)
    return string.format("\\cs(%d,%d,%d)%s\\cr", r, g, b, tostring(str or ""))
end

local function matches(text)
    for _, word in ipairs(KEYWORDS) do
        if text:find(word, 1, true) then return true end
    end
    return false
end

local function fmt_num(v)
    if type(v) ~= "number" then return tostring(v) end
    return string.format("%.2f", v)
end

-- -----------------------------------------------------------------------------
-- 状態
-- -----------------------------------------------------------------------------
local tracks = {}            -- 色 → {color, stage, pings = {...}, est = {...}, last_t}
local active = nil           -- 今表示している追跡 (色)
local dir16_seen = false     -- 16 方位の言葉が来たら、すべての方角の幅を狭くする
local logged = 0
local last_est = nil     -- 最後の推定 {x, y, radius, color, t}。追跡を終えても、答え合わせのために残す
local spawn_check_at = nil  -- 姿を現した (襲いかかってきた) あと、近くの敵を調べる時刻
local spawn_attempts = 0    -- 調べた回数 (出現の直後は、戦闘中の印がまだ付かないことがあるので、何回か探し直す)
local SPAWN_RETRY_SEC = 2.5
local SPAWN_MAX_ATTEMPTS = 4
local TRUTH_KEEP_SEC = 600
local recent = {}
local RECENT_MAX = 5
local head_sign = -1             -- 向きの約束: 前向き = (cos h, head_sign * sin h)。mappy と同じ -1 が既定で、走って確かめて直す
local head_votes = {a = 0, b = 0}    -- a = -1 の約束に合う走り、b = +1 の約束に合う走り
local head_checked = false
local unread_told = 0             -- 読めない書式をチャットで知らせた回数 (最大 3 回)
local last_sample = nil

local function now_c() return os.clock() end

local function half_width()
    return dir16_seen and radar_math.HALF_16 or radar_math.HALF_8
end

local function recompute(track)
    local list = {}
    for _, p in ipairs(track.pings) do
        list[#list + 1] = {t = p.t, px = p.px, py = p.py, dist = p.dist, bearing = p.bearing, half = half_width()}
    end
    track.est = radar_math.estimate(list, now_c(), {speed = settings.speed})
end

-- -----------------------------------------------------------------------------
-- 記録 (data/ping.log)
-- -----------------------------------------------------------------------------
local function record(text, mode, extra)
    if not settings.logging then return end
    local info = windower.ffxi.get_info() or {}
    local me = windower.ffxi.get_mob_by_target("me") or {}
    local line = string.format("%s zone=%s mode=%s x=%s y=%s z=%s heading=%s facing=%s%s | %s",
        os.date("%Y-%m-%d %H:%M:%S"), tostring(info.zone), tostring(mode),
        fmt_num(me.x), fmt_num(me.y), fmt_num(me.z), fmt_num(me.heading), fmt_num(me.facing), extra or "", text)
    if windower.create_dir then windower.create_dir(DATA_DIR) end
    local f = io.open(LOG_FILE, "a")
    if f then
        f:write(line .. "\n")
        f:close()
    end
    logged = logged + 1
    recent[#recent + 1] = line
    while #recent > RECENT_MAX do table.remove(recent, 1) end
end

-- -----------------------------------------------------------------------------
-- ヒーリングのメッセージ
-- -----------------------------------------------------------------------------
local function on_ping(parsed, text, mode)
    local me = windower.ffxi.get_mob_by_target("me")
    if not me or not me.x or not me.y then
        record(text, mode, " (自分の座標が取れなかった)")
        return
    end
    if radar_math.DIRECTIONS_16_ONLY[parsed.dir] then dir16_seen = true end
    local key = parsed.color .. "|" .. tostring(parsed.stage)     -- 段階の違う測定は、別の追跡にする (混ぜると位置がずれる)
    local track = tracks[key]
    if not track then
        track = {key = key, color = parsed.color, pings = {}}
        tracks[key] = track
    end
    track.stage = parsed.stage
    track.crescent = parsed.crescent
    track.pings[#track.pings + 1] = {t = now_c(), px = me.x, py = me.y, dist = parsed.dist, bearing = parsed.bearing, dir = parsed.dir}
    while #track.pings > MAX_PINGS do table.remove(track.pings, 1) end
    track.last_t = now_c()
    recompute(track)
    active = key
    local e = track.est
    if e then
        last_est = {x = e.x, y = e.y, radius = e.radius, color = parsed.color, t = now_c()}
        track.snaps = track.snaps or {}
        track.snaps[#track.snaps + 1] = {t = now_c(), x = e.x, y = e.y, r = e.radius}
        while #track.snaps > 10 do table.remove(track.snaps, 1) end
    end
    record(text, mode, e and string.format(" est=(%.1f,%.1f) radius=%.1f n=%d", e.x, e.y, e.radius, e.n) or "")
end

-- 答え合わせ: 実際の敵の位置と、最後の推定を比べる
local function report_truth(mob, how)
    if not last_est or now_c() - last_est.t > TRUTH_KEEP_SEC then
        chat("[AbysseanRadar] 比べる推定がありません (ヒーリングしてから 10 分以内の、最後の推定と比べます)", 167)
        return
    end
    if not mob or not mob.x or not mob.y then return end
    local err = math.sqrt((mob.x - last_est.x) ^ 2 + (mob.y - last_est.y) ^ 2)
    chat(string.format("[AbysseanRadar] 答え合わせ (%s): 実際 X %.0f Y %.0f / 推定 X %.0f Y %.0f ±%.0fYm / ずれ 約 %.0fYm",
        how, mob.x, mob.y, last_est.x, last_est.y, last_est.radius, err), 209)
    record("答え合わせ", "-", string.format(" truth=(%.1f,%.1f) est=(%.1f,%.1f) radius=%.1f err=%.1f who=%s",
        mob.x, mob.y, last_est.x, last_est.y, last_est.radius, err, tostring(mob.name)))
end

-- 姿を現した少しあとに、自分の近くで戦闘中の敵を探して、推定と比べる。
-- 出現の直後は「戦闘中」の印が付かないことがあるので、何回か探し直す (実機で 1.5 秒後には見つからなかったため)。
-- 探す敵: 戦闘中 / 自分をターゲットしている / 自分が先に戦っている (仲間・生きていない敵は除く)
local function check_spawn()
    if not spawn_check_at or now_c() < spawn_check_at then return end
    spawn_check_at = nil
    if not last_est then spawn_attempts = 0 return end
    local me = windower.ffxi.get_mob_by_target("me") or {}
    local best, best_d
    for _, mob in pairs(windower.ffxi.get_mob_array() or {}) do
        if type(mob) == "table" and mob.is_npc ~= false and mob.x and mob.y and (mob.hpp or 0) > 0
            and not mob.in_party and not mob.in_alliance and (mob.distance or 0) <= 3600 then
            local aggressive = mob.status == 1
                or (me.index and mob.target_index == me.index)
                or (me.id and mob.claim_id == me.id)
            if aggressive then
                local d = (mob.x - last_est.x) ^ 2 + (mob.y - last_est.y) ^ 2
                if not best_d or d < best_d then best, best_d = mob, d end
            end
        end
    end
    if best then
        spawn_attempts = 0
        report_truth(best, "出現した敵")
        return
    end
    spawn_attempts = spawn_attempts + 1
    if spawn_attempts < SPAWN_MAX_ATTEMPTS then
        spawn_check_at = now_c() + SPAWN_RETRY_SEC
    else
        spawn_attempts = 0
        chat("[AbysseanRadar] 近くに戦闘中の敵が見つかりませんでした。アビセアンをターゲットして //ar truth を打つと答え合わせできます", 167)
    end
end

windower.register_event("incoming text", function(original, modified, original_mode)
    if not original then return end
    local ok, err = pcall(function()
        local text = clean(to_utf8(original))
        if text == "" then return end
        if text:find("ジェイドは砕け散った", 1, true) then
            -- 姿を現した。第3段階以上のジェイドだけが砕ける。その色の第3段階以上の追跡を終える
            -- (その推定が、答え合わせの比べる相手になる)
            for key, track in pairs(tracks) do
                if text:find(track.color, 1, true) and ((track.stage or 0) >= 3 or (track.stage or 0) == 0) then
                    if track.est then
                        last_est = {x = track.est.x, y = track.est.y, radius = track.est.radius, color = track.color, t = now_c()}
                    end
                    tracks[key] = nil
                end
            end
            if active and not tracks[active] then active = nil end
            spawn_check_at = now_c() + 1.5
            spawn_attempts = 0
            record(text, original_mode)
            return
        end
        if text:find("襲いかかってきた", 1, true) then
            spawn_check_at = now_c() + 1.5
            spawn_attempts = 0
            record(text, original_mode)
            return
        end
        if not matches(text) then return end
        local parsed = radar_math.parse(text)
        if parsed then
            on_ping(parsed, text, original_mode)
        else
            record(text, original_mode, " (読めない書式)")
            if text:find("Ym先", 1, true) and unread_told < 3 then
                unread_told = unread_told + 1
                chat("[AbysseanRadar] 読めない書式のジェイドのメッセージがありました (data/ping.log に記録しました)。教えてもらえれば対応します: " .. text:sub(1, 60), 167)
            end
        end
    end)
    if not ok then
        chat("[AbysseanRadar] 解析でエラー: " .. tostring(err), 123)
    end
end)

-- -----------------------------------------------------------------------------
-- 表示: 文字の枠 + 円形のレーダー
-- -----------------------------------------------------------------------------
local hud = texts.new("", settings)

local function new_image(file, w, h)
    local img = images.new({
        pos = {x = 0, y = 0}, visible = false, draggable = false,
        color = {alpha = 255, red = 255, green = 255, blue = 255},
        size = {width = w, height = h},
        texture = {path = IMG .. file, fit = false},
        repeatable = {x = 1, y = 1},
    })
    return img
end

local check_near                -- 前方宣言 (下で定義)
local MAP_DIR = windower.addon_path .. "maps/"
local map_state = {zone = nil, dir = nil, cal = nil}   -- 今のゾーンの地図: 欠片のフォルダー・座標の合わせ方 {xs, xo, ys, yo}
local MAP_TILE = 8               -- 地図の欠片の一辺 (地図の画像は 512 → 64 × 64 枚)
local MAP_N = 64                 -- 欠片の数 (一辺)
local MAP_GRID = 16              -- 欠片を置く枠の数 (一辺)。見える欠片は、この数以内にする
-- 縁のマスク (images/map_mask_1〜6.png): 輪の幅 ÷ 円の半径。円に掛かる欠片は、輪にはみ出す (最大で欠片の対角 = 一辺 × 1.42 × 倍率)。
-- 欠けが出ないように、倍率に合わせて、幅が足りる最も細い輪を使う
local MAP_MASKS = {20 / 256, 32 / 256, 44 / 256, 60 / 256, 86 / 256, 128 / 256}
local map_mask_file = nil         -- 今の縁の画像
local map_sig = nil              -- 前回描いたときの欠片の状態 (変わらなければ、欠片を置き直さない)
local map_tile_key = {}          -- 枠 → 今入っている欠片の番号
local SLOTS = 3                -- 同時に出す追跡の数 (段階・色が違うものが重なるため)
local STAGE_MARK = {[0] = "?", "小", "大", "強", "激"}                 -- 小さく・大きく・力強く・激しく
local STAGE_COLOR = {[0] = {255, 255, 255}, {150, 210, 255}, {255, 170, 60}, {235, 50, 50}, {205, 70, 235}}
local STAGE_DEFAULT_COLOR = {"150,210,255", "255,170,60", "235,50,50", "205,70,235"}
local function parse_color(str)
    local r, g, b = tostring(str or ""):match("^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$")
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if r and g and b and r <= 255 and g <= 255 and b <= 255 then return {r, g, b} end
end
for i = 1, 4 do STAGE_COLOR[i] = parse_color(settings["color" .. i]) or STAGE_COLOR[i] end
local STAGE_SIZE = {[0] = 26, 22, 28, 32, 34}

-- 地図の座標の合わせ方を、maps/map.ini から読む。行の書式 (mappy の map.ini と同じ):
--   fd_0=0.1,129,-0.1,131,...   (ゾーン番号を 16 進数 2 桁以上で、_ のあとは地図の番号)
--   画像の位置 (256 を一辺とした座標) = オフセット + 倍率 × ゲームの座標。画像は 512 なので、ピクセルはその 2 倍
-- 欠片は maps/<ゾーン>_0/<行>_<列>.png (行・列は 00〜63)
local function load_map(zone)
    map_state.zone, map_state.dir, map_state.cal = zone, nil, nil
    map_sig, map_tile_key = nil, {}
    if not zone or zone <= 0 then return end
    local key = string.format("%02x_0", zone)
    local dir = MAP_DIR .. key .. "/"
    if not (windower.file_exists and windower.file_exists(dir .. "00_00.png")) then return end
    local f = io.open(MAP_DIR .. "map.ini", "r")
    if not f then return end
    local cal
    for line in f:lines() do
        local value = line:match("^%s*" .. key .. "%s*=%s*([^;\r\n]+)")
        if value then
            local xs, xo, ys, yo = value:match("^%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)")
            xs, xo, ys, yo = tonumber(xs), tonumber(xo), tonumber(ys), tonumber(yo)
            if xs and xo and ys and yo and xs ~= 0 and ys ~= 0 then cal = {xs, xo, ys, yo} end
            break
        end
    end
    f:close()
    if cal then map_state.dir, map_state.cal = dir, cal end
end

local radar = {
    bg = new_image("radar_bg.png", 180, 180),
    north = new_image("north.png", 20, 20),
    me = new_image("dot_me.png", 12, 12),
    me_arrow = new_image("arrow_00.png", 26, 26),
    stars = {}, rings = {}, moves = {}, labels = {},
    hist = {},
}
for i = 1, SLOTS do
    radar.stars[i] = new_image("star_white.png", 32, 32)
    radar.rings[i] = new_image("ring_white.png", 32, 32)
    radar.moves[i] = new_image("arrow_00.png", 26, 26)
    radar.labels[i] = texts.new("", {
        pos = {x = 0, y = 0}, bg = {alpha = 0, visible = false}, flags = {draggable = false}, padding = 0,
        text = {font = "Meiryo", size = 11, alpha = 255, red = 255, green = 255, blue = 255,
                stroke = {width = 2, alpha = 255, red = 0, green = 0, blue = 0}},
    })
end
for i = 1, MAX_PINGS do radar.hist[i] = new_image("dot_hist.png", 10, 10) end
-- 地図の部品 (レーダーのあとに作る。作った順に重なる: 暗い円盤 → 欠片 → 縁のマスク → 印)
radar.map_disc = new_image("map_disc.png", 200, 200)
radar.map_tiles = {}
for i = 1, MAP_GRID * MAP_GRID do radar.map_tiles[i] = new_image("map_blank.png", MAP_TILE, MAP_TILE) end
radar.map_mask = new_image("map_mask_1.png", 300, 300)
radar.map_me = new_image("dot_me.png", 12, 12)
radar.map_me_arrow = new_image("arrow_00.png", 26, 26)
radar.map_stars, radar.map_rings = {}, {}
for i = 1, SLOTS do
    radar.map_stars[i] = new_image("star_white.png", 32, 32)
    radar.map_rings[i] = new_image("ring_white.png", 32, 32)
end
local radar_visible = false      -- レーダーを今出しているか (マウスの判定に使う)

local map_shown = false          -- 地図の部品を出しているか (出していなければ、隠す呼び出しを省く)
local ui_clean = false           -- 文字・レーダー・地図をすべて隠した状態か (追跡が無い間、毎フレーム隠し直さないため)

local function hide_map()
    map_sig = nil
    if not map_shown then return end
    map_shown = false
    radar.map_disc:hide(); radar.map_mask:hide(); radar.map_me:hide(); radar.map_me_arrow:hide()
    for _, tile in ipairs(radar.map_tiles) do tile:hide() end
    for i = 1, SLOTS do radar.map_stars[i]:hide(); radar.map_rings[i]:hide() end
end

local function map_active()
    return settings.map and map_state.dir ~= nil and map_state.cal ~= nil
end

-- 地図の形: 円の直径・倍率・縁の太さ・中心。中心は、レーダーの中心と同じ (切り替えても動かない)
local function map_geom()
    local d = math.max(120, math.min(400, tonumber(settings.map_d) or 190))
    local r = d / 2
    local zmin = math.max(1, d / ((MAP_GRID - 1) * MAP_TILE))                              -- 見える欠片が枠の数に収まる倍率
    local zmax = math.max(zmin, r * MAP_MASKS[#MAP_MASKS] / (MAP_TILE * 1.42))             -- 最も太い輪で隠せる倍率
    local z = math.max(zmin, math.min(zmax, tonumber(settings.map_zoom) or 2))
    local need = MAP_TILE * 1.42 * z / r
    local level = #MAP_MASKS
    for i, w in ipairs(MAP_MASKS) do
        if w >= need then level = i break end
    end
    local outer = d * (1 + MAP_MASKS[level])
    local half = settings.radar_size / 2
    return {d = d, r = r, z = z, zmin = zmin, zmax = zmax, level = level, outer = outer,
            cx = settings.radar_pos.x + half, cy = settings.radar_pos.y + half}
end

local function hide_radar_parts()
    radar.bg:hide(); radar.north:hide(); radar.me:hide(); radar.me_arrow:hide()
    for i = 1, SLOTS do
        radar.stars[i]:hide(); radar.rings[i]:hide(); radar.moves[i]:hide(); radar.labels[i]:hide()
    end
    for _, h in ipairs(radar.hist) do h:hide() end
end

local function hide_radar()
    radar_visible = false
    ui_clean = true
    hide_map()
    hud:hide()
    hide_radar_parts()
end

local function place(img, cx, cy, w, h)
    img:size(w, h)
    img:pos(cx - w / 2, cy - h / 2)
    img:show()
end

-- 矢印の画像 (0〜15) を選んで置く。色は tint で付ける
local arrow_state = {}      -- 矢印の画像 → 今の番号 (images のオブジェクトに項目を足すと、表示の更新が走ってしまうので別の表に覚える)
local function place_arrow(img, index, cx, cy, r, g, b)
    if arrow_state[img] ~= index then
        arrow_state[img] = index
        img:path(IMG .. string.format("arrow_%02d.png", index))
    end
    img:color(r, g, b)
    place(img, cx, cy, 26, 26)
end

-- 画面のずれ (右, 上) → 画像上の位置 (上は y が小さい)
local function view_offset(dx, dy, me, scale)
    local r, u = radar_math.rotate_to_view(dx, dy, settings.mode, me.heading, head_sign)
    return r * scale, -u * scale, r, u
end

-- 走っているときの進行方向と、向き (heading) を比べて、向きの約束 (head_sign) が合っているかを確かめる
local function calibrate(me, now)
    if head_checked or not me.heading then return end
    if not last_sample or now - last_sample.t < 0.4 then
        if not last_sample then last_sample = {t = now, x = me.x, y = me.y} end
        return
    end
    local dx, dy = me.x - last_sample.x, me.y - last_sample.y
    local dt = now - last_sample.t
    last_sample = {t = now, x = me.x, y = me.y}
    if math.sqrt(dx * dx + dy * dy) / dt < 3 then return end      -- 走っているときだけ (止まっていたり、ゆっくりは除く)
    local move = math.atan2(dy, dx)                                -- 進行方向 (東 = 0、反時計回り)
    local function off(a, b)
        local d = (a - b) % (2 * math.pi)
        if d > math.pi then d = d - 2 * math.pi end
        return math.abs(d)
    end
    if off(move, -me.heading) < 0.5 and off(move, me.heading) >= 0.5 then head_votes.a = head_votes.a + 1
    elseif off(move, me.heading) < 0.5 and off(move, -me.heading) >= 0.5 then head_votes.b = head_votes.b + 1 end
    if head_votes.a + head_votes.b >= 12 then
        head_checked = true
        if head_votes.b > head_votes.a * 2 then
            head_sign = 1
            chat("[AbysseanRadar] 走った向きとキャラの向きを比べたところ、向きが逆に読めていたので、自動で直しました。")
        elseif head_votes.a >= head_votes.b then
            record("向きの約束を確認", "-", string.format(" head_sign=-1 votes=%d/%d", head_votes.a, head_votes.b))
        end
    end
end

local MODE_LABEL = {heading = "自分の向きが上", north = "北が上"}

-- 表示する追跡の並び: 段階の大きい順 (強い NM が先)、同じ段階なら新しい測定が先
local function sorted_tracks(now)
    local list = {}
    for key, track in pairs(tracks) do
        if now - track.last_t > TRACK_KEEP_SEC then
            tracks[key] = nil
        else
            list[#list + 1] = track
        end
    end
    table.sort(list, function(x, y)
        if (x.stage or 0) ~= (y.stage or 0) then return (x.stage or 0) > (y.stage or 0) end
        return x.last_t > y.last_t
    end)
    return list
end

local function draw_track(i, track, me, scale, cx, cy, half, size)
    local star, ring, move, label = radar.stars[i], radar.rings[i], radar.moves[i], radar.labels[i]
    local e = track.est
    if not e then star:hide(); ring:hide(); move:hide(); label:hide() return end
    local col = STAGE_COLOR[track.stage or 0] or STAGE_COLOR[0]
    local sz = STAGE_SIZE[track.stage or 0] or 26
    local sx, sy = view_offset(e.x - me.x, e.y - me.y, me, scale)
    local r = math.sqrt(sx * sx + sy * sy)
    local clamped = r > half - 12
    if clamped then sx, sy = sx / r * (half - 12), sy / r * (half - 12) end
    -- 確からしさの輪 (範囲外のときは出さない)
    if not clamped then
        local d = math.max(12, math.min(size, 2 * e.radius * scale))
        ring:color(col[1], col[2], col[3])
        place(ring, cx + sx, cy + sy, d, d)
    else
        ring:hide()
    end
    star:color(col[1], col[2], col[3])
    star:alpha(clamped and 150 or 255)
    place(star, cx + sx, cy + sy, sz, sz)
    -- 段階の文字 (小・大・強・激) を、星の右上に
    label:text(color_text(STAGE_MARK[track.stage or 0] or "?", col[1], col[2], col[3]))
    label:pos(cx + sx + sz / 2 - 2, cy + sy - sz / 2 - 6)
    label:show()
    -- 動きの矢印: 標的が動いていそうなときだけ、星の先に小さく出す
    local velocity = track.snaps and radar_math.velocity(track.snaps) or nil
    if velocity and not clamped then
        local _, _, vr, vu = view_offset(velocity.vx, velocity.vy, me, 1)
        local len = math.sqrt(vr * vr + vu * vu)
        if len > 0 then
            place_arrow(move, radar_math.arrow_index(vr, vu), cx + sx + vr / len * (sz / 2 + 14), cy + sy - vu / len * (sz / 2 + 14), col[1], col[2], col[3])
        end
    else
        move:hide()
    end
    return velocity
end

-- 近づいたときの知らせ。段階 (距離) ごとに 1 回だけ。離れる (距離の 1.5 倍) と、また知らせる
local function play_alert(name)
    if not settings.sound or not windower.file_exists then return end
    local path = windower.addon_path .. "sounds/" .. name .. ".wav"
    if not windower.file_exists(path) then path = windower.addon_path .. "sounds/near.wav" end
    if windower.file_exists(path) then windower.play_sound(path) end
end

check_near = function(list, me, now)
    if not settings.notify and not settings.sound then return end
    local near, close = tonumber(settings.notify_near) or 30, tonumber(settings.notify_close) or 10
    for _, track in ipairs(list) do
        local e = track.est
        if e then
            local name, arrow, dist = radar_math.compass(e.x - me.x, e.y - me.y)
            local level = track.near_level or 0
            if dist > near * 1.5 then
                level = 0
            elseif dist > close * 1.5 and level > 1 then
                level = 1
            end
            local mark = "★" .. (STAGE_MARK[track.stage or 0] or "?") .. " " .. track.color
            if dist <= close and level < 2 then
                level = 2
                if settings.notify then
                    chat(string.format("[AbysseanRadar] %s: すぐ近くです！ %s %s 約 %.0fYm (±%.0fYm)", mark, arrow, name, dist, e.radius), 204)
                end
                play_alert("close")
            elseif dist <= near and level < 1 then
                level = 1
                if settings.notify then
                    chat(string.format("[AbysseanRadar] %s: 近づきました。%s %s 約 %.0fYm (±%.0fYm)", mark, arrow, name, dist, e.radius), 209)
                end
                play_alert("near")
            end
            track.near_level = level
        end
    end
end

-- 地図: 自分を中央に置いた円形の地図 (北が上)。ゲームの座標を、地図のピクセルに変えて重ねる
local function round(v) return math.floor(v + 0.5) end

local function draw_map(list, me, g)
    local cal = map_state.cal
    if not map_active() then hide_map() return end
    map_shown = true
    local d, r, z, cx, cy = g.d, g.r, g.z, g.cx, g.cy
    local alpha = math.max(0, math.min(255, tonumber(settings.map_alpha) or 200))
    local ppx = 2 * (cal[2] + cal[1] * me.x)          -- 自分の位置 (512 の画像のピクセル)
    local ppy = 2 * (cal[4] + cal[3] * me.y)

    -- 欠片は、自分が 1 ピクセル以上動いたときなど、見た目が変わるときだけ置き直す
    local sig = table.concat({round(cx), round(cy), d, z, g.level, alpha, math.floor(ppx * z), math.floor(ppy * z), map_state.dir}, "|")
    if sig ~= map_sig then
        map_sig = sig
        radar.map_disc:size(d, d); radar.map_disc:pos(cx - r, cy - r)
        radar.map_disc:alpha(math.floor(alpha * 0.7)); radar.map_disc:show()
        local half = r / z                                  -- 画像のピクセルで見たときの半径
        local c0 = math.max(0, math.floor((ppx - half) / MAP_TILE))
        local c1 = math.min(MAP_N - 1, math.floor((ppx + half) / MAP_TILE))
        local r0 = math.max(0, math.floor((ppy - half) / MAP_TILE))
        local r1 = math.min(MAP_N - 1, math.floor((ppy + half) / MAP_TILE))
        local used = {}
        for row = r0, r1 do
            for col = c0, c1 do
                local x0 = round(cx + (col * MAP_TILE - ppx) * z)
                local x1 = round(cx + ((col + 1) * MAP_TILE - ppx) * z)
                local y0 = round(cy + (row * MAP_TILE - ppy) * z)
                local y1 = round(cy + ((row + 1) * MAP_TILE - ppy) * z)
                -- 円に掛かる欠片を全部出す (円から最も近い点までの距離が半径より小さい)。はみ出しは輪が隠す
                local nx = math.max(x0 - cx, 0, cx - x1)
                local ny = math.max(y0 - cy, 0, cy - y1)
                if nx * nx + ny * ny < r * r then
                    local slot = (row % MAP_GRID) * MAP_GRID + (col % MAP_GRID) + 1
                    local tile = radar.map_tiles[slot]
                    local key = row * 100 + col
                    if map_tile_key[slot] ~= key then
                        tile:path(string.format("%s%02d_%02d.png", map_state.dir, row, col))
                        map_tile_key[slot] = key
                    end
                    tile:pos(x0, y0); tile:size(x1 - x0, y1 - y0); tile:alpha(alpha); tile:show()
                    used[slot] = true
                end
            end
        end
        for slot, tile in ipairs(radar.map_tiles) do
            if not used[slot] then tile:hide() end
        end
        -- 縁のマスク: 倍率に合う太さの輪の画像で、はみ出した欠片を隠す
        local mask_file = IMG .. "map_mask_" .. g.level .. ".png"
        if map_mask_file ~= mask_file then
            radar.map_mask:path(mask_file)
            map_mask_file = mask_file
        end
        local m = g.outer
        radar.map_mask:size(m, m); radar.map_mask:pos(cx - m / 2, cy - m / 2); radar.map_mask:alpha(255); radar.map_mask:show()
    end

    -- 印は毎回置く。位置は、自分からのずれ (ゲームの座標) を、地図のピクセルに変える
    place(radar.map_me, cx, cy, 12, 12)
    local fx, fy = radar_math.forward(me.heading or 0, head_sign)
    place_arrow(radar.map_me_arrow, radar_math.arrow_index(fx, fy), cx + fx * 17, cy - fy * 17, 90, 230, 130)
    for i = 1, SLOTS do
        local track = list[i]
        local e = track and track.est
        if e then
            local col = STAGE_COLOR[track.stage or 0] or STAGE_COLOR[0]
            local sx = 2 * cal[1] * (e.x - me.x) * z
            local sy = 2 * cal[3] * (e.y - me.y) * z
            local dist = math.sqrt(sx * sx + sy * sy)
            local clamped = dist > r - 10
            if clamped then sx, sy = sx / dist * (r - 10), sy / dist * (r - 10) end
            local sz = math.max(18, (STAGE_SIZE[track.stage or 0] or 26) * 0.85)
            local ring = math.max(14, 2 * e.radius * 2 * math.abs(cal[1]) * z)    -- いそうな範囲 (地図のピクセル)
            if not clamped then
                radar.map_rings[i]:color(col[1], col[2], col[3])
                place(radar.map_rings[i], cx + sx, cy + sy, ring, ring)
            else
                radar.map_rings[i]:hide()
            end
            radar.map_stars[i]:color(col[1], col[2], col[3])
            radar.map_stars[i]:alpha(clamped and 150 or 255)
            place(radar.map_stars[i], cx + sx, cy + sy, sz, sz)
            -- 段階の文字 (小・大・強・激) を、星の右上に
            radar.labels[i]:text(color_text(STAGE_MARK[track.stage or 0] or "?", col[1], col[2], col[3]))
            radar.labels[i]:pos(cx + sx + sz / 2 - 2, cy + sy - sz / 2 - 6)
            radar.labels[i]:show()
            -- 動きの矢印 (北が上の地図なので、世界の向きのまま)
            local velocity = track.snaps and radar_math.velocity(track.snaps) or nil
            local len = velocity and math.sqrt(velocity.vx ^ 2 + velocity.vy ^ 2) or 0
            if len > 0 and not clamped then
                place_arrow(radar.moves[i], radar_math.arrow_index(velocity.vx, velocity.vy),
                    cx + sx + velocity.vx / len * (sz / 2 + 14), cy + sy - velocity.vy / len * (sz / 2 + 14), col[1], col[2], col[3])
            else
                radar.moves[i]:hide()
            end
        else
            radar.map_rings[i]:hide(); radar.map_stars[i]:hide(); radar.labels[i]:hide(); radar.moves[i]:hide()
        end
    end
end

local function refresh()
    local now = now_c()
    local me = windower.ffxi.get_mob_by_target("me")
    if me and me.x then calibrate(me, now) end
    local list = settings.show and sorted_tracks(now) or {}
    if active and not tracks[active] then active = nil end
    if #list == 0 or not me or not me.x then
        if not ui_clean then hide_radar() end       -- 隠し終えていれば、何もしない (追跡が無い間は、これが毎フレーム通る)
        return
    end
    local primary = (active and tracks[active]) or list[1]

    -- 文字の枠: 今の追跡 (一番新しい測定) は詳しく、ほかは 1 行で
    local use_map = map_active()
    local g = use_map and map_geom() or nil
    local view = use_map and string.format("地図 (北が上) 倍率 %.2f", g.z)
        or string.format("%s / 範囲 %dYm", MODE_LABEL[settings.mode] or settings.mode, settings.range)
    local lines = {color_text("AbysseanRadar", 255, 255, 255) .. color_text(string.format("  表示: %s (右クリックで切替・ホイールで拡大縮小)", view), 150, 150, 150)}
    local function describe(track, detailed)
        local e = track.est
        local col = STAGE_COLOR[track.stage or 0] or STAGE_COLOR[0]
        local stage = track.stage and track.stage > 0 and string.format(" 第%d段階", track.stage) or ""
        local mark = color_text("★" .. (STAGE_MARK[track.stage or 0] or "?"), col[1], col[2], col[3])
        local velocity = track.snaps and radar_math.velocity(track.snaps) or nil
        local last = track.pings[#track.pings]
        local age = now - track.last_t
        if not detailed then
            if e then
                local name, arrow, dist = radar_math.compass(e.x - me.x, e.y - me.y)
                lines[#lines + 1] = string.format("%s %s%s: %s %s 約 %.0fYm ±%.0fYm (%d秒前)", mark, track.color, stage, arrow, name, dist, e.radius, age)
            end
            return
        end
        lines[#lines + 1] = mark .. " " .. track.color .. stage .. string.format(" (%d回測定)", #track.pings)
        if e then
            local name, arrow, dist = radar_math.compass(e.x - me.x, e.y - me.y)
            lines[#lines + 1] = string.format("推定: X %.0f Y %.0f  (誤差 ±%.0fYm = %s)", e.x, e.y, e.radius, radar_math.quality(e.radius))
            lines[#lines + 1] = color_text(string.format("%s %s 約 %.0fYm", arrow, name, dist), 255, 220, 100)
            if velocity then
                lines[#lines + 1] = string.format("動き: %sへ 約 %.1fYm/秒", (radar_math.compass(velocity.vx, velocity.vy)), velocity.speed)
            end
        end
        lines[#lines + 1] = string.format("最終測定 %d 秒前 (%s %dYm)", age, last.dir, last.dist)
    end
    describe(primary, true)
    for _, track in ipairs(list) do
        if track ~= primary then describe(track, false) end
    end
    hud:text(table.concat(lines, "\n"))

    -- レーダー (または地図): 位置はドラッグで決める。文字の枠は、そのすぐ下
    local rx, ry = settings.radar_pos.x, settings.radar_pos.y
    local size = use_map and g.outer or settings.radar_size
    if use_map then
        hud:pos(g.cx - size / 2, g.cy + size / 2 + 4)
    else
        hud:pos(rx, ry + size + 4)
    end
    hud:show()
    radar_visible = true
    ui_clean = false
    check_near(list, me, now)
    if use_map then
        hide_radar_parts()
        draw_map(list, me, g)
        return
    end
    hide_map()

    local half = size / 2
    local scale = half / settings.range
    local cx, cy = rx + half, ry + half
    radar.bg:size(size, size)
    radar.bg:pos(rx, ry)
    radar.bg:alpha(math.max(0, math.min(255, tonumber(settings.alpha) or 255)))
    radar.bg:show()

    -- 北の印: 北が上なら真上。向き固定のときは、北の方角の縁の上
    local _, _, nr, nu = view_offset(0, 1, me, 1)
    place(radar.north, cx + nr * (half - 10), cy - nu * (half - 10), 20, 20)

    -- 自分: 緑の点と、向いている方向の矢印
    place(radar.me, cx, cy, 12, 12)
    local fx, fy = radar_math.forward(me.heading or 0, head_sign)
    local _, _, fr, fu = view_offset(fx, fy, me, 1)
    place_arrow(radar.me_arrow, radar_math.arrow_index(fr, fu), cx + fr * 17, cy - fu * 17, 90, 230, 130)

    -- 過去の測定の 1 点ずつの見込み (小さな黄色い点。今の追跡だけ。古いほど薄い)
    for i, h in ipairs(radar.hist) do
        local p = primary.pings[i]
        if p then
            local tx, ty = radar_math.point(p.px, p.py, p.dist, p.bearing)
            local sx, sy = view_offset(tx - me.x, ty - me.y, me, scale)
            local r = math.sqrt(sx * sx + sy * sy)
            if r > half - 5 then sx, sy = sx / r * (half - 5), sy / r * (half - 5) end
            h:alpha(math.max(60, 255 - math.floor((now - p.t))))
            place(h, cx + sx, cy + sy, 10, 10)
        else
            h:hide()
        end
    end

    for i = 1, SLOTS do
        local track = list[i]
        if track then
            draw_track(i, track, me, scale, cx, cy, half, size)
        else
            radar.stars[i]:hide(); radar.rings[i]:hide(); radar.moves[i]:hide(); radar.labels[i]:hide()
        end
    end
end

-- マウス: レーダーをドラッグして動かす / ホイールで範囲を変える (レーダーの上のクリックはゲームに渡さない)
-- 値は Windower の wiki (events/Events) で確認: 左押す 1・離す 2、右押す 4・離す 5、ホイール 10
local MOUSE_MOVE, MOUSE_LEFT_DOWN, MOUSE_LEFT_UP, MOUSE_RIGHT_DOWN, MOUSE_RIGHT_UP, MOUSE_WHEEL = 0, 1, 2, 4, 5, 10
local drag = nil
local right_held = false
do
    local info = windower.ffxi.get_info and windower.ffxi.get_info()
    if info and info.zone then load_map(info.zone) end
end
local next_refresh = 0

local function in_radar(x, y)
    if not radar_visible then return false end
    local half = settings.radar_size / 2
    local cx, cy = settings.radar_pos.x + half, settings.radar_pos.y + half
    if map_active() then half = map_geom().outer / 2 end
    return (x - cx) ^ 2 + (y - cy) ^ 2 <= half ^ 2
end

windower.register_event("mouse", function(mtype, x, y, delta, blocked)
    local ok, result = pcall(function()
        if blocked then return end
        if mtype == MOUSE_LEFT_DOWN and in_radar(x, y) then
            drag = {x - settings.radar_pos.x, y - settings.radar_pos.y}
            return true
        elseif mtype == MOUSE_MOVE and drag then
            settings.radar_pos.x, settings.radar_pos.y = x - drag[1], y - drag[2]
            next_refresh = 0                       -- すぐ描き直す
            return true
        elseif mtype == MOUSE_LEFT_UP and drag then
            drag = nil
            config.save(settings)
            return true
        elseif mtype == MOUSE_RIGHT_DOWN and in_radar(x, y) then
            right_held = true
            -- 表示を切り替える: 自分の向きが上 → 北が上 → 地図 (そのゾーンの地図があるとき) → ...
            if map_active() then
                settings.map = false
                settings.mode = "heading"
            elseif settings.mode == "heading" then
                settings.mode = "north"
            elseif map_state.dir and map_state.cal then
                settings.map = true
            else
                settings.mode = "heading"
            end
            config.save(settings)
            next_refresh = 0
            chat(string.format("[AbysseanRadar] 表示: %s", map_active() and "地図 (北が上・自分が中央)" or MODE_LABEL[settings.mode]))
            return true
        elseif mtype == MOUSE_RIGHT_UP and right_held then
            right_held = false
            return true
        elseif mtype == MOUSE_WHEEL and in_radar(x, y) and map_active() then
            local step = (tonumber(delta) or 0) > 0 and 0.25 or -0.25          -- 上へ回すと地図が拡大する
            local g = map_geom()
            settings.map_zoom = math.max(g.zmin, math.min(g.zmax, g.z + step))
            config.save(settings)
            next_refresh = 0
            return true
        elseif mtype == MOUSE_WHEEL and in_radar(x, y) then
            local step = (tonumber(delta) or 0) > 0 and -10 or 10          -- 上へ回すと拡大 (範囲を狭める)
            settings.range = math.max(10, math.min(300, settings.range + step))
            config.save(settings)
            next_refresh = 0
            return true
        end
    end)
    if ok then return result end
    drag, right_held = nil, false
end)

windower.register_event("prerender", function()
    local t = os.clock()
    if t < next_refresh then return end
    next_refresh = t + REFRESH_SEC
    local ok, err = pcall(function()
        refresh()
        check_spawn()
    end)
    if not ok then
        next_refresh = t + 5
        chat("[AbysseanRadar] 表示エラー: " .. tostring(err), 123)
    end
end)

-- -----------------------------------------------------------------------------
-- ライフサイクル
-- -----------------------------------------------------------------------------
windower.register_event("zone change", function(new_id)
    load_map(tonumber(new_id))
    tracks, active = {}, nil
    spawn_check_at = nil
    hide_radar()
end)

windower.register_event("logout", function()
    tracks, active = {}, nil
    hide_radar()
    config.save(settings)
end)

windower.register_event("unload", function()
    config.save(settings)
    hide_radar()
    hud:destroy()
    for _, name in ipairs({"bg", "north", "me", "me_arrow", "map_disc", "map_mask", "map_me", "map_me_arrow"}) do radar[name]:destroy() end
    for _, tile in ipairs(radar.map_tiles) do tile:destroy() end
    for i = 1, SLOTS do
        radar.map_stars[i]:destroy(); radar.map_rings[i]:destroy()
        radar.stars[i]:destroy(); radar.rings[i]:destroy(); radar.moves[i]:destroy(); radar.labels[i]:destroy()
    end
    for _, h in ipairs(radar.hist) do h:destroy() end
end)

-- -----------------------------------------------------------------------------
-- コマンド (//ar または //abyradar)
-- -----------------------------------------------------------------------------
local function on_off(arg, current)
    if arg == "on" then return true end
    if arg == "off" then return false end
    return not current
end

windower.register_event("addon command", function(cmd, ...)
    local args = {...}
    cmd = cmd and cmd:lower() or "help"
    local ok, err = pcall(function()
        if cmd == "hud" or cmd == "show" then
            settings.show = on_off(args[1] and args[1]:lower(), settings.show)
            config.save(settings)
            chat(string.format("[AbysseanRadar] レーダー: %s", settings.show and "オン" or "オフ"))
        elseif cmd == "log" then
            settings.logging = on_off(args[1] and args[1]:lower(), settings.logging)
            config.save(settings)
            chat(string.format("[AbysseanRadar] 記録 (ping.log): %s", settings.logging and "オン" or "オフ"))
        elseif cmd == "clear" then
            tracks, active = {}, nil
            hide_radar()
            chat("[AbysseanRadar] 追跡を消しました。")
        elseif cmd == "range" and tonumber(args[1]) then
            settings.range = math.max(20, math.min(300, tonumber(args[1])))
            config.save(settings)
            chat(string.format("[AbysseanRadar] レーダーの半径を %dヤルムにしました。", settings.range))
        elseif cmd == "size" and tonumber(args[1]) then
            settings.radar_size = math.max(80, math.min(400, tonumber(args[1])))
            config.save(settings)
            chat(string.format("[AbysseanRadar] レーダーの大きさを %dピクセルにしました。", settings.radar_size))
        elseif cmd == "speed" and tonumber(args[1]) then
            settings.speed = math.max(0, math.min(10, tonumber(args[1])))
            config.save(settings)
            for _, track in pairs(tracks) do recompute(track) end
            chat(string.format("[AbysseanRadar] アビセアンの最大の速さを %.1f ヤルム/秒にしました。", settings.speed))
        elseif cmd == "pos" and tonumber(args[1]) and tonumber(args[2]) then
            settings.radar_pos.x, settings.radar_pos.y = tonumber(args[1]), tonumber(args[2])
            config.save(settings)
            next_refresh = 0
        elseif cmd == "mode" then
            local want = args[1] and args[1]:lower()
            if want == "north" or want == "n" then settings.mode = "north"
            elseif want == "heading" or want == "h" then settings.mode = "heading"
            else settings.mode = (settings.mode == "heading") and "north" or "heading" end
            config.save(settings)
            next_refresh = 0
            chat(string.format("[AbysseanRadar] 表示の向き: %s", MODE_LABEL[settings.mode]))
        elseif cmd == "map" then
            settings.map = on_off(args[1] and args[1]:lower(), settings.map)
            config.save(settings)
            next_refresh = 0
            if not settings.map then hide_map() end
            chat(string.format("[AbysseanRadar] 地図: %s%s", settings.map and "オン" or "オフ",
                (settings.map and not map_state.dir) and " (このゾーンの地図が maps/ に無いので、出ません。tools/convert_maps.ps1 で用意してください)" or ""))
        elseif cmd == "mapsize" and tonumber(args[1]) then
            settings.map_d = math.max(120, math.min(400, tonumber(args[1])))
            config.save(settings)
            next_refresh = 0
            chat(string.format("[AbysseanRadar] 地図の円の直径を %dピクセルにしました (縁の輪は、その外側に付きます)。", settings.map_d))
        elseif cmd == "mapzoom" and tonumber(args[1]) then
            settings.map_zoom = math.max(1, math.min(8, tonumber(args[1])))
            config.save(settings)
            next_refresh = 0
            local g = map_geom()
            chat(string.format("[AbysseanRadar] 地図の拡大を %.2f にしました (欠けが出ない範囲 %.2f〜%.2f に収めます)。", g.z, g.zmin, g.zmax))
        elseif cmd == "mapalpha" and tonumber(args[1]) then
            settings.map_alpha = math.max(0, math.min(255, math.floor(tonumber(args[1]))))
            config.save(settings)
            next_refresh = 0
            chat(string.format("[AbysseanRadar] 地図の濃さを %d (0〜255) にしました。", settings.map_alpha))
        elseif cmd == "notify" then
            settings.notify = on_off(args[1] and args[1]:lower(), settings.notify)
            config.save(settings)
            chat(string.format("[AbysseanRadar] 近づいたときのチャットの知らせ: %s (%dYm と %dYm)", settings.notify and "オン" or "オフ", settings.notify_near, settings.notify_close))
        elseif cmd == "sound" then
            settings.sound = on_off(args[1] and args[1]:lower(), settings.sound)
            config.save(settings)
            chat(string.format("[AbysseanRadar] 知らせの音: %s (sounds/near.wav・sounds/close.wav を置くと鳴ります)", settings.sound and "オン" or "オフ"))
        elseif cmd == "near" and tonumber(args[1]) then
            settings.notify_near = math.max(2, math.min(300, tonumber(args[1])))
            if settings.notify_close >= settings.notify_near then settings.notify_close = math.max(1, settings.notify_near / 2) end
            config.save(settings)
            chat(string.format("[AbysseanRadar] 「近づきました」の距離を %.0fYm にしました (すぐ近く = %.0fYm)", settings.notify_near, settings.notify_close))
        elseif cmd == "close" and tonumber(args[1]) then
            settings.notify_close = math.max(1, math.min(tonumber(args[1]), settings.notify_near - 1))
            config.save(settings)
            chat(string.format("[AbysseanRadar] 「すぐ近く」の距離を %.0fYm にしました (近づきました = %.0fYm)", settings.notify_close, settings.notify_near))
        elseif cmd == "alpha" and tonumber(args[1]) then
            settings.alpha = math.max(0, math.min(255, math.floor(tonumber(args[1]))))
            config.save(settings)
            next_refresh = 0
            chat(string.format("[AbysseanRadar] レーダーの背景の濃さを %d (0〜255) にしました。", settings.alpha))
        elseif cmd == "color" then
            -- //ar color 強 255 0 0 / //ar color 2 255 170 60 / //ar color reset
            local which = args[1] or ""
            if which == "reset" then
                for i = 1, 4 do
                    settings["color" .. i] = STAGE_DEFAULT_COLOR[i]
                    STAGE_COLOR[i] = parse_color(STAGE_DEFAULT_COLOR[i])
                end
                config.save(settings)
                next_refresh = 0
                chat("[AbysseanRadar] 段階の色を、初期の色に戻しました。")
            else
                local idx = tonumber(which)
                if not idx then
                    for i, mark in ipairs({"小", "大", "強", "激"}) do if which == mark then idx = i end end
                end
                local c = parse_color(table.concat({args[2] or "", args[3] or "", args[4] or ""}, ","))
                if idx and idx >= 1 and idx <= 4 and c then
                    STAGE_COLOR[idx] = c
                    settings["color" .. idx] = table.concat(c, ",")
                    config.save(settings)
                    next_refresh = 0
                    chat(string.format("[AbysseanRadar] %s の色を %d,%d,%d にしました。", STAGE_MARK[idx], c[1], c[2], c[3]))
                else
                    chat("[AbysseanRadar] 使い方: //ar color <小|大|強|激> <赤> <緑> <青> (0〜255)  /  //ar color reset", 167)
                end
            end
        elseif cmd == "status" then
            local n = 0
            for _, track in pairs(tracks) do
                n = n + 1
                local e = track.est
                chat(string.format("  %s %s: %d回測定%s", STAGE_MARK[track.stage or 0] or "?", track.color, #track.pings,
                    e and string.format(" / 推定 X %.0f Y %.0f ±%.0fYm", e.x, e.y, e.radius) or ""))
            end
            if n == 0 then chat("[AbysseanRadar] 追跡中のアビセアンはありません") end
            chat(string.format("[AbysseanRadar] 知らせ: チャット %s / 音 %s (近づきました %.0fYm・すぐ近く %.0fYm) / 背景の濃さ %d",
                settings.notify and "オン" or "オフ", settings.sound and "オン" or "オフ", settings.notify_near, settings.notify_close, settings.alpha))
            chat(string.format("[AbysseanRadar] 記録 %s / 今回の記録 %d 行", settings.logging and "オン" or "オフ", logged))
            chat(string.format("[AbysseanRadar] 地図: %s (このゾーン: %s)", settings.map and "オン" or "オフ", map_state.dir and "あり" or "なし"))
            chat(string.format("[AbysseanRadar] キャラの向きの読み取り: %s (走って確認: %s、合っていた %d 回 / 逆だった %d 回)", head_sign == -1 and "標準" or "逆に直した",
                head_checked and "済み" or "まだ", head_votes.a, head_votes.b))
        elseif cmd == "truth" then
            -- アビセアンをターゲットして打つ: その敵の実際の位置と、最後の推定を比べる
            local target = windower.ffxi.get_mob_by_target("t")
            if not target or not target.x then
                chat("[AbysseanRadar] 比べたい敵 (姿を現したアビセアン) をターゲットして、//ar truth と打ってください。", 123)
            else
                report_truth(target, "ターゲット")
            end
        elseif cmd == "last" then
            if #recent == 0 then chat("[AbysseanRadar] まだ記録がありません") return end
            for _, line in ipairs(recent) do chat("  " .. line) end
        else
            chat("[AbysseanRadar] v0.6.1。ジェイドのヒーリングの結果から、アビセアンの位置を推定して、レーダーに出します")
            chat("[AbysseanRadar] 場所を変えて何回かヒーリングすると絞れます。北が上、点は赤 = 推定、黄 = 各回の見込み、輪 = いそうな範囲 (輪が小さいほど絞れている)")
            chat("[AbysseanRadar] //ar hud [on|off] / mode [north|heading] / clear / range <ヤルム> / size <px> / speed <ヤルム/秒> / pos <X> <Y> / status / last / log [on|off]")
            chat("[AbysseanRadar] 地図: map [on|off] / mapsize <円の直径px> / mapzoom <倍率> / mapalpha <0-255> (地図はレーダーの代わりに出る。ドラッグ = 移動、ホイール = 拡大、右クリック = 表示の切替。地図は tools/convert_maps.ps1 で用意します。README を見てください)")
            chat("[AbysseanRadar] 設定: notify [on|off] / sound [on|off] / near <m> / close <m> / alpha <0-255> / color <小|大|強|激> <R> <G> <B> | reset")
            chat("[AbysseanRadar] レーダーはマウスでドラッグして動かせます。ホイールで範囲を変え、右クリックで表示の向きを切り替えます。星 = アビセアン、矢印 = 動いていそうな向き")
            chat("[AbysseanRadar] //ar truth : 姿を現したアビセアンをターゲットして打つと、実際の位置と推定のずれが出ます (答え合わせ)")
        end
    end)
    if not ok then chat("[AbysseanRadar] コマンドエラー: " .. tostring(err), 123) end
end)
