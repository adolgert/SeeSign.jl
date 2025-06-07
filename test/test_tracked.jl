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
    @test (1,) ∈ gotten(person)
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
