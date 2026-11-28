' Flagcast TV for Roku. Not connected: ask flagcast.app for a code (hello) and wait for the club to type it in the
' Manager (wait). Connected (the token is kept in the registry): ask what to show (now) every 10 seconds on a tournament
' day, every minute otherwise, and draw the board's pages one after another, each for its seconds.

sub init()
    m.reg = CreateObject("roRegistrySection", "flagcast")
    m.pairing = invalid
    m.demo = false
    m.feedKey = ""
    m.pages = []
    m.idx = 0
    m.shown = 0
    m.video = invalid
    m.top.findNode("tick").observeField("fire", "onTick")
    m.top.findNode("tick").control = "start"
    m.top.findNode("again").observeField("fire", "nextStep")
    m.top.setFocus(true)
    nextStep()
end sub

' ---- talking to flagcast.app ----
sub call(op as String, body as Object)
    a = CreateObject("roSGNode", "Api")
    a.op = op
    a.body = body
    a.observeField("result", "onResult")
    m.api = a
    a.control = "RUN"
end sub

sub later(secs as Integer)
    t = m.top.findNode("again")
    t.control = "stop"
    t.duration = secs
    t.control = "start"
end sub

function today() as String
    d = CreateObject("roDateTime")
    d.ToLocalTime()
    return d.GetYear().ToStr() + "-" + pad(d.GetMonth()) + "-" + pad(d.GetDayOfMonth())
end function

function pad(n as Integer) as String
    if n < 10 then return "0" + n.ToStr()
    return n.ToStr()
end function

function token() as String
    if m.reg.Exists("token") then return m.reg.Read("token")
    return ""
end function

' what to do next: connected → now; else a code (hello) or keep waiting for it (wait)
sub nextStep()
    if token() <> ""
        call("now", { token: token(), today: today(), feed: 1 })
    else if m.demo
        call("demo", {})
    else if m.pairing = invalid
        call("hello", { kind: "roku" })
    else
        call("wait", { code: m.pairing.code, pair: m.pairing.pair })
    end if
end sub

sub onResult()
    a = m.api
    op = a.op
    j = a.result
    s = a.status
    m.top.findNode("offline").visible = (s = 0)
    if op = "hello"
        if s = 200 and j.code <> invalid
            m.pairing = j
            showPair(j.code, "")
            later(3)
        else
            msg = "Can’t reach Flagcast. Check the Roku’s internet."
            if j.error <> invalid then msg = j.error
            showPair("······", msg)
            later(15)
        end if
    else if op = "wait"
        if s = 200 and j.token <> invalid
            m.reg.Write("token", j.token)
            m.reg.Flush()
            m.pairing = invalid
            nextStep()
        else
            if s = 410 then m.pairing = invalid
            later(3)
        end if
    else if op = "demo"
        if not m.demo then return
        if s = 200 and j.feed <> invalid
            showBoard(j.feed)
            m.top.findNode("demoTag").visible = true
            later(10)
        else if m.top.findNode("board").visible
            later(15)
        else
            m.demo = false
            msg = "The demo isn’t available right now."
            if j.error <> invalid then msg = j.error
            if m.pairing <> invalid then showPair(m.pairing.code, msg)
            later(3)
        end if
    else if op = "now"
        if s = 401
            m.reg.Delete("token")
            m.reg.Flush()
            m.pairing = invalid
            stopVideo()
            nextStep()
        else if s = 200 and j.tv <> invalid
            if j.event <> invalid and j.feed <> invalid
                showBoard(j.feed)
                later(10)
            else
                showIdle(j)
                later(60)
            end if
        else
            later(15)
        end if
    end if
end sub

sub only(id as String)
    for each g in ["pair", "idle", "board"]
        m.top.findNode(g).visible = (g = id)
    end for
    if id <> "board" then m.top.findNode("demoTag").visible = false
    if id <> "board" then stopVideo()
end sub

' ---- not connected ----
sub showPair(code as String, note as String)
    only("pair")
    spaced = ""
    for i = 0 to Len(code) - 1
        spaced = spaced + Mid(code, i + 1, 1)
        if i < Len(code) - 1 then spaced = spaced + " "
    end for
    m.top.findNode("code").text = spaced
    if note = "" then note = "The code changes every 10 minutes."
    m.top.findNode("pairNote").text = note
end sub

' ---- between tournaments: the club's logo (Flagcast's only when the club has none) and the next tournament ----
sub showIdle(j as Object)
    only("idle")
    c = j.club
    logo = m.top.findNode("idleLogo")
    if c.flagcast or c.logo = "" then logo.uri = "pkg:/images/wordmark.png" else logo.uri = absUrl(c.logo)
    if c.name <> "" then m.top.findNode("welcome").text = "WELCOME TO " + UCase(c.name) else m.top.findNode("welcome").text = "WELCOME"
    nl = m.top.findNode("nextLine")
    nl.color = colorOf(c.accent, "0xE8C547FF")
    if j.next <> invalid
        line = "Next tournament: " + j.next.name
        if j.next.date <> "" then line = line + " · " + j.next.date
        nl.text = line
        m.top.findNode("nextSmall").text = "Live scores show here on the day"
    else
        nl.text = ""
        m.top.findNode("nextSmall").text = ""
    end if
end sub

function absUrl(u as String) as String
    if Left(u, 8) = "https://" then return u
    return "https://flagcast.app" + u
end function

function colorOf(hex as Dynamic, fallback as String) as String
    if hex = invalid or Len(hex) < 6 then return fallback
    h = hex
    if Left(h, 1) = "#" then h = Mid(h, 2)
    if Len(h) <> 6 then return fallback
    return "0x" + UCase(h) + "FF"
end function

' ---- the board ----
sub showBoard(f as Object)
    only("board")
    m.feed = f
    m.accent = colorOf(f.accent, "0xE8C547FF")
    lg = m.top.findNode("logo")
    if f.flagcast or f.logo = "" then lg.uri = "pkg:/images/wordmark.png" else lg.uri = absUrl(f.logo)
    m.top.findNode("title").text = UCase(f.title)
    tag = m.top.findNode("liveTag")
    if f.locked then tag.text = "FINAL" else tag.text = "LIVE"
    tag.color = m.accent
    m.top.findNode("ticker").text = f.ticker
    m.top.findNode("tickerBar").visible = (f.ticker <> "")
    m.top.findNode("ticker").visible = (f.ticker <> "")
    m.top.findNode("flash").text = f.flash
    m.top.findNode("flash").visible = (f.flash <> "")
    m.top.findNode("flashBar").visible = (f.flash <> "")
    m.top.findNode("flashBar").color = m.accent
    showTake(f.take)
    ' new pages: keep the page on screen if it's still there (scores refresh in place), else start again
    key = ""
    for each p in f.pages
        key = key + p.k + "|"
        if p.page <> invalid then key = key + p.page.ToStr()
        if p.hole <> invalid then key = key + "h" + p.hole.ToStr()
        key = key + ","
    end for
    m.pages = f.pages
    if m.pages.Count() = 0 then m.pages = [{ k: "empty", secs: 30, text: "Scores will show here once the first group is out." }]
    if key <> m.feedKey or m.idx >= m.pages.Count()
        m.feedKey = key
        m.idx = 0
        m.shown = 0
        drawPage(true)
    else
        drawPage(false)
    end if
end sub

sub showTake(t as Dynamic)
    g = m.top.findNode("take")
    if t = invalid then g.visible = false : return
    if t.kind = "ace" then m.top.findNode("takeHead").text = "HOLE IN ONE!" else m.top.findNode("takeHead").text = ""
    m.top.findNode("takeHead").color = m.accent
    m.top.findNode("takeText").text = t.text
    g.visible = true
end sub

sub onTick()
    if not m.top.findNode("board").visible or m.pages.Count() = 0 then return
    m.shown = m.shown + 1
    p = m.pages[m.idx]
    secs = 12
    if p.secs <> invalid then secs = p.secs
    if secs < 4 then secs = 4
    if m.shown >= secs
        m.idx = (m.idx + 1) mod m.pages.Count()
        m.shown = 0
        drawPage(true)
    end if
end sub

' a phone that just went live isn't on Cloudflare for 10–30 seconds (the playlist answers 404), and a camera can drop
' out: when the video fails or ends, try it again in 4 seconds
sub onVideoState()
    if m.video = invalid then return
    st = m.video.state
    if st = "error" or st = "finished"
        if m.retry = invalid
            m.retry = CreateObject("roSGNode", "Timer")
            m.retry.duration = 4
            m.retry.repeat = false
            m.retry.observeField("fire", "onVideoRetry")
        end if
        m.retry.control = "start"
    end if
end sub

sub onVideoRetry()
    if m.video = invalid then return
    m.video.control = "stop"
    m.video.control = "play"
end sub

sub stopVideo()
    if m.video <> invalid
        m.video.control = "stop"
        m.video = invalid
    end if
end sub

' draw the current page in the stage (1920×900 under the header); fresh = a new page (else refresh scores in place)
sub drawPage(fresh as Boolean)
    p = m.pages[m.idx]
    if p.k = "cam" and not fresh then return ' don't restart the video every 10 seconds
    stage = m.top.findNode("stage")
    stopVideo()
    stage.removeChildrenIndex(stage.getChildCount(), 0)
    if p.k = "lb"
        drawLeaderboard(stage, p)
    else if p.k = "cam"
        v = stage.createChild("Video")
        v.width = 1920
        v.height = 900
        v.enableUI = false
        v.mute = true
        c = CreateObject("roSGNode", "ContentNode")
        c.url = p.url
        c.streamFormat = "hls"
        c.live = true
        v.content = c
        v.observeField("state", "onVideoState")
        v.control = "play"
        m.video = v
        tag = "LIVE · HOLE " + p.hole.ToStr()
        if p.label <> invalid and p.label <> "" then tag = "LIVE · " + UCase(p.label)
        if p.pro <> invalid and p.pro <> "" then tag = "LIVE FROM THE PRO · " + Mid(tag, 8)
        if p.par <> invalid and p.par > 0 and (p.label = invalid or p.label = "") then tag = tag + "   PAR " + p.par.ToStr()
        bg = stage.createChild("Rectangle") : bg.translation = [30, 30] : bg.width = 1100 : bg.height = 60 : bg.color = "0xC6362BFF"
        addLabel(stage, tag, 50, 38, 1080, 32, "0xFFFFFFFF", true)
        if p.leader <> invalid and p.leader <> ""
            lb = stage.createChild("Rectangle") : lb.translation = [30, 100] : lb.width = 900 : lb.height = 56 : lb.color = "0xE8C547FF"
            addLabel(stage, "LEADER · " + p.leader, 50, 108, 880, 30, "0x1A1A10FF", true)
        end if
    else if p.k = "sponsor"
        addLabel(stage, "THANK YOU TO", 0, 160, 1920, 28, "0x8FA596FF", false, "center")
        addSponsor(stage, p, 560, 260, 800, 360)
        if p.line <> invalid and p.line <> "" then addLabel(stage, p.line, 100, 680, 1720, 38, "0xC9D6CCFF", false, "center")
    else if p.k = "sponsors"
        addLabel(stage, "THANKS TO OUR SPONSORS", 0, 80, 1920, 60, "0xEEF3ECFF", true, "center")
        n = p.list.Count()
        cols = 4
        if n < 4 then cols = n
        for i = 0 to n - 1
            col = i mod cols
            row = Int(i / cols)
            w = Int(1720 / cols)
            addSponsor(stage, p.list[i], 100 + col * w + 20, 240 + row * 200, w - 40, 160)
        end for
    else if p.k = "phone"
        addLabel(stage, UCase(p.text), 0, 260, 1920, 84, "0xEEF3ECFF", true, "center")
        addLabel(stage, "Open this on your phone. No app needed: the leaderboard, par 3 cameras and replays.", 200, 420, 1520, 36, "0xC9D6CCFF", false, "center")
        addLabel(stage, Mid(p.url, 9), 0, 560, 1920, 64, m.accent, true, "center")
    else
        t = "Scores will show here once the first group is out."
        if p.text <> invalid then t = p.text
        addLabel(stage, t, 0, 420, 1920, 40, "0x8FA596FF", false, "center")
    end if
end sub

sub drawLeaderboard(stage as Object, p as Object)
    addLabel(stage, UCase(p.sub), 60, 26, 1300, 24, "0x8FA596FF", false)
    addLabel(stage, "LEADERBOARD", 60, 58, 1000, 68, "0xEEF3ECFF", true)
    if p.sponsor <> invalid
        addLabel(stage, "Presented by", 1290, 86, 220, 24, "0x8FA596FF", false)
        addSponsor(stage, p.sponsor, 1520, 50, 340, 80)
    else if p.pages > 1
        addLabel(stage, "Page " + p.page.ToStr() + " of " + p.pages.ToStr(), 1500, 90, 360, 26, "0x8FA596FF", false, "right")
    end if
    head = "TO PAR"
    if p.points = true then head = "POINTS"
    addLabel(stage, "POS", 80, 160, 120, 22, "0x8FA596FF", false)
    addLabel(stage, "TEAM", 200, 160, 900, 22, "0x8FA596FF", false)
    addLabel(stage, head, 1460, 160, 200, 22, "0x8FA596FF", false, "right")
    addLabel(stage, "THRU", 1680, 160, 160, 22, "0x8FA596FF", false, "right")
    rule = stage.createChild("Rectangle") : rule.translation = [60, 196] : rule.width = 1800 : rule.height = 3 : rule.color = "0x1D3328FF"
    rows = p.rows
    h = 66
    if rows.Count() > 0 then h = Int(680 / rows.Count())
    if h > 92 then h = 92
    for i = 0 to rows.Count() - 1
        r = rows[i]
        y = 200 + i * h
        if i mod 2 = 1
            band = stage.createChild("Rectangle") : band.translation = [60, y] : band.width = 1800 : band.height = h : band.color = "0x10201AFF"
        end if
        ty = y + Int((h - 44) / 2)
        addLabel(stage, r.pos, 80, ty + 4, 120, 32, "0x8FA596FF", false)
        addLabel(stage, r.name, 200, ty, 1220, 40, "0xEEF3ECFF", true)
        col = "0xEEF3ECFF"
        if r.under = true then col = "0xFF6B5EFF"
        addLabel(stage, r.score, 1460, ty - 2, 200, 44, col, true, "right")
        addLabel(stage, r.thru, 1680, ty + 2, 160, 34, "0xC9D6CCFF", true, "right")
    end for
end sub

function addLabel(parent as Object, text as String, x as Integer, y as Integer, w as Integer, size as Integer, color as String, bold as Boolean, align = "left" as String) as Object
    l = parent.createChild("Label")
    l.horizAlign = align
    l.text = text
    l.translation = [x, y]
    l.width = w
    l.color = color
    f = CreateObject("roSGNode", "Font")
    if bold then f.uri = "font:BoldSystemFontFile" else f.uri = "font:SystemFontFile"
    f.size = size
    l.font = f
    return l
end function

sub addSponsor(parent as Object, s as Object, x as Integer, y as Integer, w as Integer, h as Integer)
    if s.logo <> invalid and s.logo <> ""
        po = parent.createChild("Poster")
        po.translation = [x, y]
        po.width = w
        po.height = h
        po.loadDisplayMode = "scaleToFit"
        po.uri = s.logo
    else
        addLabel(parent, s.name, x, y + Int(h / 2) - 26, w, 48, "0xEEF3ECFF", true, "center")
    end if
end sub

' OK on the code screen: "Watch a demo" (the live Demo tournament). Back leaves the demo for the code (a new one if
' it ran out). Otherwise OK checks now (handy if a TV looks stuck)
function onKeyEvent(key as String, press as Boolean) as Boolean
    if press and key = "OK" and token() = "" and not m.demo and m.top.findNode("pair").visible
        m.demo = true
        nextStep()
        return true
    end if
    if press and key = "back" and m.demo
        m.demo = false
        stopVideo()
        m.pairing = invalid
        nextStep()
        return true
    end if
    if press and key = "OK"
        nextStep()
        return true
    end if
    return false
end function
