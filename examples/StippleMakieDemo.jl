using Stipple, Stipple.ReactiveTools
using StippleMakie
using WGLMakie

Bonito.configure_server!(listen_url = "localhost", listen_port = 8003, proxy_url = "")
# setup_makie_proxy(listen_port = 8003, proxy_port = 8000)

@app MD begin
    @out fig1 = MakieFigure()
    @out fig2 = MakieFigure()

    @onchange isready begin
        init_makiefigures(__model__)
        sleep(0.3)
        Makie.scatter(fig1.fig[1, 1], (0:4).^3)
        # Makie.heatmap(fig2.fig[1, 1], rand(5, 5))
        # Makie.scatter(fig2.fig[1, 2], (0:4).^3)
    end
end

ui() = column(style = "height: 80vh; width: 98vw", [
    h4("MakiePlot 1")
    cell(col = 4, class = "full-width", makie_figure(:fig1))
    h4("MakiePlot 2")
    cell(col = 4, class = "full-width", makie_figure(:fig2))
])

route("/") do
    global model
    model = @init MD
    makie = makie_dom(model)
    # html!(ui, layout = Stipple.ReactiveTools.DEFAULT_LAYOUT(head_content = [makie]), model = model, context = @__MODULE__)
    page(model, ui, prepend = ParsedHTMLString(makie_dom(model))) |> html
end

up(open_browser = true)