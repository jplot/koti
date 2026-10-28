# frozen_string_literal: true

module Schema
  module Extract
    # The protobuf file descriptors the app's generated Java carries as string literals, read back as bytes: jadx prints
    # each byte of these ISO-8859-1 strings as a unicode or simple escape.
    module JavaLiterals
      MARK = 'internalBuildGeneratedFileFrom(new String[]{'
      SEPARATORS = " \n\t\r,"
      ESCAPES = { 'n' => 10, 't' => 9, 'r' => 13, 'b' => 8, 'f' => 12, '"' => 34, '\\' => 92 }.freeze

      module_function

      # @return [Array<String>] the bytes of each FileDescriptorProto a decompiled .java file builds
      def descriptors(source)
        found = []
        offset = 0
        while (start = source.index(MARK, offset))
          bytes, offset = array(source, start + MARK.length)
          found << bytes if bytes
        end
        found
      end

      # A brace inside a segment is a byte, so segments are read whole.
      def array(source, index)
        codes = []
        while (character = source[index])
          return [codes.pack('C*'), index + 1] if character == '}'
          return [nil, index] unless character == '"' || SEPARATORS.include?(character)

          index = character == '"' ? segment(source, index + 1, codes) : index + 1
        end
        [nil, index]
      end

      def segment(source, index, codes)
        while (character = source[index]) && character != '"'
          if character == '\\'
            index = escape(source, index + 1, codes)
          else
            codes << character.ord
            index += 1
          end
        end
        index + 1
      end

      def escape(source, index, codes)
        return unicode(source, index, codes) if source[index] == 'u'

        codes << ESCAPES.fetch(source[index])
        index + 1
      end

      def unicode(source, index, codes)
        codes << source[index + 1, 4].to_i(16)
        index + 5
      end
    end
  end
end
