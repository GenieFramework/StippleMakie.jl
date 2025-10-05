using Stipple
using Stipple.Genie.HTTPUtils.HTTP.URIs
using Stipple.Genie.Generator.UUIDs
 
const BACKEND_HOST = "127.0.0.1"
const SOCKETS = Dict{Int, Dict{UUID, WebSocket}}()
const SERVERS = Dict{Int, HTTP.Server}()

function proxy_handler(stream::HTTP.Stream;
    genie_port = Genie.config.server_port,
    genie_ws_port = something(Genie.config.websockets_port, genie_port),
    makie_path = URI(Bonito.SERVER_CONFIGURATION.proxy_url[]).path,
    makie_port = Bonito.SERVER_CONFIGURATION.listen_port[])
 
    startswith(makie_path, "/") || (makie_path = "/$makie_path")
 
    req = stream.message
    host_port = parse(Int, split(Dict(req.headers)["Host"], ":")[2])
    is_makie_path = startswith(req.target, Regex(makie_path * "(/|\$)"))
    
    is_makie_path && (req.target = req.target[length(makie_path) + 1:end])
 
    if WebSockets.isupgrade(req)
        backend_port = is_makie_path ? makie_port : genie_ws_port
        HTTP.WebSockets.upgrade(stream) do client_ws
            client_id = uuid4()
            sockets = get!(Dict{UUID, WebSocket}, SOCKETS, host_port)
            push!(sockets, client_id => client_ws)
 
            HTTP.WebSockets.open("http://$BACKEND_HOST:$backend_port$(req.target)") do backend_ws
                backend_id = uuid4()
                push!(sockets, backend_id => backend_ws)
                @async begin
                    for msg in backend_ws
                        try
                            @debug("Sending to client '$(backend_ws.request.target)': $msg")
                            HTTP.WebSockets.send(client_ws, msg)
                        catch err
                            error("Proxy error in backend connection: $err")
                            close(client_ws)
                            break
                        end
                    end
                    @debug "Closing backend connection."
                    close(client_ws)
                    delete!(sockets, client_id)
                end
 
                for msg in client_ws
                    try
                        @debug("Sending to backend  '$(client_ws.request.target)': $msg")
                        HTTP.WebSockets.send(backend_ws, msg)
                    catch err
                        error("Proxy error in client connection: $err\nclosing Stream handler")
                        break
                    end
                end
                @debug "Closing client connection."
                close(backend_ws)
                delete!(sockets, backend_id)
                delete!(sockets, client_id) # just to be sure ...
            end
        end
    else
        backend_port = is_makie_path ? makie_port : genie_port
        backend_url = "http://$BACKEND_HOST:$backend_port$(req.target)"
        backend_response = HTTP.request(req.method, backend_url; headers=req.headers, body=req.body)
        closeread(stream)
        req.body = read(stream)
        req.response = backend_response
        req.response.request = req
        startwrite(stream)
        write(stream, req.response.body)
        nothing
    end
end

function startproxy(port = 8080;
    genie_port = Genie.config.server_port,
    genie_ws_port = something(Genie.config.websockets_port, genie_port),
    makie_path = URI(Bonito.SERVER_CONFIGURATION.proxy_url[]).path,
    makie_port = Bonito.SERVER_CONFIGURATION.listen_port[])

    # make sure makie_path is set to a non-empty string
    if strip(makie_path, '/') == ""
        makie_path = "/_makie_"
        configure_makie_server!(proxy_url = makie_path)
    end

    function handler(stream::HTTP.Stream)
        proxy_handler(stream; genie_port, genie_ws_port, makie_path, makie_port)
    end

    server = HTTP.listen!(handler, port)
    SERVERS[port] = server
end

function closeproxy(server; force::Bool = false)
    if force
        HTTP.Servers.shutdown(server.on_shutdown)
        close(server.listener)
        Base.@lock server.connections_lock begin
            for c in server.connections
                HTTP.Servers.requestclose!(c)
            end
        end
        port = parse(Int, server.listener.hostport)
        haskey(SOCKETS, port) && [try close(ws) finally end for ws in values(SOCKETS[port])]
        delete!(SOCKETS, port)
    end
    close(server)
    return true
end

function closeproxy(port::Integer; force::Bool = false)
    haskey(SERVERS, port) || return false
    closeproxy(SERVERS[port]; force)
    delete!(SERVERS, port)
    return true
end

function close_all_proxies(; force::Bool = false)
    for port in keys(SERVERS)
        closeproxy(port; force)
    end
end