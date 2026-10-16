-- =============================================================================
-- radar_math.lua : AbysseanRadar の計算部分 (Windower に依存しない。素の Lua 5.1 でテストできる)
-- =============================================================================
-- 座標の約束 (実データで確認した向き。2026-10-16、ラテーヌ高原の 4 回の測定):
--   X は東にプラス、Y は北にプラス。方角は北を 0 とし、時計回りに増える (東 = 90 度)。
--   → 方角 theta (ラジアン) の向きの単位ベクトルは (sin theta, cos theta)
-- =============================================================================

local M = {}

local PI = math.pi
local function rad(deg) return deg * PI / 180 end

-- 方角の言葉 → 角度 (度)。8 方位と、16 方位の追加分
local DIRECTIONS = {
    ["北"] = 0, ["北東"] = 45, ["東"] = 90, ["南東"] = 135, ["南"] = 180, ["南西"] = 225, ["西"] = 270, ["北西"] = 315,
    ["北北東"] = 22.5, ["東北東"] = 67.5, ["東南東"] = 112.5, ["南南東"] = 157.5,
    ["南南西"] = 202.5, ["西南西"] = 247.5, ["西北西"] = 292.5, ["北北西"] = 337.5,
}
local DIRECTIONS_16_ONLY = {
    ["北北東"] = true, ["東北東"] = true, ["東南東"] = true, ["南南東"] = true,
    ["南南西"] = true, ["西南西"] = true, ["西北西"] = true, ["北北西"] = true,
}
M.DIRECTIONS_16_ONLY = DIRECTIONS_16_ONLY

-- 振動の言葉 → ジェイドの段階
local VIBRATION = {["小さく"] = 1, ["大きく"] = 2, ["力強く"] = 3, ["激しく"] = 4}

M.HALF_8 = rad(22.5)       -- 8 方位のとき、方角が持つ幅 (片側)
M.HALF_16 = rad(11.25)     -- 16 方位のとき

-- ヒーリングのメッセージを読む。書式 (実データ):
--   「灰色のジェイドは、大きく振動し、南の方向の約10Ym先に向かって光を発した。」
--   「三日月形の緋色のジェイドは、力強く振動し、北東の方向の約8Ym先に向かって光を発した。」
-- 戻り値: {color, crescent, stage, dir, dist, bearing} か、読めなければ nil
function M.parse(text)
    if not text then return nil end
    -- ジェイドの名前は 3 通り見つかっている: 「灰色のジェイド」「三日月形の緋色のジェイド」「変色ジェイド」(「の」が付かない)
    local who, vib, dir, dist = text:match("(.-)ジェイドは、(.-)振動し、(.-)の方向の約(%d+)Ym先")
    if not who or not DIRECTIONS[dir] then return nil end
    local crescent = false
    local color = who
    local rest = who:match("^三日月形の(.*)$")
    if rest then crescent, color = true, rest end
    color = color:gsub("の$", "")
    if color == "" then color = "?" end
    return {
        color = color, crescent = crescent, stage = VIBRATION[vib] or 0, vibration = vib,
        dir = dir, dist = tonumber(dist), bearing = rad(DIRECTIONS[dir]),
    }
end

-- 打った地点 (px, py) から、方角 bearing・距離 dist の点
function M.point(px, py, dist, bearing)
    return px + dist * math.sin(bearing), py + dist * math.cos(bearing)
end

-- 角度の差 (-pi〜pi)
local function angle_diff(a, b)
    local d = (a - b) % (2 * PI)
    if d > PI then d = d - 2 * PI end
    return d
end

-- 位置の推定。pings = {{t, px, py, dist, bearing, half}, ...}、now = 今の時刻 (t と同じ単位の秒)
-- 標的は動くので、古い測定ほど「許される範囲」を広げる (最大の速さ speed ヤルム/秒 のぶん、その測定の範囲が膨らむ)。
-- 新しい測定は厳しく、古い測定は緩く効くので、動いた標的の「今いる場所」に寄る。
-- 方法: 候補の点を格子で調べ、各測定の範囲 (距離の幅 + 方角の幅) からのはみ出しの合計が小さい点の
--       重心を推定位置にする。戻り値: {x, y, radius, cost, n}  (radius = 候補の広がり (ヤルム))
function M.estimate(pings, now, opts)
    opts = opts or {}
    local speed = opts.speed or 1.5
    local max_age = opts.max_age or 240
    local used = {}
    for _, p in ipairs(pings) do
        local age = now - p.t
        if age <= max_age then
            used[#used + 1] = {p = p, age = math.max(age, 0)}
        end
    end
    if #used == 0 then return nil end

    -- 1 回ぶんの点の推定 (探す範囲を決めるため)
    local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
    local maxd = 0
    for _, u in ipairs(used) do
        local p = u.p
        local tx, ty = M.point(p.px, p.py, p.dist, p.bearing)
        minx, maxx = math.min(minx, tx, p.px), math.max(maxx, tx, p.px)
        miny, maxy = math.min(miny, ty, p.py), math.max(maxy, ty, p.py)
        maxd = math.max(maxd, p.dist)
    end
    local margin = maxd * 0.5 + 10
    minx, maxx, miny, maxy = minx - margin, maxx + margin, miny - margin, maxy + margin

    local function cost_at(x, y)
        local c = 0
        for _, u in ipairs(used) do
            local p = u.p
            local slack = speed * u.age                       -- この測定から標的が動けた距離
            local dx, dy = x - p.px, y - p.py
            local d = math.sqrt(dx * dx + dy * dy)
            local sd = 2 + 0.06 * p.dist                      -- 距離の読みの幅 (四捨五入と誤差)
            local over_d = math.max(0, math.abs(d - p.dist) - sd - slack)
            local pen = math.max(0, math.abs(angle_diff(math.atan2(dx, dy), p.bearing)) - (p.half or M.HALF_8))
            local over_l = math.max(0, d * math.sin(math.min(pen, PI / 2)) - slack)   -- 方角の幅からの横のはみ出し
            c = c + (over_d / 3) ^ 2 + (over_l / 3) ^ 2
        end
        return c
    end

    -- 格子で調べて、良い点 (最小のコスト + 余裕) の重心と広がりを出す
    local function scan(x0, x1, y0, y1, step, tolerance)
        local cells, best = {}, math.huge
        local y = y0
        while y <= y1 do
            local x = x0
            while x <= x1 do
                local c = cost_at(x, y)
                cells[#cells + 1] = {x, y, c}
                if c < best then best = c end
                x = x + step
            end
            y = y + step
        end
        local sx, sy, n = 0, 0, 0
        for _, cell in ipairs(cells) do
            if cell[3] <= best + tolerance then sx, sy, n = sx + cell[1], sy + cell[2], n + 1 end
        end
        local cx, cy = sx / n, sy / n
        local var = 0
        for _, cell in ipairs(cells) do
            if cell[3] <= best + tolerance then var = var + (cell[1] - cx) ^ 2 + (cell[2] - cy) ^ 2 end
        end
        return cx, cy, math.sqrt(var / n), best
    end

    local span = math.max(maxx - minx, maxy - miny)
    local step1 = math.max(2, span / 90)
    local cx, cy, r1 = scan(minx, maxx, miny, maxy, step1, 1.5)
    -- 2 回目: 重心のまわりを細かく
    local box = math.max(r1 * 1.8, step1 * 3, 8)
    local step2 = math.max(0.5, box / 45)
    local x, y, radius, best = scan(cx - box, cx + box, cy - box, cy + box, step2, 1.5)
    return {x = x, y = y, radius = math.max(radius, step2), cost = best, n = #used}
end

-- 相手の方向 (自分から見て)。戻り値: 8 方位の名前, 矢印, 距離
local COMPASS = {"北", "北東", "東", "南東", "南", "南西", "西", "北西"}
local ARROWS = {"↑", "↗", "→", "↘", "↓", "↙", "←", "↖"}
function M.compass(dx, dy)
    local bearing = math.atan2(dx, dy)                        -- 北 = 0、時計回り
    local index = math.floor(((bearing / (2 * PI)) * 8 + 0.5) % 8) + 1
    return COMPASS[index], ARROWS[index], math.sqrt(dx * dx + dy * dy)
end

-- 見込みの確かさ (広がりから)
function M.quality(radius)
    if radius < 6 then return "ほぼ特定" end
    if radius < 15 then return "だいたい" end
    return "まだ広い"
end

-- -----------------------------------------------------------------------------
-- 表示の向き (v0.3.0)
-- -----------------------------------------------------------------------------
-- 自分の向き (heading、ラジアン) の前向きベクトル。mappy が地図に描く向きの線と同じ約束:
--   (cos h, -sin h) (X は東、Y は北)。sign = -1 が既定。実機で逆だと分かったときは sign = +1 にする
function M.forward(heading, sign)
    return math.cos(heading), (sign or -1) * math.sin(heading)
end

-- 自分から見た「世界でのずれ」(dx = 東、dy = 北) を、画面の (右, 上) に変える。
--   mode = "north"   : 北が上 (そのまま)
--   mode = "heading" : 自分が向いている方が上
function M.rotate_to_view(dx, dy, mode, heading, sign)
    if mode ~= "heading" or not heading then return dx, dy end
    local fx, fy = M.forward(heading, sign)
    return dx * fy - dy * fx, dx * fx + dy * fy
end

-- 画面の (右, 上) の向きを、矢印の画像の番号 (0 = 上、時計回りに 22.5 度ずつ、0〜15) にする
function M.arrow_index(right, up)
    local a = math.atan2(right, up)                         -- 上 = 0、時計回り
    return math.floor(a / (2 * PI) * 16 + 0.5) % 16
end

-- -----------------------------------------------------------------------------
-- 標的の動き (v0.3.0)
-- -----------------------------------------------------------------------------
-- 推定位置の履歴 snaps = {{t, x, y, r}, ...} から、動く向きと速さを出す。
-- 一番新しいものと、8〜45 秒前のうち一番古いものを比べる。ずれが推定の広がりより十分大きいときだけ返す (ゆらぎの除外)。
-- 戻り値: {vx, vy, speed} か nil
function M.velocity(snaps)
    local n = #snaps
    if n < 2 then return nil end
    local last = snaps[n]
    local first
    for i = 1, n - 1 do
        local age = last.t - snaps[i].t
        if age >= 8 and age <= 45 then first = snaps[i] break end
    end
    if not first then return nil end
    local dt = last.t - first.t
    local dx, dy = last.x - first.x, last.y - first.y
    local disp = math.sqrt(dx * dx + dy * dy)
    if disp < math.max(5, 0.7 * ((last.r or 0) + (first.r or 0))) then return nil end
    local speed = disp / dt
    if speed > 4 then return nil end                         -- 速すぎるのは、推定の乱れ
    return {vx = dx / dt, vy = dy / dt, speed = speed}
end

return M
