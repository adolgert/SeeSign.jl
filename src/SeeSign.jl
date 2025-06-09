module SeeSign

include("higher_order.jl")
include("changed.jl")
include("tracked.jl")
include("sim.jl")

export StepArray, changed, previous_value, accept

end
