This repository has code written in Julia. I know you are trained on Python and other languages, so you know how code works, but there are a few properties of Julia that I've seen you confuse with Python. Here are some of the differences:

 * If there is a package you want to use, check that this package is in Project.toml. If it is not in Project.toml, you can add it with `julia -e 'using Pkg; Pkg.add("PackageName")'`.

 * In Julia a struct defined with "struct" is immutable by default. If you want to define a mutable struct, you need to use "mutable struct".

 * In Julia, you can't define a struct within a function, even though Python can do this.


For this repository, please limit comments to "WHY code is written this way". If the code is self-explanatory, you can leave it uncommented.

