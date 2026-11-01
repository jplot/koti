# frozen_string_literal: true

# The eight parameters of 1/1574 the app reads before it writes the required ones, none of them required. A
# change of nil drops one.
module OvenParameters
  def oven_parameters(changes = {})
    types = { 1 => :u8, 2 => :u8, 6 => :u16, 7 => :u16, 12 => :u32, 30 => :u8, 31 => :u8 }
    values = types.transform_values { dop2_field(:struct, { 1 => dop2_field(:u8, 0), 4 => dop2_field(it, 0) }) }
    power = dop2_field(:struct, { 1 => dop2_field(:u8, 0), 3 => dop2_field(:u8, 0) })
    values.merge(15 => power).merge(changes).compact
  end
end

RSpec.configure { it.include OvenParameters }
