# StippleMakie

StippleMakie is a plugin for the GenieFramework to enable Makie plots via WGLMakie


### Demo App
Don't be surprised if the first loading time of the Webpage is very long (about a minute).
```julia
using Stipple
using Stipple.ReactiveTools
using StippleUI
import Genie.Server.openbrowser

using StippleMakie

Stipple.enable_model_storage(false)

# ------------------------------------------------------------------------------------------------

# WGLMakie uses a separate server to serve the websocket connections for the figures. 
# If you are serving your Genie app to external users, you might need to set this port explicitly.
# configure_makie_server!(listen_port = 8001)

# If you have only one port available, you can use the built-in proxy server to serve both the Genie app and the WGLMakie server
# on the same port. The proxy server will forward requests to the appropriate backend based on the URL path.
# The proxy server will listen on port 8080 by default. You can change this by providing the `port` argument.

# In order to use a proxy server, Makie needs to be configured to use a proxy URL.
# When using an external proxy, you have to set a valid proxy URL.
# If you are using the built-in proxy server, `start_proxy()` autmatically sets "/_makie_" as the proxy URL.
# You can change this by providing the `proxy_url` argument.

# Example settings for a pmanual proxy configuration:
# proxy_host and proxy_port will be taken from the Genie configuration.
# configure_makie_server!(proxy_url = "/_makie_")
# configure_makie_server!(listen_port = 8001, proxy_url = "/makie")
# configure_makie_server!(listen_port = 8001, proxy_url = "/makie", proxy_port = 8081)

# start the proxy server (if required)
startproxy()
# startproxy(8080)

@app MakieDemo begin
    @out fig1 = MakieFigure()
    @out fig2 = MakieFigure()
    @in hello = false

    @onbutton hello @notify "Hello World!"

    @onchange isready begin
        init_makiefigures(__model__)
        # the viewport changes when the figure is ready to be written to
        onready(fig1) do
            Makie.scatter(fig1.fig[1, 1], (0:4).^3)
            Makie.heatmap(fig2.fig[1, 1], rand(5, 5))
            Makie.scatter(fig2.fig[1, 2], (0:4).^3)
        end
    end
end

UI::ParsedHTMLString = row(cell(class = "st-module", style = "height: 80vh; width: 100%", column(class = "full-height", [
    h4(col = "auto", "MakiePlot 1")
    cell(class = "full-width", makie_figure(:fig1))

    h4(col = "auto", "MakiePlot 2")
    cell(class = "full-width", makie_figure(:fig2))

    btn(col = "auto", "Hello", class = "q-mt-lg", @click(:hello), color = "primary")
])))

ui() = UI

route("/") do
    WGLMakie.Page()
    global model = @init MakieDemo    
    html!(ui, layout = Stipple.ReactiveTools.DEFAULT_LAYOUT(head_content = [makie_dom(model)]), model = model, context = @__MODULE__)
    # page(model, ui, head_content = [makie_dom(model)]) |> Stipple.html
    # alternatively, you can use the following line to render the page without the default layout
    # page(model, ui, prepend = makie_dom(model)) |> html
end

up()
openbrowser(port = 8080) # open the browser at the proxy port!
```
![Form](docs/demoapp.png)

As WGLMakie needs its own websocket port to communicate with the plots, operation behind a proxy needs more careful proxy setup.
After setting up the server, e.g. with `configure_makie_server!(listen_port = 8001, proxy_base_path = "/makie")`, `nginx_conf()` returns a valid
configuration for an nginx server to accomodate running Genie and Makie over the same port.
Here's the nginx configuration for above configuration.

```
http {
    upstream makie {
        server localhost:8001;
    }

    upstream genie {
        server localhost:8000;
    }

    server {
        listen 8080;

        # Proxy traffic to /makie/* to http://localhost:8001/*
        location /makie {
            proxy_pass http://makie/;
            
            # WebSocket headers
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            
            # Preserve headers
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Proxy all other traffic to http://localhost:8000/*
        location / {
            proxy_pass http://genie/;

            # WebSocket headers
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            
            # Preserve headers
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
```
