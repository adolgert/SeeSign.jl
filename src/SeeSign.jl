module SeeSign

include("higher_order.jl")
include("changed.jl")
include("sim.jl")
include("tracked.jl")

export StepArray, changed, previous_value, accept

end
