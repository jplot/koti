# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # A user-authored behavior script formula; the bridge currently restricts its creation.
      class BehaviorScriptFormula < Base
        resource_type 'behavior_script_formula'
        operations :create, :delete
      end
    end
  end
end
