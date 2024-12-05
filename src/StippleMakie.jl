module StippleMakie

using Stipple

using WGLMakie
using WGLMakie.Bonito
using Stipple.HTTP

# import Stipple.Genie.Router.WS_PROXIES
WS_PROXIES = isdefined(Genie.Router, :WS_PROXIES) ? Genie.Router.WS_PROXIES : Dict{String, Any}()

export MakieFigure, init_makiefigures, makie_figure, makie_dom, configure_makie_server!, WGLMakie, Makie

Base.@kwdef mutable struct MakieFigure
    fig::Figure = Figure()
    session::Union{Nothing, Bonito.Session} = nothing
    id = -1
end

Stipple.render(mf::MakieFigure) = Dict(
    :js_id1 => "$(mf.id)",
    :js_id2 => "$(mf.id + 1)"
)

listtypes(T::DataType) = zip(fieldnames(T), fieldtypes(T))
figurenames(T::Type{<:ReactiveModel}) = [n for (n, t) in listtypes(Stipple.get_concrete_type(T)) if t == R{MakieFigure}]
figurenames(model::ReactiveModel) = figurenames(typeof(model))

function init_makiefigure(fig::R{MakieFigure})
    fig.id = fig.session.dom_uuid_counter + 1
    Bonito.jsrender(fig.session, fig.fig)
end

function init_makiefigures(model)
    figurenames(model) .|> n -> init_makiefigure(getfield(model, n))
end

function makie_figure(fig::Symbol, args...; kwargs...)
        htmldiv(class = "full-width full-height", data__jscall__id = Symbol(fig, ".js_id1"),
            canvas(style="display: block", data__jscall__id! = Symbol(fig, ".js_id2"), tabindex = "0"),
            args...; kwargs...
        )
end

"""
    makie_dom(model::ReactiveModel)

Sets up the session of all figures in the model and constructs the DOM for initializing Makie.
"""
function makie_dom(model::ReactiveModel)
    nn = figurenames(model)
    isempty(nn) && return ""
    session = Session()
    for n in nn
        getfield(model, n)[!].session = session
    end
    proxy = get(WS_PROXIES, "makie_proxy", nothing)
    proxy === nothing || close(proxy)
    Bonito.session_dom(session, DOM.div()) |> string |> ParsedHTMLString
end

function Base.empty!(mf::Union{MakieFigure, R{MakieFigure}})
    for c in contents(mf.fig.layout)
        empty!(c.blockscene)
        delete!(c)
    end
    trim!(mf.fig.layout)
end

function configure_makie_server!(; listen_host = nothing, listen_port = Bonito.SERVER_CONFIGURATION.listen_port[], proxy_host = nothing, proxy_port = nothing)
    listen_url = something(listen_host, Genie.config.server_host)
    proxy_host = something(proxy_host, Genie.config.websockets_exposed_host, Genie.config.websockets_host)
    proxy_url = proxy_port === nothing ? nothing : join(filter(!isempty, strip.(["http://$proxy_host:$proxy_port", Genie.config.base_path, Genie.config.websockets_base_path], '/')), "/")

    Bonito.configure_server!(; listen_url, listen_port, proxy_url)

    # in the future we're trying to internally redirect Makie's websocket traffic to Genie's ws server, WIP

    # WS_PROXIES["makie_proxy"] = "ws://localhost:$listen_port/dummy"
    # Bonito.configure_server!(listen_url = "localhost", listen_port = listen_port, proxy_url = "http://localhost:$proxy_port/makie_proxy")
    
    # routename = join(filter(!isempty, [Genie.config.base_path, Genie.config.websockets_base_path, "makie_proxy/assets/:bonito"]), "/")
    # println("routename: $routename")
    # route("/$routename") do
    #     asset = params(:bonito)
    #     @debug "loading asset via proxy: $asset"
    #     res = HTTP.get("http://localhost:$listen_port/assets/$asset")

    #     if endswith(asset, "-Websocket.bundled.js")
    #         # modify the Makie websocket client to suppress control messages from Genie's ws server
    #         res.body = replace(String(res.body), r"( *)const binary = new Uint8Array\(evt.data\);" => 
    #         s"""
    #         \1const binary = new Uint8Array(evt.data);
    #         \1
    #         \1if (typeof(evt.data) == 'string') {
    #         \1    return resolve(null);
    #         \1}
    #         """, "send_pings();" => "") |> Vector{UInt8}
    #     end

    #     return res
    # end

    # Genie.Router.channel("/", named = :makie) do
    #     @debug begin
    #         client = Genie.Requests.wsclient()
    #         """ws proxy in: from $(client.request.target) to 
    #         ... $(WS_PROXIES["makie_proxy"].request.url)"
    #         """
    #     end
    #     msg = Genie.Requests.payload(:raw)
    #     @debug "ws proxy <-: $(String(deepcopy(msg)))"
    #     Base.@lock Genie.Router.wslock try
    #         sleep(0.1)
    #         HTTP.WebSockets.send(WS_PROXIES["makie_proxy"], msg)
    #     catch e
    #         @error "ws proxy <-: $(e)"
    #     end
    # end

    return nothing
end

function __init__()
    configure_makie_server!()
    WGLMakie.activate!(resize_to = :parent)
end

end