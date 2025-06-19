# SeeSign

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://adolgert.github.io/SeeSign.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://adolgert.github.io/SeeSign.jl/dev/)
[![Build Status](https://github.com/adolgert/SeeSign.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/adolgert/SeeSign.jl/actions/workflows/CI.yml?query=branch%3Amain)


## How to Run Test

The usual way to run tests works:
```julia
julia --project=. -e "using Pkg; Pkg.test()"
```
If you want to run specific tests, then use `runtests.jl` as a script.
The "Board" argument will run only tests that have "Board" in the testset name.
```julia
julia --project=. test/runtests.jl "Board"
```
