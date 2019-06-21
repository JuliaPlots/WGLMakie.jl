using WGLMakie, AbstractPlotting, WebIO, JSCall, AssetRegistry
using FileIO, Colors, ImageShow, FixedPointNumbers


f64 = Float64.(AbstractPlotting.get_texture_atlas().data)
mini, maxi = extrema(f64)
g16_normed = Gray{N0f16}.((f64 .- mini) ./ (maxi - mini))
path = joinpath(homedir(), "Desktop", "texture_atlas_web.tiff")
save(path, rotl90(g16_normed))
x = load(path)
reconstr = (Float64.(red.(x)) * (maxi - mini)) .+ mini
Float16.(reconstr) ≈ AbstractPlotting.get_texture_atlas().data

jsm = WGLMakie.three_scene(scene)
jsm.RedFormat |> JSCall.jlvalue
open(joinpath(@__DIR__, "index.html"), "w") do io
    show(io, WebIO.WEBIO_APPLICATION_MIME(), WGLMakie.three_scene(scene))
end
typeof(x)
mini = (0, 1)
maxi = (1, 2)

jscam = jsm.THREE.new.OrthographicCamera(
    mini[1], maxi[1], maxi[2], mini[2], -10_000, 10_000
)
AbstractPlotting.to_align((:left, :bottom))
