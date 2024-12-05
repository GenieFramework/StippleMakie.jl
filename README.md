# StippleMakie

StippleMakie is a plugin for the GenieFramework to enable Makie plots via WGLMakie


WGLMakie needs its own websocket port to communicate with the plots. Therefore operation behind a proxy needs a second available port,
which can be configured by `configure_makie_server!`. In the future we might integrate automatic port forwarding with the Genie settings, but that's still work in progress.

### Demo App
Don't be surprised if the first loading time of the Webpage is very long (about a minute).
```
using Stipple, Stipple.ReactiveTools
using StippleMakie

using WGLMakie

Stipple.enable_model_storage(false)

# -----------------------------------------------------------------------------------------------------

configure_makie_server!()

@app MakieDemo begin
    @out fig1 = MakieFigure()
    @out fig2 = MakieFigure()

    @onchange isready begin
        init_makiefigures(__model__)
        sleep(0.3)
        Makie.scatter(fig1.fig[1, 1], (0:4).^3)
        Makie.heatmap(fig2.fig[1, 1], rand(5, 5))
        Makie.scatter(fig2.fig[1, 2], (0:4).^3)
    end
end

UI::ParsedHTMLString = column(style = "height: 80vh; width: 98vw", [
    h4("MakiePlot 1")
    cell(col = 4, class = "full-width", makie_figure(:fig1))
    h4("MakiePlot 2")
    cell(col = 4, class = "full-width", makie_figure(:fig2))
])

ui() = UI

route("/") do
    WGLMakie.Page()
    global model = @init MakieDemo    
    html!(ui, layout = Stipple.ReactiveTools.DEFAULT_LAYOUT(head_content = [makie_dom(model)]), model = model, context = @__MODULE__)

    # alternatively, you can use the following line to render the page without the default layout
    # page(model, ui, prepend = makie_dom(model)) |> html
end

up(open_browser = true)
```
![Form](docs/demoapp.png)