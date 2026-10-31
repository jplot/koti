# frozen_string_literal: true

# DOP2 answers built with the gem's own encoder, for fakes that serve leaves.
module Dop2Leaves
  def dop2_field(type, value) = Miele::Sdk::Dop2::Field.new(type:, value:)

  def dop2_leaf(unit, attribute, fields, idx1: 0, idx2: 0)
    Miele::Sdk::Dop2.encode(Miele::Sdk::Dop2::Leaf.new(unit:, attribute:, idx1:, idx2:, fields:))
  end
end

RSpec.configure { it.include Dop2Leaves }
