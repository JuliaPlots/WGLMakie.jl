using Colors, WebIO
using JSCall, JSExpr
using ShaderAbstractions: InstancedProgram
using AbstractPlotting: Key, plotkey
using GeometryTypes: Mat4f0
using Colors: N0f8

function JSInstanceBuffer(context, attribute::AbstractVector{T}) where T
    flat = reinterpret(eltype(T), attribute)
    js_f32 = window.new.Float32Array(flat)
    return THREE.new.InstancedBufferAttribute(js_f32, length(T))
end

function JSBuffer(context, buff::AbstractVector{T}) where T
    flat = reinterpret(eltype(T), buff)
    return THREE.new.Float32BufferAttribute(flat, length(T))
end

jl2js(val::Number) = val
function jl2js(val::Mat4f0)
    x = THREE.new.Matrix4()
    x.fromArray(vec(val))
    return x
end

jl2js(val::Quaternion) = THREE.new.Vector4(val.data...)
jl2js(val::Vec4f0) = THREE.new.Vector4(val...)
jl2js(val::Vec3f0) = THREE.new.Vector3(val...)
jl2js(val::Vec2f0) = THREE.new.Vector2(val...)

function jl2js(val::RGBA)
    return THREE.new.Vector4(red(val), green(val), blue(val), alpha(val))
end
function jl2js(val::RGB)
    return THREE.new.Vector3(red(val), green(val), blue(val))
end

function jl2js(color::Sampler{T}) where T
    data = to_js_buffer(color.data)
    tex = THREE.new.DataTexture(
        data, size(color, 1), size(color, 2),
        three_format(T), three_type(eltype(T))
    )
    tex.minFilter = three_filter(color.minfilter)
    tex.magFilter = three_filter(color.magfilter)
    tex.wrapS = three_repeat(color.repeat[1])
    tex.wrapT = three_repeat(color.repeat[2])
    tex.anisotropy = color.anisotropic
    tex.needsUpdate = true
    return tex
end

function to_js_uniforms(context, dict::Dict)
    result = window.new.Object()
    for (k, v) in dict
        setproperty!(result, k, Dict(:value => jl2js(to_value(v))))
    end
    # for (k, v) in dict
    #     # Sampler + Buffers won't come through as Observables,
    #     # Since they update themselves
    #     v isa Observable || continue
    #     onjs(v, @js function (val)
    #         $(result).$(k).value = val
    #         $(result).$(k).needsUpdate = true
    #     end)
    # end
    return result
end

JSCall.@jsfun function create_material(vert, frag, uniforms)
    @var material = @new $(THREE).RawShaderMaterial(
        Dict(
            :uniforms => uniforms,
            :vertexShader => vert,
            :fragmentShader => frag,
            :side => $(THREE).DoubleSide,
            :transparent => true
            # :depthTest => true,
            # :depthWrite => true
        ),
    )
    return material
end

three_format(::Type{<: Real}) = THREE.AlphaFormat
three_format(::Type{<: RGB}) = THREE.RGBFormat
three_format(::Type{<: RGBA}) = THREE.RGBAFormat

three_type(::Type{Float16}) = THREE.FloatType
three_type(::Type{Float32}) = THREE.FloatType
three_type(::Type{N0f8}) = THREE.UnsignedByteType

function to_js_buffer(array::AbstractArray{T}) where T
    return to_js_buffer(reinterpret(eltype(T), array))
end
function to_js_buffer(array::AbstractArray{Float32})
    return window.Float32Array.from(vec(array))
end
function to_js_buffer(array::AbstractArray{Float16})
    return window.Float32Array.from(vec(Float32.(array)))
end
function to_js_buffer(array::AbstractArray{T}) where T <: Union{N0f8, UInt8}
    return window.Uint8Array.from(vec(array))
end

function three_filter(sym)
    sym == :linear && return THREE.LinearFilter
    sym == :nearest && return THREE.NearestFilter
end
function three_repeat(s::Symbol)
    s == :clamp_to_edge && return THREE.ClampToEdgeWrapping
    s == :mirrored_repeat && return THREE.MirroredRepeatWrapping
    s == :repeat && return THREE.RepeatWrapping
end
using StaticArrays

lasset(paths...) = read(joinpath(dirname(pathof(WGLMakie)), "..", "assets", paths...), String)

isscalar(x::StaticArrays.StaticArray) = true
isscalar(x::AbstractArray) = false
isscalar(x::Observable) = isscalar(x[])
isscalar(x) = true
ShaderAbstractions.type_string(context::ShaderAbstractions.AbstractContext, t::Type{<: AbstractPlotting.Quaternion}) = "vec4"
ShaderAbstractions.convert_uniform(context::ShaderAbstractions.AbstractContext, t::Quaternion) = convert(Quaternion, t)

function wgl_convert(value, key1, key2)
    AbstractPlotting.convert_attribute(value, key1, key2)
end

function wgl_convert(value::AbstractMatrix, ::key"colormap", key2)
    ShaderAbstractions.Sampler(value)
end

AbstractPlotting.plotkey(::Nothing) = :scatter
function lift_convert(key, value, plot)
    val = lift(value) do value
         wgl_convert(value, Key{key}(), Key{plotkey(plot)}())
     end
     if key == :colormap && val[] isa AbstractArray
         return ShaderAbstractions.Sampler(val)
     else
         val
     end
end

function create_shader(scene::Scene, plot::MeshScatter)
    # Potentially per instance attributes
    per_instance_keys = (:rotations, :markersize, :color, :intensity)
    per_instance = filter(plot.attributes.attributes) do (k, v)
        k in per_instance_keys && !(isscalar(v[]))
    end
    per_instance[:offset] = plot[1]

    for (k, v) in per_instance
        per_instance[k] = Buffer(lift_convert(k, v, plot))
    end

    uniforms = filter(plot.attributes.attributes) do (k, v)
        (!haskey(per_instance, k)) && isscalar(v[])
    end

    uniform_dict = Dict{Symbol, Any}()
    for (k,v) in uniforms
        k in (:shading, :overdraw, :fxaa, :visible, :transformation, :alpha, :linewidth, :transparency, :marker) && continue
        uniform_dict[k] = lift_convert(k, v, plot)
    end
    color = to_value(get(uniform_dict, :color, nothing))
    if color isa Colorant || color isa AbstractVector{<: Colorant} || color === nothing
        delete!(uniform_dict, :colormap)
    end

    instance = VertexArray(map(GLNormalMesh, plot.marker))
    if !GeometryBasics.hascolumn(instance, :texturecoordinate)
        uniform_dict[:texturecoordinate] = Vec2f0(0)
    end
    for key in (:view, :projection, :resolution, :eyeposition, :projectionview)
        uniform_dict[key] = getfield(scene.camera, key)
    end
    uniform_dict[:model] = plot.model

    p = InstancedProgram(
        WebGL(),
        lasset("particles.vert"),
        lasset("particles.frag"),
        instance,
        VertexArray(; per_instance...)
        ; uniform_dict...
    )
end

function wgl_convert(context, ip::InstancedProgram)
    # bufferGeometry = THREE.new.BoxBufferGeometry(0.1, 0.1, 0.1);
    js_vbo = THREE.new.InstancedBufferGeometry()
    for (name, buff) in pairs(ip.program.vertexarray)
        js_buff = JSBuffer(context, buff).setDynamic(true)
        js_vbo.addAttribute(name, js_buff)
    end
    indices = GeometryBasics.faces(getfield(ip.program.vertexarray, :data))
    indices = reinterpret(UInt32, indices) .- UInt32(1)
    js_vbo.setIndex(indices)
    js_vbo.maxInstancedCount = length(ip.per_instance)

    # per instance data
    for (name, buff) in pairs(ip.per_instance)
        js_buff = JSInstanceBuffer(context, buff).setDynamic(true)
        js_vbo.addAttribute(name, js_buff)
    end
    uniforms = to_js_uniforms(context, ip.program.uniforms)

    material = WGLMakie.create_material(
        ip.program.vertex_source,
        ip.program.fragment_source,
        to_js_uniforms(context, ip.program.uniforms)
    )
    return THREE.new.Mesh(js_vbo, material)
end

@enum Shape CIRCLE RECTANGLE ROUNDED_RECTANGLE DISTANCEFIELD TRIANGLE
primitive_shape(::Char) = Cint(DISTANCEFIELD)
primitive_shape(x::X) where X = Cint(primitive_shape(X))
primitive_shape(::Type{<: Circle}) = Cint(CIRCLE)
primitive_shape(::Type{<: SimpleRectangle}) = Cint(RECTANGLE)
primitive_shape(::Type{<: HyperRectangle{2}}) = Cint(RECTANGLE)
primitive_shape(x::Shape) = Cint(x)

function scatter_shader(scene::Scene, attributes)
    # Potentially per instance attributes
    per_instance_keys = (:offset, :rotations, :markersize, :color, :intensity, :uv_offset_width)
    per_instance = filter(attributes) do (k, v)
        k in per_instance_keys && !(isscalar(v[]))
    end
    for (k, v) in per_instance
        per_instance[k] = Buffer(lift_convert(k, v, nothing))
    end
    uniforms = filter(attributes) do (k, v)
        (!haskey(per_instance, k)) && isscalar(v[])
    end
    uniform_dict = Dict{Symbol, Any}()
    ignore_keys = (
        :shading, :overdraw, :rotation, :rotations, :distancefield, :fxaa,
        :visible, :transformation, :alpha, :linewidth, :transparency, :marker
    )
    for (k,v) in uniforms
        k in ignore_keys && continue
        uniform_dict[k] = lift_convert(k, v, nothing)
    end
    get!(uniform_dict, :shape_type) do
        lift(primitive_shape, attributes[:marker])
    end
    if uniform_dict[:shape_type][] == 3
        atlas = AbstractPlotting.get_texture_atlas()
        uniform_dict[:distancefield] = Sampler(
            atlas.data,
            minfilter = :linear,
            magfilter = :linear,
            anisotropic = 16f0,
        )
    else
        uniform_dict[:distancefield] = Observable(false)
    end
    if !haskey(per_instance, :uv_offset_width)
        get!(uniform_dict, :uv_offset_width) do
            if haskey(attributes, :marker) && attributes[:marker][] isa Char
                lift(AbstractPlotting.glyph_uv_width!, attributes[:marker])
            else
                Vec4f0(0)
            end
        end
    end
    color = to_value(get(uniform_dict, :color, nothing))
    if color isa Colorant || color isa AbstractVector{<: Colorant} || color === nothing
        delete!(uniform_dict, :colormap)
    end
    instance = VertexArray(GLUVMesh2D(GeometryTypes.SimpleRectangle(0f0, 0f0, 1f0, 1f0)))
    for key in (:resolution,)#(:view, :projection, :resolution, :eyeposition, :projectionview)
        uniform_dict[key] = getfield(scene.camera, key)
    end
    p = InstancedProgram(
        WebGL(),
        lasset("simple.vert"),
        lasset("sprites.frag"),
        instance,
        VertexArray(; per_instance...)
        ; uniform_dict...
    )
end

function create_shader(scene::Scene, plot::Scatter)
    # Potentially per instance attributes
    per_instance_keys = (:offset, :rotations, :markersize, :color, :intensity, :marker_offset)
    per_instance = filter(plot.attributes.attributes) do (k, v)
        k in per_instance_keys && !(isscalar(v[]))
    end
    attributes = copy(plot.attributes.attributes)
    attributes[:offset] = plot[1]
    attributes[:model] = plot.model
    delete!(attributes, :uv_offset_width)
    return scatter_shader(scene, attributes)
end

using AbstractPlotting: get_texture_atlas, glyph_bearing!, glyph_uv_width!, NativeFont, glyph_scale!, calc_position, calc_offset

function to_gl_text(string, startpos::AbstractVector{T}, textsize, font, align, rot, model) where T <: VecTypes
    atlas = get_texture_atlas()
    N = length(T)
    positions, uv_offset_width, scale = Point{N, Float32}[], Vec4f0[], Vec2f0[]
    # toffset = calc_offset(string, textsize, font, atlas)
    char_str_idx = iterate(string)
    broadcast_foreach(1:length(string), startpos, textsize, (font,), align) do idx, pos, tsize, font, align
        char, str_idx = char_str_idx
        _font = isa(font[1], NativeFont) ? font[1] : font[1][idx]
        mpos = model * Vec4f0(to_ndim(Vec3f0, pos, 0f0)..., 1f0)
        push!(positions, to_ndim(Point{N, Float32}, mpos, 0))
        push!(uv_offset_width, glyph_uv_width!(atlas, char, _font))
        if isa(tsize, Vec2f0) # this needs better unit support
            push!(scale, tsize) # Vec2f0, we assume it's already in absolute size
        else
            push!(scale, glyph_scale!(atlas, char,_font, tsize))
        end
        char_str_idx = iterate(string, str_idx)
    end
    positions, Vec2f0(0), uv_offset_width, scale
end

function to_gl_text(string, startpos::VecTypes{N, T}, textsize, font, aoffsetvec, rot, model) where {N, T}
    atlas = get_texture_atlas()
    mpos = model * Vec4f0(to_ndim(Vec3f0, startpos, 0f0)..., 1f0)
    pos = to_ndim(Point{N, Float32}, mpos, 0f0)
    rscale = Float32(textsize)
    chars = Vector{Char}(string)
    scale = glyph_scale!.(Ref(atlas), chars, (font,), rscale)
    positions2d = calc_position(string, Point2f0(0), rscale, font, atlas)
    # font is Vector{FreeType.NativeFont} so we need to protec
    aoffset = AbstractPlotting.align_offset(Point2f0(0), positions2d[end], atlas, rscale, font, aoffsetvec)
    aoffsetn = to_ndim(Point{N, Float32}, aoffset, 0f0)
    uv_offset_width = glyph_uv_width!.(Ref(atlas), chars, (font,))
    positions = map(positions2d) do p
        pn = rot * (to_ndim(Point{N, Float32}, p, 0f0) .+ aoffsetn)
        pn .+ pos
    end
    positions, Vec2f0(0), uv_offset_width, scale
end

function create_shader(scene::Scene, plot::AbstractPlotting.Text)
    liftkeys = (:position, :textsize, :font, :align, :rotation, :model)
    gl_text = lift(to_gl_text, plot[1], getindex.(plot.attributes, liftkeys)...)
    # unpack values from the one signal:
    positions, offset, uv_offset_width, scale = map((1, 2, 3, 4)) do i
        lift(getindex, gl_text, i)
    end
    keys = (:color, :rotation)
    signals = getindex.(plot.attributes, keys)
    return scatter_shader(scene, Dict(
        :shape_type => AbstractPlotting.Node(Cint(3)),
        :color => signals[1],
        :rotation => signals[2],
        :markersize => scale,
        :marker_offset => offset,
        :offset => positions,
        :uv_offset_width => uv_offset_width,
        :model => plot.model,
        :transform_marker => AbstractPlotting.Node(true)
    ))
end


function draw_js(jsscene, scene::Scene, plot::MeshScatter)
    program = create_shader(scene, plot)
    mesh = wgl_convert(jsscene, program)
    jsscene.add(mesh)
end
function draw_js(jsscene, scene::Scene, plot::AbstractPlotting.Text)
    program = create_shader(scene, plot)
    write(joinpath(@__DIR__, "test.vert"), program.program.vertex_source)
    write(joinpath(@__DIR__, "test.frag"), program.program.fragment_source)
    mesh = wgl_convert(jsscene, program)
    mesh.name = "Text"
    jsscene.add(mesh)
end
function draw_js(jsscene, scene::Scene, plot::Scatter)
    program = create_shader(scene, plot)
    mesh = wgl_convert(jsscene, program)

    write(joinpath(@__DIR__, "scatter.vert"), program.program.vertex_source)
    write(joinpath(@__DIR__, "scatter.frag"), program.program.fragment_source)

    mesh.name = "Scatter"
    jsscene.add(mesh)
end