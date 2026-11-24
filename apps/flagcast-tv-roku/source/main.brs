' Flagcast TV for Roku: the club's leaderboard screen. Roku has no web views, so this draws the board's pages from the
' feed flagcast.app builds for TVs (tv.js / tvfeed.js on the server). See components/MainScene.brs.
sub Main(args as Dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.setMessagePort(port)
    scene = screen.CreateScene("MainScene")
    screen.show()
    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent" and msg.isScreenClosed() then return
    end while
end sub
