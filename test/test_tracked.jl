using Test
using SeeSign
using Base


@tracked_struct Person begin
    health::Symbol
    age::Int
    location::Int
end

Base.zero(::Type{Person}) = Person(:neutral, 0, 0)


@testset "validation and contracts" begin
    person = TrackedVector{Person}(undef, 3)
    for i in eachindex(person)
        person[i] = Person(:neutral, 20 * i, i)
    end
    reset_tracking!(person)
    @test person[1] == Person(:neutral, 20, 1)
    @test (1,:health) ∈ gotten(person)
    @test (1,:age) ∈ gotten(person)
    @test (1,:location) ∈ gotten(person)
    @test person[2].health == :neutral
    @test (2, :health) ∈ gotten(person)
    person[3].location = 5
    @test (3, :location) ∉ gotten(person)
    @test (3, :location) ∈ changed(person)
    reset_gotten!(person)
    @test isempty(gotten(person))
    @test (3, :location) ∈ changed(person)
    reset_tracking!(person)
    @test isempty(changed(person))
end


@testset "how linear indices work" begin
    arr = zeros(Int, 3, 7)
    for i in 1:21
        arr[i] = i
    end
    @test arr[13] == 13
    # CartesianIndices convert from linear to a Cartesian index.
    ci = CartesianIndices(arr)
    ci15 = ci[13]
    # You don't usually access the .I member directly.
    @test ci15.I == (1, 5)
    # Either of these works.
    @test arr[ci15] == 13
    @test arr[1, 5] == 13
    # Go the other way with LinearIndices.
    li = LinearIndices(arr)
    li15 = li[ci15]
    @test li15 == 13
    @test li[1, 5] == 13
end
