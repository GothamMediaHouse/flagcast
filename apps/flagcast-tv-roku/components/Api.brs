sub init()
    m.top.functionName = "go"
end sub

sub go()
    t = CreateObject("roUrlTransfer")
    t.SetUrl(m.top.base + "/golf/api/tv/" + m.top.op)
    t.SetCertificatesFile("common:/certs/ca-bundle.crt")
    t.InitClientCertificates()
    t.AddHeader("Content-Type", "application/json")
    t.RetainBodyOnError(true)
    port = CreateObject("roMessagePort")
    t.SetMessagePort(port)
    status = 0
    out = {}
    if t.AsyncPostFromString(FormatJson(m.top.body))
        msg = wait(20000, port)
        if type(msg) = "roUrlEvent"
            status = msg.GetResponseCode()
            j = ParseJson(msg.GetString())
            if j <> invalid then out = j
        else
            t.AsyncCancel()
        end if
    end if
    m.top.status = status
    m.top.result = out
end sub
