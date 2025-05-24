using SeeSign
using Documenter

DocMeta.setdocmeta!(SeeSign, :DocTestSetup, :(using SeeSign); recursive=true)

makedocs(;
    modules=[SeeSign],
    authors="Andrew Dolgert <github@dolgert.com>",
    sitename="SeeSign.jl",
    format=Documenter.HTML(;
        canonical="https://adolgert.github.io/SeeSign.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/adolgert/SeeSign.jl",
    devbranch="main",
)
