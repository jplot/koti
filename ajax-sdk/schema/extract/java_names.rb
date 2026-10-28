# frozen_string_literal: true

module Schema
  module Extract
    # Full names of the classes a decompiled .java file names: obfuscated classes share short names across packages,
    # and the app's v2 and v3 APIs both have a GetDeviceAboutResponse.
    module JavaNames
      module_function

      # @return [String, nil] the class the file imports under that name, or else the one of its own package
      def qualify(name, source)
        return unless name

        source[/^import ([\w.]+\.#{name});/, 1] || [source[/^package ([\w.]+);/, 1], name].compact.join('.')
      end
    end
  end
end
