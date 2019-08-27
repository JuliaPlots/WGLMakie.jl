using WGLMakie, AbstractPlotting, WebIO

current_plot = Base.RefValue{Any}()
WebIO.routing_callback[] = function (request)
    return sprint() do io
        print(io, """
            <!doctype html><html><head>
            <meta charset="UTF-8"></head>
            <meta name="viewport" content="width=device-width, initial-scale=1"><body>
        """)
        show(io, WebIO.WEBIO_APPLICATION_MIME(), current_plot[])
        print(io, "</body></html>")
    end
end
show()
x = AbstractPlotting.Node(rand(4))
current_plot[] = scatter(x);
show(IOBuffer(),  WebIO.WEBIO_APPLICATION_MIME(), WebIO.node(:div, "start server"))
using ElectronDisplay
electrondisplay(s)

x[] = rand(4)
s[end].color = :green
x = surface(rand(4, 4))
x[end][1] = rand(4, 4)
using Electron
WebIO.webio_server_config[]
app = Electron.Application()

win = Electron.Window(app, URI("http://localhost:8081/"))


function render() {
    requestAnimationFrame(render);
    renderer.render(scene, camera);
    if(getImageData == true){
        imgData = renderer.domElement.toDataURL();
        getImageData = false;
    }
}
