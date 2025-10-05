module StippleMakie

using Stipple
using Stipple.Genie.HTTPUtils.HTTP
using Stipple.Genie.HTTPUtils.HTTP.WebSockets

using WGLMakie
using WGLMakie.Bonito
using WGLMakie.Bonito.URIs
using WGLMakie.Bonito.Observables

include("proxy.jl")

# import Stipple.Genie.Router.WS_PROXIES
WS_PROXIES = isdefined(Genie.Router, :WS_PROXIES) ? Genie.Router.WS_PROXIES : Dict{String, Any}()

export MakieFigure, init_makiefigures, makie_figure, makie_dom, configure_makie_server!, WGLMakie, Makie, nginx_config, once, onready
export startproxy, closeproxy

"""
    once(f::Function, o::Observable)

Runs a function once when the observable changes the first time.

# Example
```julia
o = Observable(1)
once(o) do
    println("I only say this once!")
end
```
"""
function once(f::Function, o::Observable)
    ref = Ref{ObserverFunction}()
    ref[] = on(o) do o
        f(o)
        off(ref[])
    end
end

Base.@kwdef mutable struct MakieFigure
    fig::Figure = Figure()
    session::Union{Nothing, Bonito.Session} = nothing
    id = -1
end

"""
    onready(f::Function, mf::MakieFigure)

Runs a function once when the viewport of the figure is ready.

# Example
```julia
onready(fig1) do
    Makie.scatter(fig1.fig[1, 1], (0:4).^3)
end
"""
onready(f::Function, mf::MakieFigure) = once(_ -> f(), mf.fig.scene.viewport)

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

"""
    configure_makie_server!(; listen_host = nothing, listen_port = Bonito.SERVER_CONFIGURATION.listen_port[], proxy_url = nothing, proxy_port = nothing)

Configures the Makie server with the specified settings. The default values are taken from Makie's and Genie server configuration.
Parameters:

    - `listen_host`: The host to listen on, defaults to `Genie.config.websockets_host`, e.g. `0.0.0.0` or `127.0.0.1`
    - `listen_port`: The port to listen on, e.g. `8001`
    - `proxy_url`: The URL to proxy traffic to, e.g. `'/makie'` or `'http:localhost:8080/_makie_'`
    - `proxy_port`: The port to proxy traffic to, e.g. `8080`, this setting overrides port settings in `proxy_url`
"""
 function configure_makie_server!(; listen_host = nothing, listen_port = nothing, proxy_url = nothing, proxy_port = nothing)
    listen_url = something(listen_host, Genie.config.websockets_host, Genie.config.server_host)
    listen_port = something(listen_port, Bonito.SERVER_CONFIGURATION.listen_port[])
    proxy_url = something(proxy_url, Genie.config.websockets_exposed_host, "")
    isempty(proxy_url) || startswith(proxy_url, "http") || startswith(proxy_url, "/") || (proxy_url = "http://$proxy_url")
    uri = URI(something(proxy_url, ""))
    host, port, path, scheme = uri.host, uri.port, uri.path, uri.scheme
    # let the proxy port override the port
    port = something(proxy_port, port)
    
    # if port is defined but host is not, set host to localhost
    if !isempty(port) && isempty(host)
        host = "127.0.0.1"
        scheme = "http"
    end

    uri = isempty(port) ? URI(; host, path, scheme) : URI(; host, port, path, scheme)
    proxy_url = "$uri"
    Bonito.configure_server!(; listen_url, listen_port, proxy_url)
    (; listen_url, listen_port, proxy_url)
end

"""
    nginx_config(; genie_port = nothing, makie_port = Bonito.SERVER_CONFIGURATION.listen_port[], makie_proxy_path = nothing)

Generates an nginx configuration for proxying traffic to Makie and Genie servers.

If not specified otherwise, the configuration takes into account the current configuration of the Genie and Makie servers.
"""
function nginx_config(proxy_port = 8080; genie_port = nothing, makie_port = Bonito.SERVER_CONFIGURATION.listen_port[], makie_proxy_path = nothing)
    genie_port = something(genie_port, Genie.config.websockets_port,  Genie.config.server_port)
    makie_proxy_path = lstrip(something(makie_proxy_path, isempty(Bonito.SERVER_CONFIGURATION.proxy_url[]) ? "_makie_" : Bonito.SERVER_CONFIGURATION.proxy_url[]), '/')
    """
    http {
        upstream makie {
            server localhost:$makie_port;
        }

        upstream genie {
            server localhost:$genie_port;
        }

        server {
            listen $proxy_port;

            # Proxy traffic to /$makie_proxy_path/* to http://localhost:$makie_port;/*
            location /$makie_proxy_path/ {
                proxy_pass http://makie/;
                
                # WebSocket headers
                proxy_http_version 1.1;
                proxy_set_header Upgrade \$http_upgrade;
                proxy_set_header Connection "upgrade";
                
                # Preserve headers
                proxy_set_header Host \$host;
                proxy_set_header X-Real-IP \$remote_addr;
                proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto \$scheme;
            }

            # Proxy all other traffic to http://localhost:$genie_port/*
            location / {
                proxy_pass http://genie/;

                # WebSocket headers
                proxy_http_version 1.1;
                proxy_set_header Upgrade \$http_upgrade;
                proxy_set_header Connection "upgrade";
                
                # Preserve headers
                proxy_set_header Host \$host;
                proxy_set_header X-Real-IP \$remote_addr;
                proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto \$scheme;
            }
        }
    }
    """
end

function __init__()
    configure_makie_server!()
    WGLMakie.activate!(resize_to = :parent)
end

end