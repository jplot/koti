# frozen_string_literal: true

# The parameters of 1/1574. A change of nil drops one.
module OvenParameters
  # The eight the app reads before it writes the required ones, none of them required.
  def oven_parameters(changes = {})
    types = { 1 => :u8, 2 => :u8, 6 => :u16, 7 => :u16, 12 => :u32, 30 => :u8, 31 => :u8 }
    values = types.transform_values { dop2_field(:struct, { 1 => dop2_field(:u8, 0), 4 => dop2_field(it, 0) }) }
    power = dop2_field(:struct, { 1 => dop2_field(:u8, 0), 3 => dop2_field(:u8, 0) })
    values.merge(15 => power).merge(changes).compact
  end

  # Every parameter the SDK writes, readable and writable (mask 9), with a value the app's sections show.
  def shown_parameters(changes = {})
    values = { 1 => [:u8, 1], 2 => [:u8, 1], 6 => [:u16, 18_000], 7 => [:u16, 6_000], 8 => [:u16, 0], 9 => [:u16, 0],
               10 => [:u16, 0], 12 => [:u32, 1_800], 13 => [:u64, 0], 14 => [:u64, 0], 18 => [:u8, 1],
               30 => [:u8, 1], 31 => [:u8, 1] }
    shown = values.transform_values { |(type, current)| shown_parameter(type, current) }
    option = dop2_field(:struct, { 1 => dop2_field(:u8, 9), 2 => dop2_field(:bool, false) })
    options = [21, 24, 25, 26, 27].to_h { [it, option] }
    power = dop2_field(:struct, { 1 => dop2_field(:u8, 9), 2 => dop2_field(:u8, 0x7F), 3 => dop2_field(:u8, 1) })
    shown.merge(options, 15 => power).merge(changes).compact
  end

  def shown_parameter(type, current, mask: 9, min: 0)
    dop2_field(:struct, { 1 => dop2_field(:u8, mask), 2 => dop2_field(type, min), 4 => dop2_field(type, current) })
  end
end

RSpec.configure { it.include OvenParameters }
