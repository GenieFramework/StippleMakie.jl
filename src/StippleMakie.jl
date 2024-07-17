module StippleMakie

using Stipple

using WGLMakie
using WGLMakie.Bonito
using Stipple.HTTP

import Stipple.Genie.Router.WS_PROXIES

export MakieFigure, init_makiefigures, makie_figure, makie_dom, setup_makie_proxy, WGLMakie, Bonito

WGLMakie.activate!(resize_to = :parent)

@kwdef mutable struct MakieFigure
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
    proxy = get(WS_PROXIES, "makie_proxy", "")
    proxy isa String || close(proxy)
    Bonito.session_dom(session, DOM.div()) |> string
end

function Base.empty!(mf::Union{MakieFigure, R{MakieFigure}})
    for c in contents(mf.fig.layout)
        empty!(c.blockscene)
        delete!(c)
    end
    trim!(mf.fig.layout)
end

function setup_makie_proxy(; listen_port = 8001, proxy_port = 8000)
    Bonito.configure_server!(listen_url = "localhost", listen_port = listen_port, proxy_url = "http://localhost:$proxy_port/makie_proxy")
    Genie.Router.WS_PROXIES["makie_proxy"] = "ws://localhost:$listen_port/dummy"

    routename = join(filter(!isempty, [Genie.config.base_path, Genie.config.websockets_base_path, "makie_proxy/assets/:bonito"]), "/")
    println("routename: $routename")
    route("/$routename") do
        asset = params(:bonito)
        @debug "loading asset via proxy: $asset"
        res = HTTP.get("http://localhost:$listen_port/assets/$asset")

        if endswith(asset, "-Websocket.bundled.js")
            # modify the Makie websocket client to suppress control messages from Genie's ws server
            res.body = replace(String(res.body), r"( *)const binary = new Uint8Array\(evt.data\);" => 
            s"""
            \1const binary = new Uint8Array(evt.data);
            \1
            \1if (typeof(evt.data) == 'string') {
            \1    return resolve(null);
            \1}
            """, "send_pings();" => "") |> Vector{UInt8}
        end

        return res
    end

    Genie.Router.channel("/", named = :makie) do
        # @debug begin
        #     client = Genie.Requests.wsclient()
        #     """ws proxy in: from $(client.request.target) to 
        #     ... $(WS_PROXIES["makie_proxy"].request.url)"
        #     """
        # end
        msg = Genie.Requests.payload(:raw)
        @debug "ws proxy <-: $(String(deepcopy(msg)))"
        HTTP.WebSockets.send(WS_PROXIES["makie_proxy"], msg)
    end
    return nothing
end

end