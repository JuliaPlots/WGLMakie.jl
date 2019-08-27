using WGLMakie, AbstractPlotting, WebIO

current_plot = Base.RefValue{Any}()
three_screen = Base.RefValue{Any}()
WebIO.routing_callback[] = function (request)
    return sprint() do io
        print(io, """
            <!doctype html><html><head>
            <meta charset="UTF-8"></head>
            <meta name="viewport" content="width=device-width, initial-scale=1"><body>
        """)
        three_screen[] = show(io, WebIO.WEBIO_APPLICATION_MIME(), current_plot[])
        print(io, "</body></html>")
    end
end
x = AbstractPlotting.Node(rand(4))
current_plot[] = scatter(x);
show(IOBuffer(),  WebIO.WEBIO_APPLICATION_MIME(), WebIO.node(:div, "start server"))
using Electron
WebIO.webio_server_config[]
app = Electron.Application()

win = Electron.Window(app, URI("http://localhost:8081/"))

using JSCall, Base64
using Statistics, ImageMagick

getimage()
using ImageMagick
using ImageShow
