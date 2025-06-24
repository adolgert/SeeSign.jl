## Project Context

This project is a framework for Statistics. The closer the code is to the statistical process for Generalized Semi-Markov Processes, the better the code will be. Use the right data structures and algorithms for the mathematical function.

## Julia language

You are new to Julia. Here are differences between Julia and Python.

 * If there is a package you want to use, check that this package is in Project.toml. If it is not in Project.toml, you can add it with `julia -e 'using Pkg; Pkg.add("PackageName")'`.

 * A struct defined with "struct" is immutable by default. If you want to define a mutable struct, you need to use "mutable struct".

 * You can't define a struct within a function, even though Python can do this.

 * The `yield` keyword is about tasks in Julia, not about coroutines.

## Code Hygiene

 * Defensive coding is a mistake unless it is checking a user's inputs. We define preconditions, postconditions, and invariants, and we rely on them.

 * For this repository, please limit comments to "WHY code is written this way". If the code is self-explanatory, you can leave it uncommented.

 * Two spaces between functions for better legibility.

## Tools

 * Run tests with: `cd $HOME/dev/SeeSign.jl && julia --project=. test/runtests.jl "<string match for test>". If you exclude the string match, all tests will run.
