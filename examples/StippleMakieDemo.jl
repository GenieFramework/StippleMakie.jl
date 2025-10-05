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
# If you are using the built-in proxy server, `startproxy()` autmatically sets "/_makie_" as the proxy URL.
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