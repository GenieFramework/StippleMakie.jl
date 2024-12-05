using Test

using Stipple
using Stipple.ReactiveTools

# testing can be down without StippleUI, it only breaks rendering which we don't test
# using StippleUI

using StippleMakie

Stipple.enable_model_storage(false)

# ------------------------------------------------------------------------------------------------

# if required set a different port, url or proxy_port for Makie's websocket communication, e.g.
# otherwise, Genie's settings are applied for listen_url and proxy_url and Makie's (Bonito's) settings are applied for the ports
configure_makie_server!(listen_port = rand(8081:8999))

@app MakieDemo begin
    @out fig1 = MakieFigure()
    @out fig2 = MakieFigure()

    @onchange isready begin
        init_makiefigures(__model__)
        # Wait until plots are ready to be written to
        # sleep(0.3)
        # Makie.scatter(fig1.fig[1, 1], (0:4).^3)
        # Makie.heatmap(fig2.fig[1, 1], rand(5, 5))
        # Makie.scatter(fig2.fig[1, 2], (0:4).^3)
    end
end


UI::ParsedHTMLString = column(style = "height: 80vh; width: 98vw", [
    h4("MakiePlot 1")
    cell(col = 4, class = "full-width", makie_figure(:fig1))
    h4("MakiePlot 2")
    cell(col = 4, class = "full-width", makie_figure(:fig2))
])

ui() = UI

model = @init MakieDemo    
response = html!(ui, layout = Stipple.ReactiveTools.DEFAULT_LAYOUT(head_content = [makie_dom(model)]), model = model, context = @__MODULE__)

model.isready[] = true

@test model isa MakieDemo
@test response isa Genie.Requests.HTTP.Response
@test makie_dom(model) isa ParsedHTMLString

nothing